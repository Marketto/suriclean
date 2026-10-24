package com.suriclean.app

import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Process
import android.os.storage.StorageManager
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Progress callback + cancel flag for long jobs. */
class Reporter(val cancel: AtomicBoolean = AtomicBoolean(false), private val onUpdate: (String, Float?) -> Unit = { _, _ -> }) {
    private var last = 0L
    val cancelled get() = cancel.get()
    fun report(text: String, progress: Float? = null, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - last < 90) return
        last = now
        onUpdate(text, progress)
    }
}

/** One walk of the shared storage, reused by several zones. */
class StorageIndex(
    val files: List<Pair<File, Long>>,          // files >= 1 MB with size
    val apks: List<File>,
    val emptyDirs: List<File>,
    val junkFiles: List<File>,
    val thumbDirs: List<File>,
    val dirSizes: Map<String, Long>,             // folders down to 4 levels
    val total: Long,
    val built: Long = System.currentTimeMillis(),
    val trashed: List<File> = emptyList(),      // .trashed-* / old .pending-* left by MediaStore
) {
    val stale get() = System.currentTimeMillis() - built > 15 * 60_000

    companion object {
        private val keepEmpty = setOf("DCIM", "Download", "Pictures", "Movies", "Music", "Documents", "Alarms", "Notifications",
            "Podcasts", "Ringtones", "Audiobooks", "Recordings", "Android")

        fun build(rep: Reporter): StorageIndex {
            val root = Fs.root
            val rootPath = root.absolutePath
            val baseDepth = rootPath.count { it == '/' }
            val skip = setOf("$rootPath/Android/data", "$rootPath/Android/obb", Trash.dir.absolutePath)
            val files = ArrayList<Pair<File, Long>>()
            val apks = ArrayList<File>()
            val empty = ArrayList<File>()
            val junk = ArrayList<File>()
            val thumbs = ArrayList<File>()
            val trashed = ArrayList<File>()
            val sizes = HashMap<String, Long>()
            var total = 0L
            var n = 0
            val stack = ArrayDeque<File>()
            stack.add(root)
            while (stack.isNotEmpty()) {
                if (rep.cancelled) break
                val d = stack.removeLast()
                val kids = d.listFiles() ?: continue
                if (kids.isEmpty() && d != root && d.name !in keepEmpty && !d.absolutePath.startsWith("$rootPath/Android")) empty.add(d)
                for (k in kids) {
                    n++
                    if (n % 300 == 0) rep.report(L.t("and.rep.sniffed", n, Fs.pretty(k)))
                    if (Fs.isSymlink(k)) continue
                    if (k.isDirectory) {
                        if (k.absolutePath in skip) continue
                        if (k.name == ".thumbnails") thumbs.add(k)
                        stack.add(k)
                        continue
                    }
                    val len = k.length()
                    total += len
                    // add to every ancestor folder down to 4 levels
                    var p: File? = k.parentFile
                    while (p != null && p.absolutePath.length >= rootPath.length) {
                        val depth = p.absolutePath.count { it == '/' } - baseDepth
                        if (depth in 1..4) sizes[p.absolutePath] = (sizes[p.absolutePath] ?: 0L) + len
                        if (p.absolutePath == rootPath) break
                        p = p.parentFile
                    }
                    val name = k.name.lowercase()
                    if (len >= 1_048_576) files.add(k to len)
                    if (name.endsWith(".apk") || name.endsWith(".xapk") || name.endsWith(".apks")) apks.add(k)
                    if (name.endsWith(".log") || name.endsWith(".tmp") || name.startsWith("~$") || name == ".ds_store") junk.add(k)
                    if (name.startsWith(".trashed-") || (name.startsWith(".pending-") && Fs.daysSince(k.lastModified()) > 7)) trashed.add(k)
                }
            }
            rep.report(L.t("and.rep.exploreDone", n), force = true)
            return StorageIndex(files, apks, empty, junk, thumbs, sizes, total, trashed = trashed)
        }
    }
}

