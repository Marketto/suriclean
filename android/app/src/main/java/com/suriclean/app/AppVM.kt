package com.suriclean.app

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class AppVM(app: Application) : AndroidViewModel(app) {
    private val ctx get() = getApplication<Application>()
    private val prefs = app.getSharedPreferences("suri", 0)

    val results = mutableStateMapOf<Category, List<Item>>()
    var selection by mutableStateOf(setOf<Long>())
    var busy by mutableStateOf<Busy?>(null)
    var celebration by mutableStateOf<Celebration?>(null)
    var view by mutableStateOf<Category?>(null)
    var toast by mutableStateOf<String?>(null)
    var storage by mutableStateOf(0L to 0L)          // total, free
    var trashSize by mutableStateOf(0L)
    var appCache by mutableStateOf(0L)
    var hasFiles by mutableStateOf(true)
    var hasUsage by mutableStateOf(true)
    /** The "may I come in?" dialog, and the step-by-step permission tour behind it. */
    var askPerms by mutableStateOf(false)
    private var permTour = false
    private var permTourScan = false
    private val permAsked = mutableSetOf<String>()
    private var permsChecked = false
    var muted by mutableStateOf(prefs.getBoolean("muted", false))
    var remix by mutableStateOf(prefs.getBoolean("remix", false))
        private set
    var freed by mutableStateOf(prefs.getLong("freed", 0))
        private set
    var update by mutableStateOf<AppUpdate?>(null)
    var autoUpdate by mutableStateOf(prefs.getBoolean("autoUpdate", true))
        private set
    val version: String = try { app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "0" } catch (e: Exception) { "0" }

    /** Package names waiting for the system uninstall dialog. */
    val uninstallQueue = ArrayDeque<String>()
    var pendingIntent by mutableStateOf<Intent?>(null)
    var breakdown by mutableStateOf<List<Slice>>(emptyList())
    /** Set when the «clear all caches» screen is opened, to detect phones that refuse it. */
    var cacheRequestAt = 0L

    private var cancel = AtomicBoolean(false)
    private var index: StorageIndex? = null

    init {
        Chiptune.muted = muted
        Chiptune.remix = remix
        refresh()
        viewModelScope.launch {
            delay(4000)
            while (true) { checkUpdate(false); delay(6L * 3600 * 1000) }
        }
    }

    // ───────── state helpers ─────────
    fun items(c: Category) = results[c] ?: emptyList()
    fun total(l: List<Item>) = l.sumOf { it.size }
    fun displayTotal(c: Category) = if (c.viewOnly) items(c).maxOfOrNull { it.size } ?: 0 else total(items(c))
    val foundTotal get() = Category.entries.filter { !it.viewOnly }.sumOf { total(items(it)) }
    val recommendedTotal get() = Category.entries.filter { !it.viewOnly }.sumOf { c -> items(c).filter { it.recommended }.sumOf { it.size } }

    fun showToast(s: String) {
        toast = s
        viewModelScope.launch { delay(3500); if (toast == s) toast = null }
    }

    fun refresh() {
        hasFiles = if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager() else true
        hasUsage = AppsInfo.hasUsageAccess(ctx)
        if (!permsChecked) {
            permsChecked = true
            if ((!hasFiles || !hasUsage) && prefs.getString("permsSnoozed", "") != version) askPerms = true
        }
        viewModelScope.launch(Dispatchers.IO) {
            val s = Fs.storage()
            val t = Trash.size()
            val b = try { StorageBreakdown.compute(ctx, null) } catch (e: Exception) { emptyList() }
            withContext(Dispatchers.Main) { storage = s; trashSize = t; breakdown = b }
            // drop what disappeared meanwhile
            val gone = results.values.flatten().filter { it.packageName == null && !File(it.path).exists() }.map { it.id }.toSet()
            if (gone.isNotEmpty()) withContext(Dispatchers.Main) {
                for (c in results.keys.toList()) results[c] = results[c]!!.filter { it.id !in gone }
                selection = selection - gone
                index = null
            }
            if (AppsInfo.hasUsageAccess(ctx) && results[Category.APPS] != null) {
                val pm = ctx.packageManager
                val removedApps = items(Category.APPS).filter { a ->
                    try { pm.getPackageInfo(a.packageName!!, 0); false } catch (e: Exception) { true }
                }.map { it.id }.toSet()
                if (removedApps.isNotEmpty()) withContext(Dispatchers.Main) {
                    results[Category.APPS] = items(Category.APPS).filter { it.id !in removedApps }
                    selection = selection - removedApps
                }
            }
        }
    }

    fun toggleRemix() {
        remix = !remix; Chiptune.remix = remix; prefs.edit().putBoolean("remix", remix).apply()
        if (muted) toggleMute()
        Chiptune.sfx(Sfx.POP)
        showToast(if (remix) "🎧 Remix ON! Wub-wub~ ドロップ!" else "🎵 Torna la musica originale ♪")
    }

    fun toggleMute() { muted = !muted; Chiptune.muted = muted; prefs.edit().putBoolean("muted", muted).apply() }
    fun setAuto(v: Boolean) { autoUpdate = v; prefs.edit().putBoolean("autoUpdate", v).apply() }

    fun level(): Triple<String, Float, String> {
        val gb = freed / 1e9
        val steps = listOf(1.0 to "🐣 Cucciolina curiosa", 5.0 to "🌱 Scavatrice in erba", 20.0 to "👀 Sentinella del disco", 50.0 to "👑 Regina delle dune")
        var prev = 0.0
        for ((lim, name) in steps) { if (gb < lim) return Triple(name, ((gb - prev) / (lim - prev)).toFloat(), "prossimo livello a ${lim.toInt()} GB"); prev = lim }
        return Triple("🌟 Leggenda del deserto", 1f, "livello MAX!! Sugoi~")
    }

    fun greeting(): String {
        val (tot, free) = storage
        val pct = if (tot > 0) ((tot - free) * 100 / tot).toInt() else 0
        if (results.isEmpty()) return when {
            pct >= 90 -> "Kyaa~! Sono Suri-chan 🐾 La memoria è piena al $pct%… emergenza kawaii!! Premi il bottone e la faccio tornare pika-pika ✨"
            pct >= 70 -> "Konnichiwa~! Sono Suri-chan 🐾 La memoria è al $pct%. Andiamo a caccia di spazio insieme? Ganbarō! ☆"
            else -> "Yahoo~! Sono Suri-chan 🐾 La memoria sta benino ($pct%), ma un po' di brillantezza non guasta mai ✧"
        }
        return "Sugoi!! Ho scovato ${Fs.bytes(foundTotal)} di roba ✨ e ${Fs.bytes(recommendedTotal)} puoi buttarli senza pensieri! Tocca una zona~ ♡"
    }

    // ───────── selection ─────────
    fun toggle(it: Item) { selection = if (it.id in selection) selection - it.id else selection + it.id; Chiptune.sfx(Sfx.POP) }
    fun setSel(ids: Collection<Long>, on: Boolean) { selection = if (on) selection + ids else selection - ids.toSet(); Chiptune.sfx(if (on) Sfx.COIN else Sfx.POP) }
    fun selRecommended(c: Category) { val l = items(c); selection = selection - l.map { it.id }.toSet() + l.filter { it.recommended }.map { it.id }; Chiptune.sfx(Sfx.COIN) }
    fun selected(c: Category) = items(c).filter { it.id in selection }

    private fun setResults(c: Category, list: List<Item>) {
        selection = selection - items(c).map { it.id }.toSet() + list.filter { it.recommended }.map { it.id }
        results[c] = list
    }

    // ───────── scanning ─────────
    fun open(c: Category?) {
        Chiptune.sfx(Sfx.POP)
        view = c
        if (c != null && results[c] == null && busy == null) scan(listOf(c))
    }

    fun scanAll() {
        if (!hasFiles || !hasUsage) { permTourScan = true; askPerms = true; return }
        scan(Category.entries.toList())
    }

    fun snoozePerms() {
        askPerms = false
        prefs.edit().putString("permsSnoozed", version).apply()
        if (permTourScan) { permTourScan = false; scan(Category.entries.toList()) }
    }

    /** Opens the settings page of each missing permission, one after the other, then (if asked) starts the scan. */
    fun startPermTour() {
        askPerms = false
        permTour = true
        permAsked.clear()
        nextPermission()
    }

    private fun nextPermission() {
        hasFiles = if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager() else true
        hasUsage = AppsInfo.hasUsageAccess(ctx)
        when {
            !hasFiles && "files" !in permAsked && Build.VERSION.SDK_INT >= 30 -> {
                permAsked += "files"
                showToast("Cerca SuriClean e accendi l'interruttore ♡")
                pendingIntent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${ctx.packageName}"))
            }
            !hasUsage && "usage" !in permAsked -> {
                permAsked += "usage"
                showToast("Tocca SuriClean e consenti l'accesso ♡")
                pendingIntent = Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)
            }
            else -> {
                permTour = false
                refresh()
                if (hasFiles && hasUsage) { Chiptune.sfx(Sfx.COIN); showToast("Yatta~! Ora vedo tutte le stanze 🔑✨") }
                else showToast("Okke~ guardo quello che posso: puoi darmi i permessi quando vuoi dalla tana")
                if (permTourScan) { permTourScan = false; scan(Category.entries.toList()) }
            }
        }
    }

    fun rescan(c: Category) { index = null; scan(listOf(c)) }

    fun cancelJob() { cancel.set(true); busy = busy?.copy(title = "Okke~ mi fermo! ✋"); Chiptune.sfx(Sfx.ERROR) }

    private fun needsIndex(c: Category) = c in setOf(Category.MAP, Category.DUPLICATES, Category.BIG, Category.APKS, Category.JUNK, Category.SYSTEM)

    fun scan(cats: List<Category>) {
        if (busy != null || cats.isEmpty()) return
        if (!hasFiles && cats.any { it != Category.APPS }) { showToast("Prima dammi l'accesso a tutti i file ♡"); return }
        cancel = AtomicBoolean(false)
        val flag = cancel
        busy = Busy(cats[0].act, cats[0].scanTitle, steps = cats.size)
        Chiptune.sfx(Sfx.WHOOSH)
        viewModelScope.launch {
            for ((i, c) in cats.withIndex()) {
                if (flag.get()) break
                Chiptune.setMood(if (c == Category.DUPLICATES) Mood.DETECTIVE else Mood.SCANNING)
                Chiptune.intensity = i.toDouble() / cats.size
                busy = busy?.copy(act = c.act, title = c.scanTitle, step = i, progress = if (cats.size > 1) i.toFloat() / cats.size else 0f)
                val rep = Reporter(flag) { text, p ->
                    viewModelScope.launch {
                        busy = busy?.let { b -> b.copy(detail = text, progress = p?.let { (b.step + it.coerceIn(0f, 1f)) / b.steps } ?: b.progress) }
                    }
                }
                val list = withContext(Dispatchers.IO) {
                    if (needsIndex(c) && (index == null || index!!.stale)) {
                        withContext(Dispatchers.Main) { busy = busy?.copy(act = Act.DIGGING, title = "Esploro tutta la memoria, tan-tan! 🏡", progress = null) }
                        index = StorageIndex.build(rep)
                        withContext(Dispatchers.Main) { busy = busy?.copy(act = c.act, title = c.scanTitle) }
                    }
                    val idx = index
                    when (c) {
                        Category.MAP -> idx?.let { Scanners.map(it) } ?: emptyList()
                        Category.CHATS -> Scanners.chats(rep)
                        Category.DUPLICATES -> idx?.let { Scanners.duplicates(it, rep) } ?: emptyList()
                        Category.BIG -> idx?.let { Scanners.big(it) } ?: emptyList()
                        Category.DOWNLOADS -> Scanners.downloads(rep)
                        Category.APKS -> idx?.let { Scanners.apks(it) } ?: emptyList()
                        Category.JUNK -> idx?.let { Scanners.junk(it) } ?: emptyList()
                        Category.SYSTEM -> idx?.let { SystemAreas.scan(ctx, it, rep) } ?: emptyList()
                        Category.APPS -> if (AppsInfo.hasUsageAccess(ctx)) {
                            val (apps, cache) = AppsInfo.scan(ctx, rep)
                            withContext(Dispatchers.Main) { appCache = cache }
                            apps
                        } else AppsInfo.scan(ctx, rep).first
                    }
                }
                if (flag.get()) break
                setResults(c, list)
                busy = busy?.copy(found = (busy?.found ?: 0) + list.size, foundBytes = (busy?.foundBytes ?: 0) + if (c.viewOnly) 0 else total(list))
                Chiptune.sfx(Sfx.COIN)
            }
            val cancelled = flag.get()
            busy = null
            Chiptune.intensity = 0.0
            Chiptune.setMood(if (cancelled) Mood.MENU else Mood.RESULTS)
            refresh()
            if (!cancelled && cats.size > 1) showToast("Missione compiuta!! Bottino: ${Fs.bytes(foundTotal)} ☆ Sugoi~!")
        }
    }

    // ───────── cleaning ─────────
    fun clean(c: Category) {
        if (busy != null) return
        var sel = selected(c)
        if (c == Category.APPS) { uninstall(sel); return }
        if (c == Category.DUPLICATES) {
            // always keep at least one copy of every file
            val safe = ArrayList<Item>()
            for (g in items(c).groupBy { it.group }.values) {
                val kept = g.filter { it.id !in selection && File(it.path).exists() }
                if (kept.isNotEmpty()) safe += g.filter { it.id in selection }
                else { val spare = g.firstOrNull { !it.recommended } ?: g[0]; safe += g.filter { it.id in selection && it.id != spare.id } }
            }
            if (safe.size < sel.size) showToast("Tranquillo~ ho tenuto almeno un gemellino di ogni file 💎")
            sel = safe
        }
        if (sel.isEmpty()) return
        cancel = AtomicBoolean(false)
        val flag = cancel
        busy = Busy(Act.SWEEPING, "Suri spazza via ${sel.size} ${if (sel.size == 1) "elemento" else "elementi"}…")
        Chiptune.setMood(Mood.CLEANING); Chiptune.sfx(Sfx.WHOOSH)
        viewModelScope.launch {
            val rep = Reporter(flag) { text, p -> viewModelScope.launch { busy = busy?.copy(detail = text, progress = p ?: busy?.progress); Chiptune.sfx(Sfx.COIN) } }
            val (removed, bytes, failed) = withContext(Dispatchers.IO) { Trash.move(ctx, sel, rep) }
            val ids = removed.toSet()
            for (k in results.keys.toList()) results[k] = results[k]!!.filter { it.id !in ids }
            selection = selection - ids
            index = null
            busy = null
            freed += bytes; prefs.edit().putLong("freed", freed).apply()
            refresh()
            celebrate(Celebration(
                if (bytes > 0) "Yatta~!! 🎉" else "Ehh… gomen! 🙈",
                if (bytes > 0) "Ho spedito ${Fs.bytes(bytes)} nel Cestino di Suri ☆" else "Non sono riuscita a spostare niente, scusa~",
                if (failed.isNotEmpty()) "${failed.size} elementi non si sono lasciati spostare: ${failed.take(3).joinToString()}" else
                    "Psst~ lo spazio torna libero davvero quando svuoti il Cestino di Suri ♡",
                offerEmptyTrash = bytes > 0))
        }
    }

    fun emptyTrash() {
        if (busy != null) return
        celebration = null
        busy = Busy(Act.SWEEPING, "Pulizia finale, pika-pika! 🗑️✨", progress = null)
        Chiptune.setMood(Mood.CLEANING); Chiptune.sfx(Sfx.WHOOSH)
        viewModelScope.launch {
            val freedNow = withContext(Dispatchers.IO) { Trash.empty() }
            busy = null
            refresh()
            celebrate(Celebration("Pika-pika! Cestino vuoto ✨", "Hai recuperato ${Fs.bytes(freedNow)} di spazio vero! Sugoi~ ♡"))
        }
    }

    fun clearAllCaches() {
        if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
            showToast("Per pulire le cache serve l'«Accesso a tutti i file» ♡"); return
        }
        cacheRequestAt = System.currentTimeMillis()
        pendingIntent = if (Build.VERSION.SDK_INT >= 25) Intent(android.os.storage.StorageManager.ACTION_CLEAR_APP_CACHE)
            else Intent(android.provider.Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
    }

    /** Called with the result of any system screen we opened. */
    fun onSystemResult(resultOk: Boolean) {
        if (permTour) { nextPermission(); return }
        if (cacheRequestAt > 0) {
            val quick = System.currentTimeMillis() - cacheRequestAt < 1500
            cacheRequestAt = 0
            if (resultOk) {
                Chiptune.sfx(Sfx.COIN); showToast("Pika-pika! Cache di tutte le app svuotate ✨")
            } else if (quick) {
                // many phones (Samsung, Xiaomi…) disable this screen: fall back to the system storage settings
                showToast("Questo telefono non permette la pulizia in un colpo: apro l'archiviazione di Android ♡")
                pendingIntent = Intent(android.provider.Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
                return
            }
            viewModelScope.launch { delay(800); refresh(); if (results[Category.APPS] != null) rescan(Category.APPS) }
            return
        }
        if (uninstallQueue.isNotEmpty()) nextUninstall() else {
            refresh()
            if (results[Category.APPS] != null && busy == null) scan(listOf(Category.APPS))
        }
    }

    fun openAppSettings(pkg: String) {
        Chiptune.sfx(Sfx.POP)
        pendingIntent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
    }

    private fun uninstall(apps: List<Item>) {
        uninstallQueue.clear()
        apps.mapNotNullTo(uninstallQueue) { it.packageName }
        nextUninstall()
    }

    fun nextUninstall() {
        val pkg = uninstallQueue.removeFirstOrNull()
        if (pkg == null) { refresh(); return }
        @Suppress("DEPRECATION")
        pendingIntent = Intent(Intent.ACTION_UNINSTALL_PACKAGE, Uri.parse("package:$pkg")).putExtra(Intent.EXTRA_RETURN_RESULT, true)
    }

    private fun celebrate(c: Celebration) {
        celebration = c
        Chiptune.setMood(Mood.VICTORY)
        viewModelScope.launch { delay(3800); if (Chiptune.currentMood() == Mood.VICTORY) Chiptune.setMood(Mood.RESULTS) }
    }

    fun dismissCelebration() { celebration = null; Chiptune.sfx(Sfx.POP) }

    // ───────── updates ─────────
    private fun newer(a: String, b: String): Boolean {
        val x = a.trimStart('v', 'V').split(".").map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
        val y = b.trimStart('v', 'V').split(".").map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(x.size, y.size)) { val l = x.getOrElse(i) { 0 }; val r = y.getOrElse(i) { 0 }; if (l != r) return l > r }
        return false
    }

    fun checkUpdate(manual: Boolean) {
        viewModelScope.launch {
            val found = withContext(Dispatchers.IO) {
                try {
                    val c = URL("https://api.github.com/repos/Marketto/suriclean/releases/latest").openConnection() as HttpURLConnection
                    c.setRequestProperty("Accept", "application/vnd.github+json")
                    c.connectTimeout = 15000; c.readTimeout = 15000
                    val j = JSONObject(c.inputStream.bufferedReader().readText())
                    val v = j.getString("tag_name").trimStart('v')
                    val assets = j.getJSONArray("assets")
                    var url: String? = null
                    for (i in 0 until assets.length()) {
                        val a = assets.getJSONObject(i)
                        if (a.getString("name") == "SuriClean-Android.apk") url = a.getString("browser_download_url")
                    }
                    if (url != null && newer(v, version)) AppUpdate(v, url) else null
                } catch (e: Exception) { null }
            }
            update = found
            when {
                found != null && (autoUpdate || manual) && busy == null && results.isEmpty() -> installUpdate()
                found != null -> showToast("Kyaa~! È uscita SuriClean ${found.version} ✨ Tocca «Aggiorna» in alto")
                manual -> showToast("Sei già all'ultima versione ($version) ✨")
            }
        }
    }

    fun installUpdate() {
        val u = update ?: return
        if (busy != null) return
        if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
            pendingIntent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}"))
            showToast("Permetti a SuriClean di installare aggiornamenti, poi tocca di nuovo «Aggiorna» ♡")
            return
        }
        busy = Busy(Act.DIGGING, "Scarico SuriClean ${u.version}… ✨", "Poi Android ti chiede di confermare", progress = null)
        viewModelScope.launch {
            val file = withContext(Dispatchers.IO) {
                try {
                    val dir = File(ctx.cacheDir, "updates").apply { mkdirs() }
                    val f = File(dir, "SuriClean.apk")
                    val c = URL(u.url).openConnection() as HttpURLConnection
                    c.instanceFollowRedirects = true
                    c.inputStream.use { inp -> f.outputStream().use { inp.copyTo(it) } }
                    f
                } catch (e: Exception) { null }
            }
            busy = null
            if (file == null) { showToast("Aggiornamento non riuscito, riprova più tardi~"); return@launch }
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
            pendingIntent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
}
