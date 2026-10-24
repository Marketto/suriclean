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

    /** `pm clear <pkg>` with shell rights. Returns true when Android says "Success". */
    fun clearData(pkg: String): Boolean = try {
        val m = Shizuku::class.java.getDeclaredMethod("newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java)
        m.isAccessible = true
        val p = m.invoke(null, arrayOf("pm", "clear", pkg), null, null) as Process
        val out = p.inputStream.bufferedReader().readText()
        p.waitFor() == 0 && out.contains("Success")
    } catch (e: Throwable) { false }
}