object Scanners {
    fun item(f: File, name: String = f.name, detail: String? = null, risk: Risk, rec: Boolean, badges: List<String> = emptyList(),
             size: Long? = null, date: Long? = null, rep: Reporter? = null, minSize: Long = 0): Item? {
        if (!f.exists()) return null
        val s = size ?: Fs.sizeOf(f, rep?.cancel)
        if (s < minSize) return null
        return Item(Fs.nextId(), f.absolutePath, name, detail ?: Fs.pretty(f.parentFile ?: f), s, date ?: f.lastModified(),
            risk, rec, badges, isDir = f.isDirectory)
    }

    fun map(idx: StorageIndex): List<Item> {
        val root = Fs.root
        val out = ArrayList<Item>()
        out.add(Item(Fs.nextId(), root.absolutePath, L.t("and.map.phone"), "📱", idx.total, null, Risk.CAREFUL, false, listOf(L.t("and.badge.all")), isDir = true))
        val base = root.absolutePath.count { it == '/' }
        for ((path, size) in idx.dirSizes) {
            val depth = path.count { it == '/' } - base
            val threshold = if (depth <= 1) 20L * 1_048_576 else 50L * 1_048_576
            if (size < threshold) continue
            val f = File(path)
            out.add(Item(Fs.nextId(), path, f.name, Fs.pretty(f), size, null, Risk.CAREFUL, false, isDir = true))
        }
        return out
    }

    fun chats(rep: Reporter): List<Item> {
        val r = Fs.root
        val bases = listOf(
            "Android/media/com.whatsapp/WhatsApp/Media" to "WhatsApp",
            "WhatsApp/Media" to "WhatsApp",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media" to "WhatsApp Business",
            "WhatsApp Business/Media" to "WhatsApp Business",
            "Android/media/org.telegram.messenger/Telegram" to "Telegram",
            "Telegram" to "Telegram",
            "Android/media/org.thunderdog.challegram/Telegram X" to "Telegram X",
            "Android/media/org.thoughtcrime.securesms" to "Signal",
        )
        val out = ArrayList<Item>()
        for ((i, pair) in bases.withIndex()) {
            val (rel, app) = pair
            if (rep.cancelled) break
            rep.report(app, i.toFloat() / bases.size)
            val base = File(r, rel)
            val kids = base.listFiles() ?: continue
            for (k in kids) {
                if (!k.isDirectory) continue
                val label = k.name.removePrefix(app + " ").removePrefix("WhatsApp ").removePrefix("Telegram ").ifEmpty { k.name }
                val statuses = k.name == ".Statuses"
                val newest = Fs.newest(k)
                val it = item(k, "$app · ${if (statuses) L.t("and.chats.statuses") else label}",
                    detail = L.t("and.chats.detail", Fs.pretty(k), Fs.relative(newest)),
                    risk = if (statuses) Risk.SAFE else Risk.REVIEW, rec = statuses,
                    badges = listOf(if (statuses) L.t("and.badge.expired24") else "💬 $app"),
                    date = newest, rep = rep, minSize = 1_048_576) ?: continue
                out.add(it)
            }
        }
        return out
    }

    private fun keepScore(f: File): Int {
        val p = f.absolutePath.lowercase()
        var s = p.count { it == '/' } * 10
        if ("/download" in p) s += 1000
        if ("/whatsapp" in p || "/telegram" in p) s += 400
        if (" (1)" in f.name || "copy" in f.name.lowercase() || "copia" in f.name.lowercase()) s += 500
        if ("/sent/" in p) s += 300
        return s
    }

