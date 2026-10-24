package com.suriclean.app

import android.content.Context
import android.content.pm.PackageManager
import rikka.shizuku.Shizuku

/**
 * Android lets only the system clear another app's data. Shizuku (a free app many power users have)
 * runs commands with the same rights as `adb shell`, so with it SuriClean can run `pm clear` for
 * every selected app in one go. Without it we fall back to opening each app's settings page.
 */
object ShizukuBridge {
    const val PACKAGE = "moe.shizuku.privileged.api"
    private const val REQUEST = 4242
    private var onResult: ((Boolean) -> Unit)? = null
    private val listener = Shizuku.OnRequestPermissionResultListener { code, result ->
        if (code == REQUEST) {
            val cb = onResult; onResult = null
            cb?.invoke(result == PackageManager.PERMISSION_GRANTED)
        }
    }

    init {
        try { Shizuku.addRequestPermissionResultListener(listener) } catch (e: Throwable) { }
    }

    fun installed(ctx: Context): Boolean = try {
        ctx.packageManager.getPackageInfo(PACKAGE, 0); true
    } catch (e: Exception) { false }

    /** Shizuku is installed and its service is running. */
    fun running(): Boolean = try { Shizuku.pingBinder() && !Shizuku.isPreV11() } catch (e: Throwable) { false }

    fun granted(): Boolean = try { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED } catch (e: Throwable) { false }

    fun request(cb: (Boolean) -> Unit) {
        if (granted()) { cb(true); return }
        try {
            if (Shizuku.shouldShowRequestPermissionRationale()) { cb(false); return }   // user chose "deny forever"
            onResult = cb
            Shizuku.requestPermission(REQUEST)
        } catch (e: Throwable) { onResult = null; cb(false) }
    }

    /** Running and allowed: ready to work without asking anything. */
    fun ready(): Boolean = running() && granted()

    /** Runs a command with shell (adb) rights, entirely on the phone. Null if Shizuku is not usable. */
    fun exec(vararg cmd: String): Pair<Int, String>? = try {
        val m = Shizuku::class.java.getDeclaredMethod("newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java)
        m.isAccessible = true
        val p = m.invoke(null, arrayOf(*cmd), null, null) as Process
        val out = p.inputStream.bufferedReader().readText()
        p.errorStream.bufferedReader().readText()
        p.waitFor() to out
    } catch (e: Throwable) { null }

    fun sh(script: String) = exec("sh", "-c", script)

    fun q(s: String) = "'" + s.replace("'", "'\\''") + "'"

    /** `pm clear <pkg>`: the app goes back to freshly installed. */
    fun clearData(pkg: String): Boolean = exec("pm", "clear", pkg)?.let { it.first == 0 && it.second.contains("Success") } ?: false

    /** Asks Android to free all app caches (same as the system "clear cache" for every app). */
    fun trimCaches(): Boolean = exec("pm", "trim-caches", "999G")?.first == 0

    /** `du -sk` lines ("<kb>\t<path>") of the given shell glob(s). */
    fun du(globs: String): List<Pair<String, Long>> {
        val out = sh("for d in $globs; do [ -d \"\$d\" ] && du -sk \"\$d\" 2>/dev/null; done")?.second ?: return emptyList()
        return out.lines().mapNotNull { l ->
            val t = l.split('\t', limit = 2)
            val kb = t.getOrNull(0)?.trim()?.toLongOrNull() ?: return@mapNotNull null
            (t.getOrNull(1) ?: return@mapNotNull null) to kb * 1024
        }
    }

    fun remove(path: String): Boolean {
        sh("rm -rf -- ${q(path)}")
        return sh("[ -e ${q(path)} ] && echo yes")?.second?.contains("yes") == false
    }
}
