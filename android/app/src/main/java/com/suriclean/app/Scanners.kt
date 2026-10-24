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
                    if (n % 300 == 0) rep.report("$n elementi annusati · ${Fs.pretty(k)}")
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
            rep.report("Esplorazione finita: $n elementi", force = true)
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
        out.add(Item(Fs.nextId(), root.absolutePath, "Memoria del telefono", "📱", idx.total, null, Risk.CAREFUL, false, listOf("📱 tutto"), isDir = true))
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
                val it = item(k, "$app · ${if (statuses) "Stati (scaduti)" else label}",
                    detail = "${Fs.pretty(k)} · ultimo file ${Fs.relative(newest)}",
                    risk = if (statuses) Risk.SAFE else Risk.REVIEW, rec = statuses,
                    badges = listOf(if (statuses) "⏰ scaduti dopo 24 h" else "💬 $app"),
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
            rep.report("Confronto impronte: ${g[0].first.name}", i.toFloat() / bySize.size.coerceAtLeast(1) * 0.4f)
            g.groupBy { Fs.partialHash(it.first) ?: it.first.absolutePath }.values.filter { it.size > 1 }.forEach { candidates.add(it) }
        }
        val groups = ArrayList<List<Pair<File, Long>>>()
        for ((i, g) in candidates.withIndex()) {
            if (rep.cancelled) return emptyList()
            rep.report("SHA-256 di ${g[0].first.name}", 0.4f + i.toFloat() / candidates.size.coerceAtLeast(1) * 0.6f)
            g.groupBy { Fs.fullHash(it.first, rep.cancel) ?: it.first.absolutePath }.values.filter { it.size > 1 }.forEach { groups.add(it) }
        }
        groups.sortByDescending { it[0].second * it.size }
        val out = ArrayList<Item>()
        for ((gid, g) in groups.withIndex()) {
            val sorted = g.sortedBy { keepScore(it.first) }
            val label = "${sorted[0].first.name} · ${g.size} copie da ${Fs.bytes(g[0].second)}"
            for ((j, p) in sorted.withIndex()) {
                val keep = j == 0
                out.add(Item(Fs.nextId(), p.first.absolutePath, p.first.name, Fs.pretty(p.first.parentFile ?: p.first), p.second,
                    p.first.lastModified(), if (keep) Risk.CAREFUL else Risk.SAFE, !keep,
                    listOf(if (keep) "💎 da tenere" else "👯 copia"), group = gid, groupLabel = label))
            }
        }
        return out
    }

    private fun badgeFor(name: String): String? {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "mkv", "mov", "avi", "3gp", "webm" -> "🎬 video"
            "zip", "rar", "7z", "tar", "gz" -> "📦 archivio"
            "jpg", "jpeg", "png", "heic", "webp" -> "🖼️ foto"
            "mp3", "m4a", "wav", "flac", "opus", "ogg" -> "🎵 audio"
            "apk", "xapk" -> "📦 installer"
            "pdf" -> "📄 documento"
            else -> null
        }
    }

    fun big(idx: StorageIndex): List<Item> =
        idx.files.filter { it.second >= 100L * 1_048_576 }.sortedByDescending { it.second }.take(250).map { (f, s) ->
            Item(Fs.nextId(), f.absolutePath, f.name, "${Fs.pretty(f.parentFile ?: f)} · modificato ${Fs.relative(f.lastModified())}",
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
            item(k, detail = "Scaricato ${Fs.relative(d)}", risk = Risk.REVIEW, rec = false,
                badges = listOfNotNull(if (days > 365) "🦕 più di un anno" else null, badgeFor(k.name)),
                date = d, rep = rep, minSize = 100 * 1024)?.let { out.add(it) }
        }
        return out
    }

    fun apks(idx: StorageIndex): List<Item> {
        val dl = Fs.downloads.absolutePath
        return idx.apks.map { f ->
            val inDl = f.absolutePath.startsWith(dl)
            Item(Fs.nextId(), f.absolutePath, f.name, "${Fs.pretty(f.parentFile ?: f)} · ${Fs.relative(f.lastModified())}",
                f.length(), f.lastModified(), if (inDl) Risk.SAFE else Risk.REVIEW, inDl, listOf("📦 installer"))
        }.filter { it.size > 50 * 1024 }
    }

    fun junk(idx: StorageIndex): List<Item> {
        val out = ArrayList<Item>()
        for (t in idx.thumbDirs) {
            item(t, "Miniature · ${t.parentFile?.name ?: ""}", risk = Risk.SAFE, rec = true, badges = listOf("🖼️ si ricreano da sole"))?.let { if (it.size > 0) out.add(it) }
        }
        val lost = File(Fs.root, "LOST.DIR")
        item(lost, "LOST.DIR", risk = Risk.SAFE, rec = true, badges = listOf("💾 frammenti recuperati"))?.let { if (it.size > 0) out.add(it) }
        for (f in idx.junkFiles) {
            out.add(Item(Fs.nextId(), f.absolutePath, f.name, Fs.pretty(f.parentFile ?: f), f.length(), f.lastModified(), Risk.SAFE, true, listOf("🧾 log/temporaneo")))
        }
        for (d in idx.emptyDirs) {
            out.add(Item(Fs.nextId(), d.absolutePath, d.name, Fs.pretty(d.parentFile ?: d), 0, d.lastModified(), Risk.SAFE, true, listOf("📂 cartella vuota"), isDir = true))
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

        rep.report("Vecchi backup delle chat", 0f, force = true)
        for (path in listOf("Android/media/com.whatsapp/WhatsApp/Databases", "Android/media/com.whatsapp.w4b/WhatsApp Business/Databases",
                "WhatsApp/Databases", "WhatsApp Business/Databases")) {
            val app = if (path.contains("Business")) "WhatsApp Business" else "WhatsApp"
            for (f in File(root, path).listFiles().orEmpty()) {
                if (!f.isFile || !dated.matches(f.name)) continue
                add(Scanners.item(f, "Backup vecchio di $app · ${f.name.substringAfter("msgstore-").take(10)}",
                    "Il backup più recente (msgstore.db…) resta al suo posto", Risk.SAFE, true, listOf("🗄️ backup vecchio")))
            }
        }

        rep.report("Aggiornamenti già installati", 0.2f, force = true)
        for (name in listOf("downloaded_rom", ".Ota", "ota", "OTA", "fota", "SystemUpdate", ".ota_package")) {
            add(Scanners.item(File(root, name), "Aggiornamento di sistema scaricato · $name", Fs.pretty(File(root, name)),
                Risk.SAFE, true, listOf("⬇️ già installato"), rep = rep, minSize = 1_048_576))
        }
        for (f in root.listFiles().orEmpty()) {
            val n = f.name.lowercase()
            if (f.isFile && n.endsWith(".zip") && (n == "update.zip" || n.contains("ota") || n.startsWith("miui_") || n.contains("rom")))
                add(Scanners.item(f, "Pacchetto di aggiornamento · ${f.name}", null, Risk.REVIEW, false, listOf("⬇️ aggiornamento")))
        }

        rep.report("Avanzi di app disinstallate", 0.4f, force = true)
        for (d in File(root, "Android/obb").listFiles().orEmpty()) {
            if (rep.cancelled) break
            if (d.isDirectory && !installed(ctx, d.name))
                add(Scanners.item(d, "Dati di gioco (OBB) · ${d.name}", "L'app non è più installata", Risk.SAFE, true, listOf("👻 app disinstallata"), rep = rep))
        }
        for (d in File(root, "Android/media").listFiles().orEmpty()) {
            if (rep.cancelled) break
            if (d.isDirectory && !installed(ctx, d.name))
                add(Scanners.item(d, "Cartella media · ${d.name}", "L'app non è più installata: dentro possono esserci foto o file tuoi",
                    Risk.REVIEW, false, listOf("👻 app disinstallata"), rep = rep, minSize = 256 * 1024))
        }

        rep.report("Log dei produttori", 0.6f, force = true)
        for (name in listOf("MIUI/debug_log", "log", "logs", "Log", "bugreports", "mtklog", "debuglogger", "Android/log", "tombstones", "Huawei/log")) {
            add(Scanners.item(File(root, name), "Log di sistema · $name", Fs.pretty(File(root, name)), Risk.SAFE, true, listOf("📜 log"), rep = rep, minSize = 64 * 1024))
        }

        rep.report("Backup di app", 0.75f, force = true)
        for (name in listOf("TitaniumBackup", "SwiftBackup", "MIUI/backup", "Huawei/Backup", "Backups", "backups", "backup", "Smart Switch", "OnePlus Switch", "OPBackup")) {
            add(Scanners.item(File(root, name), "Backup · $name", "Controlla di non averne più bisogno (o che sia già sul PC/cloud)",
                Risk.CAREFUL, false, listOf("🗄️ backup"), rep = rep, minSize = 1_048_576))
        }

        rep.report("File già nel cestino di Android", 0.9f, force = true)
        for (f in idx.trashed) {
            val pending = f.name.startsWith(".pending-")
            add(Scanners.item(f, f.name.substringAfter('-').substringAfter('-').ifEmpty { f.name },
                (if (pending) "Download o salvataggio interrotto · " else "Già nel cestino di Android · ") + Fs.pretty(f.parentFile ?: f),
                Risk.SAFE, true, listOf(if (pending) "⏸️ interrotto" else "🗑️ già cestinato")))
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
                if (last == null) add("👻 mai aperta?") else if (days > 365) add("😴 dorme da 1+ anno") else if (days > 90) add("💤 dorme da mesi")
                if (size > 0) add("📦 app ${Fs.bytes(appBytes)} · 💾 dati ${Fs.bytes(size - appBytes)}")
                if (appCache > 20L * 1_048_576) add("🧽 cache ${Fs.bytes(appCache)}")
            }
            val version = try { pm.getPackageInfo(a.packageName, 0).versionName ?: "" } catch (e: Exception) { "" }
            out.add(Item(Fs.nextId(), a.sourceDir ?: a.packageName, label,
                (last?.let { "Ultimo uso ${Fs.relative(it)}" } ?: "Nessun uso registrato") + if (version.isNotEmpty()) " · v$version" else "",
                size, last, Risk.CAREFUL, false, badges, packageName = a.packageName))
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
            out.add(Slice("Foto e video", media, Kawaii.pink, "DCIM, Pictures, Movies e i media delle chat"))
            out.add(Slice("Musica e audio", ext.audioBytes, Kawaii.lilac, "brani, vocali, podcast"))
            val other = (ext.totalBytes - media - ext.audioBytes - ext.appBytes).coerceAtLeast(0)
            out.add(Slice("Altri file", other, Kawaii.lemon, "Download, documenti, APK e il resto della memoria condivisa"))
            accounted += media + ext.audioBytes + other
            if (AppsInfo.hasUsageAccess(ctx)) {
                val st = ssm.queryStatsForUser(StorageManager.UUID_DEFAULT, user)
                val data = (st.dataBytes - st.cacheBytes).coerceAtLeast(0)
                out.add(Slice("App (programmi)", st.appBytes, Kawaii.sky, "le app installate"))
                out.add(Slice("Dati delle app", data, Kawaii.orange, "chat, giochi, musica offline… dentro ogni app: si svuotano dalla scheda ⚙️ dell'app"))
                out.add(Slice("Cache delle app", st.cacheBytes, Kawaii.mint, "si ricrea da sola: «Pulisci» o la scheda ⚙️ dell'app"))
                accounted += st.appBytes + data + st.cacheBytes
            }
        } catch (e: Exception) {
            if (measuredFiles != null) { out.add(Slice("File misurati", measuredFiles, Kawaii.lemon, "la memoria condivisa")); accounted += measuredFiles }
        }
        val rest = (used - accounted).coerceAtLeast(0)
        out.add(Slice(if (AppsInfo.hasUsageAccess(ctx)) "Sistema Android" else "Sistema e app",
            rest, Kawaii.coral, if (AppsInfo.hasUsageAccess(ctx)) "il sistema operativo e i file nascosti" else "dai a Suri l'«Accesso ai dati di utilizzo» per separare le app dal sistema"))
        out.add(Slice("Libero", free, Kawaii.mint.copy(alpha = 0.35f), "spazio disponibile adesso"))
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
            val ok = f.renameTo(dest) || (f.isDirectory && f.listFiles().isNullOrEmpty() && f.delete())
            if (ok) { removed.add(it.id); bytes += it.size; scan.add(f.absolutePath) } else failed.add(it.name)
        }
        if (scan.isNotEmpty()) MediaScannerConnection.scanFile(ctx, scan.toTypedArray(), null, null)
        rep.report("Fatto!", 1f, force = true)
        return Triple(removed, bytes, failed)
    }

    fun size(): Long = Fs.sizeOf(dir)

    fun empty(): Long {
        val before = size()
        dir.listFiles()?.forEach { if (it.name != ".nomedia") it.deleteRecursively() }
        return before - size()
    }
}