    fun duplicates(idx: StorageIndex, rep: Reporter): List<Item> {
        val bySize = idx.files.groupBy { it.second }.values.filter { it.size > 1 }
        val candidates = ArrayList<List<Pair<File, Long>>>()
        for ((i, g) in bySize.withIndex()) {
            if (rep.cancelled) return emptyList()
            rep.report(L.t("and.rep.fingerprints", g[0].first.name), i.toFloat() / bySize.size.coerceAtLeast(1) * 0.4f)
            g.groupBy { Fs.partialHash(it.first) ?: it.first.absolutePath }.values.filter { it.size > 1 }.forEach { candidates.add(it) }
        }
        val groups = ArrayList<List<Pair<File, Long>>>()
        for ((i, g) in candidates.withIndex()) {
            if (rep.cancelled) return emptyList()
            rep.report(L.t("and.rep.sha", g[0].first.name), 0.4f + i.toFloat() / candidates.size.coerceAtLeast(1) * 0.6f)
            g.groupBy { Fs.fullHash(it.first, rep.cancel) ?: it.first.absolutePath }.values.filter { it.size > 1 }.forEach { groups.add(it) }
        }
        groups.sortByDescending { it[0].second * it.size }
        val out = ArrayList<Item>()
        for ((gid, g) in groups.withIndex()) {
            val sorted = g.sortedBy { keepScore(it.first) }
            val label = L.t("and.dup.group", sorted[0].first.name, g.size, Fs.bytes(g[0].second))
            for ((j, p) in sorted.withIndex()) {
                val keep = j == 0
                out.add(Item(Fs.nextId(), p.first.absolutePath, p.first.name, Fs.pretty(p.first.parentFile ?: p.first), p.second,
                    p.first.lastModified(), if (keep) Risk.CAREFUL else Risk.SAFE, !keep,
                    listOf(if (keep) L.t("and.badge.keep") else L.t("and.badge.copy")), group = gid, groupLabel = label))
            }
        }
        return out
    }

    private fun badgeFor(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "mkv", "mov", "avi", "3gp", "webm" -> L.t("and.badge.video")
            "zip", "rar", "7z", "tar", "gz" -> L.t("and.badge.archive")
            "jpg", "jpeg", "png", "heic", "webp" -> L.t("and.badge.photo")
            "mp3", "m4a", "wav", "flac", "opus", "ogg" -> L.t("and.badge.audio")
            "apk", "xapk" -> L.t("and.badge.installer")
            "pdf" -> L.t("and.badge.document")
            else -> null
        }
    }

    fun big(idx: StorageIndex): List<Item> =
        idx.files.filter { it.second >= 100L * 1_048_576 }.sortedByDescending { it.second }.take(250).map { (f, s) ->
            Item(Fs.nextId(), f.absolutePath, f.name, L.t("and.big.detail", Fs.pretty(f.parentFile ?: f), Fs.relative(f.lastModified())),
                s, f.lastModified(), Risk.CAREFUL, false, listOfNotNull(badgeFor(f.name)))
        }

    fun downloads(rep: Reporter): List<Item> {
        val kids = Fs.downloads.listFiles() ?: return emptyList()
        val out = ArrayList<Item>()
        for ((i, k) in kids.withIndex()) {
            if (rep.cancelled) break
            rep.report(Fs.pretty(k), i.toFloat() / kids.size)
            val d = Fs.newest(k)
            val days = Fs.daysSince(d)
            if (days < 90) continue
            item(k, detail = L.t("and.dl.detail", Fs.relative(d)), risk = Risk.REVIEW, rec = false,
                badges = listOfNotNull(if (days > 365) L.t("and.badge.overYear") else null, badgeFor(k.name)),
                date = d, rep = rep, minSize = 100 * 1024)?.let { out.add(it) }
        }
        return out
    }

    fun apks(idx: StorageIndex): List<Item> {
        val dl = Fs.downloads.absolutePath
        return idx.apks.map { f ->
            val inDl = f.absolutePath.startsWith(dl)
            Item(Fs.nextId(), f.absolutePath, f.name, "${Fs.pretty(f.parentFile ?: f)} · ${Fs.relative(f.lastModified())}",
                f.length(), f.lastModified(), if (inDl) Risk.SAFE else Risk.REVIEW, inDl, listOf(L.t("and.badge.installer")))
        }.filter { it.size > 50 * 1024 }
    }

    fun junk(idx: StorageIndex): List<Item> {
        val out = ArrayList<Item>()
        for (t in idx.thumbDirs) {
            item(t, L.t("and.junk.thumbs", t.parentFile?.name ?: ""), risk = Risk.SAFE, rec = true, badges = listOf(L.t("and.badge.thumbs")))?.let { if (it.size > 0) out.add(it) }
        }
        val lost = File(Fs.root, "LOST.DIR")
        item(lost, "LOST.DIR", risk = Risk.SAFE, rec = true, badges = listOf(L.t("and.badge.lost")))?.let { if (it.size > 0) out.add(it) }
        for (f in idx.junkFiles) {
            out.add(Item(Fs.nextId(), f.absolutePath, f.name, Fs.pretty(f.parentFile ?: f), f.length(), f.lastModified(), Risk.SAFE, true, listOf(L.t("and.badge.logTmp"))))
        }
        for (d in idx.emptyDirs) {
            out.add(Item(Fs.nextId(), d.absolutePath, d.name, Fs.pretty(d.parentFile ?: d), 0, d.lastModified(), Risk.SAFE, true, listOf(L.t("and.badge.emptyDir")), isDir = true))
        }
        return out
    }
}

