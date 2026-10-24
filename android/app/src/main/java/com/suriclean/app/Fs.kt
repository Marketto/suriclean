package com.suriclean.app

import android.os.Environment
import android.os.StatFs
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

object Fs {
    val root: File get() = Environment.getExternalStorageDirectory()
    val downloads: File get() = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
    private val ids = AtomicLong(1)
    fun nextId(): Long = ids.getAndIncrement()

    fun pretty(f: File): String {
        val r = root.absolutePath
        return if (f.absolutePath.startsWith(r)) "📱" + f.absolutePath.removePrefix(r).ifEmpty { "/" } else f.absolutePath
    }

    fun bytes(b: Long): String {
        var v = b.coerceAtLeast(0).toDouble()
        val u = listOf("byte", "KB", "MB", "GB", "TB")
        var i = 0
        while (v >= 1000 && i < 4) { v /= 1000; i++ }
        return if (i == 0) "${b.coerceAtLeast(0)} byte" else String.format(java.util.Locale.ITALY, "%.1f %s", v, u[i])
    }

    fun relative(millis: Long?): String {
        if (millis == null || millis <= 0) return "mai"
        val s = (System.currentTimeMillis() - millis) / 1000
        val d = s / 86_400
        return when {
            s < 3600 -> "poco fa"
            d < 1 -> "oggi"
            d < 2 -> "ieri"
            d < 30 -> "$d giorni fa"
            d < 365 -> (d / 30).let { if (it == 1L) "1 mese fa" else "$it mesi fa" }
            else -> (d / 365).let { if (it == 1L) "1 anno fa" else "$it anni fa" }
        }
    }

    fun daysSince(millis: Long?): Long = if (millis == null || millis <= 0) 99_999 else (System.currentTimeMillis() - millis) / 86_400_000

    /** Size of a file or folder (no symlinks followed). */
    fun sizeOf(f: File, cancel: AtomicBoolean? = null): Long {
        if (!f.exists()) return 0
        if (f.isFile) return f.length()
        var total = 0L
        val stack = ArrayDeque<File>()
        stack.add(f)
        var n = 0
        while (stack.isNotEmpty()) {
            if (++n % 500 == 0 && cancel?.get() == true) break
            val d = stack.removeLast()
            val kids = d.listFiles() ?: continue
            for (k in kids) {
                if (isSymlink(k)) continue
                if (k.isDirectory) stack.add(k) else total += k.length()
            }
        }
        return total
    }

    fun newest(f: File): Long {
        var best = f.lastModified()
        f.listFiles()?.forEach { if (it.lastModified() > best) best = it.lastModified() }
        return best
    }

    fun isSymlink(f: File): Boolean = try {
        java.nio.file.Files.isSymbolicLink(f.toPath())
    } catch (e: Exception) { false }

    fun storage(): Pair<Long, Long> {
        val s = StatFs(root.absolutePath)
        return s.totalBytes to s.availableBytes
    }

    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    fun partialHash(f: File): String? = try {
        RandomAccessFile(f, "r").use { r ->
            val md = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(65_536)
            val n = r.read(buf)
            if (n > 0) md.update(buf, 0, n)
            val len = r.length()
            if (len > 131_072) {
                r.seek(len - 65_536)
                val m = r.read(buf)
                if (m > 0) md.update(buf, 0, m)
            }
            hex(md.digest())
        }
    } catch (e: Exception) { null }

    fun fullHash(f: File, cancel: AtomicBoolean): String? = try {
        FileInputStream(f).use { inp ->
            val md = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(1 shl 20)
            while (true) {
                if (cancel.get()) return null
                val n = inp.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
            hex(md.digest())
        }
    } catch (e: Exception) { null }
}