/** What only Shizuku can see: the Android/data and Android/obb folders of every app. */
object HiddenAreas {
    private fun root() = Fs.root.absolutePath

    /** The cache folders apps keep in Android/data: always safe to remove, the apps rebuild them. */
    fun caches(rep: Reporter): List<Item> {
        if (!ShizukuBridge.ready()) return emptyList()
        rep.report(L.t("and.rep.hidden"), 0.95f, force = true)
        val r = root()
        return ShizukuBridge.du("$r/Android/data/*/cache $r/Android/data/*/files/cache $r/Android/data/*/files/Cache").mapNotNull { (path, bytes) ->
            if (bytes < 256 * 1024) return@mapNotNull null
            val pkg = path.removePrefix("$r/Android/data/").substringBefore('/')
            Item(Fs.nextId(), path, L.t("and.hidden.cache", pkg), L.t("and.hidden.cacheDetail", pkg), bytes, null,
                Risk.SAFE, true, listOf(L.t("and.badge.cache"), L.t("and.badge.viaShizuku")), isDir = true)
        }
    }

    /** Sizes of Android/data and Android/obb (and of each app inside), for the storage map. */
    fun mapEntries(): List<Item> {
        if (!ShizukuBridge.ready()) return emptyList()
        val r = root()
        val out = ArrayList<Item>()
        for ((path, bytes) in ShizukuBridge.du("$r/Android/data $r/Android/obb $r/Android/data/* $r/Android/obb/*")) {
            val top = path == "$r/Android/data" || path == "$r/Android/obb"
            if (!top && bytes < 50L * 1_048_576) continue
            out.add(Item(Fs.nextId(), path, path.substringAfterLast('/'), Fs.pretty(File(path)), bytes, null, Risk.CAREFUL, false,
                listOf(L.t("and.badge.viaShizuku")), isDir = true))
        }
        return out
    }
}

object SystemAreas {
    private val dated = Regex("^msgstore-\\d{4}-\\d{2}-\\d{2}\\..*")

    private fun installed(ctx: Context, pkg: String): Boolean = try {
        ctx.packageManager.getPackageInfo(pkg, 0); true
    } catch (e: Exception) { false }

    fun scan(ctx: Context, idx: StorageIndex, rep: Reporter): List<Item> {
        val root = Fs.root
        val out = ArrayList<Item>()
        fun add(it: Item?) { if (it != null && it.size > 0) out.add(it) }

        rep.report(L.t("and.rep.chatBackups"), 0f, force = true)
        for (path in listOf("Android/media/com.whatsapp/WhatsApp/Databases", "Android/media/com.whatsapp.w4b/WhatsApp Business/Databases",
                "WhatsApp/Databases", "WhatsApp Business/Databases")) {
            val app = if (path.contains("Business")) "WhatsApp Business" else "WhatsApp"
            for (f in File(root, path).listFiles().orEmpty()) {
                if (!f.isFile || !dated.matches(f.name)) continue
                add(Scanners.item(f, L.t("and.sys.oldBackup", app, f.name.substringAfter("msgstore-").take(10)),
                    L.t("and.sys.oldBackupDetail"), Risk.SAFE, true, listOf(L.t("and.badge.oldBackup"))))
            }
        }

        rep.report(L.t("and.rep.updates"), 0.2f, force = true)
        for (name in listOf("downloaded_rom", ".Ota", "ota", "OTA", "fota", "SystemUpdate", ".ota_package")) {
            add(Scanners.item(File(root, name), L.t("and.sys.otaDir", name), Fs.pretty(File(root, name)),
                Risk.SAFE, true, listOf(L.t("and.badge.installed")), rep = rep, minSize = 1_048_576))
        }
        for (f in root.listFiles().orEmpty()) {
            val n = f.name.lowercase()
            if (f.isFile && n.endsWith(".zip") && (n == "update.zip" || n.contains("ota") || n.startsWith("miui_") || n.contains("rom")))
                add(Scanners.item(f, L.t("and.sys.otaFile", f.name), null, Risk.REVIEW, false, listOf(L.t("and.badge.update"))))
        }

        rep.report(L.t("and.rep.leftovers"), 0.4f, force = true)
        for (d in File(root, "Android/obb").listFiles().orEmpty()) {
            if (rep.cancelled) break
            if (d.isDirectory && !installed(ctx, d.name))
                add(Scanners.item(d, L.t("and.sys.obb", d.name), L.t("and.sys.notInstalled"), Risk.SAFE, true, listOf(L.t("and.badge.uninstalled")), rep = rep))
        }
        for (d in File(root, "Android/media").listFiles().orEmpty()) {
            if (rep.cancelled) break
            if (d.isDirectory && !installed(ctx, d.name))
                add(Scanners.item(d, L.t("and.sys.media", d.name), L.t("and.sys.mediaDetail"),
                    Risk.REVIEW, false, listOf(L.t("and.badge.uninstalled")), rep = rep, minSize = 256 * 1024))
        }

        rep.report(L.t("and.rep.oemLogs"), 0.6f, force = true)
        for (name in listOf("MIUI/debug_log", "log", "logs", "Log", "bugreports", "mtklog", "debuglogger", "Android/log", "tombstones", "Huawei/log")) {
            add(Scanners.item(File(root, name), L.t("and.sys.log", name), Fs.pretty(File(root, name)), Risk.SAFE, true, listOf(L.t("and.badge.log")), rep = rep, minSize = 64 * 1024))
        }

        rep.report(L.t("and.rep.appBackups"), 0.75f, force = true)
        for (name in listOf("TitaniumBackup", "SwiftBackup", "MIUI/backup", "Huawei/Backup", "Backups", "backups", "backup", "Smart Switch", "OnePlus Switch", "OPBackup")) {
            add(Scanners.item(File(root, name), L.t("and.sys.backup", name), L.t("and.sys.backupDetail"),
                Risk.CAREFUL, false, listOf(L.t("and.badge.backup")), rep = rep, minSize = 1_048_576))
        }

        rep.report(L.t("and.rep.trashed"), 0.9f, force = true)
        for (f in idx.trashed) {
            val pending = f.name.startsWith(".pending-")
            add(Scanners.item(f, f.name.substringAfter('-').substringAfter('-').ifEmpty { f.name },
                if (pending) L.t("and.sys.pending", Fs.pretty(f.parentFile ?: f)) else L.t("and.sys.trashed", Fs.pretty(f.parentFile ?: f)),
                Risk.SAFE, true, listOf(if (pending) L.t("and.badge.interrupted") else L.t("and.badge.alreadyTrashed"))))
        }
        return out
    }
}

object AppsInfo {
    fun hasUsageAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= 29)
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        else @Suppress("DEPRECATION") ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Returns the user apps (with size and last use) and the total cache of all apps. */
    fun scan(ctx: Context, rep: Reporter): Pair<List<Item>, Long> {
        val pm = ctx.packageManager
        val apps = pm.getInstalledApplications(0).filter {
            (it.flags and ApplicationInfo.FLAG_SYSTEM == 0 || it.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0) && it.packageName != ctx.packageName
        }
        val ssm = ctx.getSystemService(StorageStatsManager::class.java)
        val usm = ctx.getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        val usage = try { usm.queryAndAggregateUsageStats(now - 2L * 365 * 86_400_000, now) } catch (e: Exception) { emptyMap() }
        val out = ArrayList<Item>()
        var cache = 0L
        for ((i, a) in apps.withIndex()) {
            if (rep.cancelled) break
            val label = a.loadLabel(pm).toString()
            rep.report(label, i.toFloat() / apps.size.coerceAtLeast(1))
            var size = 0L
            var appCache = 0L
            var appBytes = 0L
            try {
                val st = ssm.queryStatsForPackage(StorageManager.UUID_DEFAULT, a.packageName, Process.myUserHandle())
                size = st.appBytes + st.dataBytes
                appBytes = st.appBytes
                appCache = st.cacheBytes
                cache += st.cacheBytes
            } catch (e: Exception) { /* no usage access */ }
            val last = usage[a.packageName]?.lastTimeUsed?.takeIf { it > 0 }
            val days = Fs.daysSince(last)
            val badges = buildList {
                if (last == null) add(L.t("and.badge.neverOpened")) else if (days > 365) add(L.t("and.badge.sleepYear")) else if (days > 90) add(L.t("and.badge.sleepMonths"))
                if (size > 0) add(L.t("and.badge.appData", Fs.bytes(appBytes), Fs.bytes(size - appBytes)))
                if (appCache > 20L * 1_048_576) add(L.t("and.badge.appCache", Fs.bytes(appCache)))
            }
            val version = try { pm.getPackageInfo(a.packageName, 0).versionName ?: "" } catch (e: Exception) { "" }
            out.add(Item(Fs.nextId(), a.sourceDir ?: a.packageName, label,
                (last?.let { L.t("and.apps.lastUse", Fs.relative(it)) } ?: L.t("and.apps.noUse")) + if (version.isNotEmpty()) " · v$version" else "",
                size, last, Risk.CAREFUL, false, badges, packageName = a.packageName, appBytes = appBytes))
        }
        return out to cache
    }
}

object StorageBreakdown {
    /** Splits the used storage the way Android counts it (needs usage access for the app part). */
    fun compute(ctx: Context, measuredFiles: Long?): List<Slice> {
        val ssm = ctx.getSystemService(StorageStatsManager::class.java)
        val total = try { ssm.getTotalBytes(StorageManager.UUID_DEFAULT) } catch (e: Exception) { Fs.storage().first }
        val free = try { ssm.getFreeBytes(StorageManager.UUID_DEFAULT) } catch (e: Exception) { Fs.storage().second }
        val used = (total - free).coerceAtLeast(0)
        val out = ArrayList<Slice>()
        var accounted = 0L
        try {
            val user = Process.myUserHandle()
            val ext = ssm.queryExternalStatsForUser(StorageManager.UUID_DEFAULT, user)
            val media = ext.imageBytes + ext.videoBytes
            out.add(Slice(L.t("and.slice.media"), media, Kawaii.pink, L.t("and.slice.mediaNote")))
            out.add(Slice(L.t("and.slice.audio"), ext.audioBytes, Kawaii.lilac, L.t("and.slice.audioNote")))
            val other = (ext.totalBytes - media - ext.audioBytes - ext.appBytes).coerceAtLeast(0)
            out.add(Slice(L.t("and.slice.other"), other, Kawaii.lemon, L.t("and.slice.otherNote")))
            accounted += media + ext.audioBytes + other
            if (AppsInfo.hasUsageAccess(ctx)) {
                val st = ssm.queryStatsForUser(StorageManager.UUID_DEFAULT, user)
                val data = (st.dataBytes - st.cacheBytes).coerceAtLeast(0)
                out.add(Slice(L.t("and.slice.apps"), st.appBytes, Kawaii.sky, L.t("and.slice.appsNote")))
                out.add(Slice(L.t("and.slice.appData"), data, Kawaii.orange, L.t("and.slice.appDataNote")))
                out.add(Slice(L.t("and.slice.appCache"), st.cacheBytes, Kawaii.mint, L.t("and.slice.appCacheNote")))
                accounted += st.appBytes + data + st.cacheBytes
            }
        } catch (e: Exception) {
            if (measuredFiles != null) { out.add(Slice(L.t("and.slice.measured"), measuredFiles, Kawaii.lemon, L.t("and.slice.measuredNote"))); accounted += measuredFiles }
        }
        val rest = (used - accounted).coerceAtLeast(0)
        out.add(Slice(if (AppsInfo.hasUsageAccess(ctx)) L.t("and.slice.system") else L.t("and.slice.systemApps"),
            rest, Kawaii.coral, if (AppsInfo.hasUsageAccess(ctx)) L.t("and.slice.systemNote") else L.t("and.slice.systemAppsNote")))
        out.add(Slice(L.t("and.slice.free"), free, Kawaii.mint.copy(alpha = 0.35f), L.t("and.slice.freeNote")))
        return out.filter { it.bytes > 0 }
    }
}

/** SuriClean's own trash on the shared storage: moving is instant, emptying frees the space. */
object Trash {
    val dir: File get() = File(Fs.root, ".SuriCestino")

    fun move(ctx: Context, items: List<Item>, rep: Reporter): Triple<List<Long>, Long, List<String>> {
        dir.mkdirs()
        File(dir, ".nomedia").createNewFile()
        val removed = ArrayList<Long>()
        val failed = ArrayList<String>()
        var bytes = 0L
        val scan = ArrayList<String>()
        for ((i, it) in items.withIndex()) {
            if (rep.cancelled) break
            rep.report(it.name, i.toFloat() / items.size.coerceAtLeast(1), force = true)
            val f = File(it.path)
            if (!f.exists()) { removed.add(it.id); continue }
            var dest = File(dir, f.name)
            var k = 1
            while (dest.exists()) { dest = File(dir, "${f.nameWithoutExtension} ($k)${if (f.extension.isNotEmpty()) "." + f.extension else ""}"); k++ }
            val hidden = it.path.contains("/Android/data/") || it.path.contains("/Android/obb/")
            val ok = if (hidden && !f.canWrite() && ShizukuBridge.ready()) ShizukuBridge.remove(it.path)   // rebuildable caches: gone for good
                else f.renameTo(dest) || (f.isDirectory && f.listFiles().isNullOrEmpty() && f.delete())
            if (ok) { removed.add(it.id); bytes += it.size; scan.add(f.absolutePath) } else failed.add(it.name)
        }
        if (scan.isNotEmpty()) MediaScannerConnection.scanFile(ctx, scan.toTypedArray(), null, null)
        rep.report(L.t("and.rep.done"), 1f, force = true)
        return Triple(removed, bytes, failed)
    }

    fun size(): Long = Fs.sizeOf(dir)

    fun empty(): Long {
        val before = size()
        dir.listFiles()?.forEach { if (it.name != ".nomedia") it.deleteRecursively() }
        return before - size()
    }
}
