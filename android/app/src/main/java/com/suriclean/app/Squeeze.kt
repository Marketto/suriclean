package com.suriclean.app

import android.annotation.SuppressLint
import android.app.Activity
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.webkit.WebViewAssetLoader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Which files Schiaccia can squeeze (same extensions as Motore.kindOf). */
object SqueezeKinds {
    fun of(name: String): String? {
        val n = name.lowercase()
        return when {
            n.endsWith(".pdf") -> "pdf"
            n.endsWith(".jpg") || n.endsWith(".jpeg") -> "jpg"
            n.endsWith(".mp4") || n.endsWith(".mov") || n.endsWith(".m4v") || n.endsWith(".webm") || n.endsWith(".mkv") -> "video"
            else -> null
        }
    }

    fun mime(name: String): String {
        val n = name.lowercase()
        return when {
            n.endsWith(".pdf") -> "application/pdf"
            n.endsWith(".jpg") || n.endsWith(".jpeg") -> "image/jpeg"
            n.endsWith(".mov") -> "video/quicktime"
            n.endsWith(".webm") -> "video/webm"
            n.endsWith(".mkv") -> "video/x-matroska"
            n.endsWith(".m4v") -> "video/x-m4v"
            else -> "video/mp4"
        }
    }

    /** Short label shown on the file Suri carries to the press. */
    fun label(kind: String) = when (kind) { "pdf" -> "PDF"; "jpg" -> "JPG"; else -> "MP4" }

    /** PDF and photos from 1 MB, videos from 20 MB, outside Android/data, Suri's trash and thumbnails. */
    fun scan(idx: StorageIndex): List<Item> {
        val trash = Trash.dir.absolutePath
        return idx.files.mapNotNull { (f, len) ->
            val p = f.absolutePath
            if (p.contains("/Android/data/") || p.contains("/Android/obb/") || p.startsWith(trash) ||
                p.contains("/.thumbnails/") || f.name.startsWith(".suri-")) return@mapNotNull null
            val kind = of(f.name) ?: return@mapNotNull null
            if (len < (if (kind == "video") 20L * 1_048_576 else 1_048_576L)) return@mapNotNull null
            Item(Fs.nextId(), p, f.name, Fs.pretty(f.parentFile ?: f), len, f.lastModified(), Risk.REVIEW, true,
                listOf(L.t("and.sq.badge.$kind")))
        }
    }
}

/**
 * Runs Schiaccia's engine (assets/schiaccia/motore.js, see docs/SCHIACCIA.md) in a hidden WebView.
 * Files go in through WebViewAssetLoader (/suri-file/<token> streams the real file, nothing is copied);
 * results come back through [Bridge.chunk] in base64 pieces, written straight to a temp file next to
 * the original. One file at a time. The WebView lives as long as the Activity.
 */
class SqueezeEngine(private val activity: Activity) {
    data class Result(val status: String, val note: String, val name: String, val out: File?)

    private var web: WebView? = null
    private var readyState = CompletableDeferred<JSONObject>()
    private val files = ConcurrentHashMap<String, File>()
    private val jobs = ConcurrentHashMap<String, Job>()
    private val seq = AtomicInteger()

    private class Job(val out: File, val onPct: (Int) -> Unit) {
        @Volatile var stream: FileOutputStream? = FileOutputStream(out)
        val done = CompletableDeferred<JSONObject>()
    }

    /** Assets with the right MIME types (module scripts need text/javascript, WebView's guess doesn't know .mjs). */
    private inner class AssetsHandler : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse? = try {
            WebResourceResponse(mimeOf(path), null, activity.assets.open(path))
        } catch (e: IOException) {
            WebResourceResponse("text/plain", null, 404, "Not Found", emptyMap(), null)
        }
    }

    /** The file being squeezed, streamed from disk. */
    private inner class FileHandler : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse? {
            val f = files[path.substringBefore('/')] ?: return WebResourceResponse("text/plain", null, 404, "Not Found", emptyMap(), null)
            return try {
                WebResourceResponse(SqueezeKinds.mime(f.name), null, 200, "OK",
                    mapOf("Content-Length" to f.length().toString(), "Cache-Control" to "no-store"), FileInputStream(f))
            } catch (e: IOException) {
                WebResourceResponse("text/plain", null, 404, "Not Found", emptyMap(), null)
            }
        }
    }

    private fun mimeOf(p: String): String {
        val n = p.lowercase()
        return when {
            n.endsWith(".js") || n.endsWith(".mjs") -> "text/javascript"
            n.endsWith(".html") -> "text/html"
            n.endsWith(".json") -> "application/json"
            n.endsWith(".svg") -> "image/svg+xml"
            n.endsWith(".wasm") -> "application/wasm"
            n.endsWith(".css") -> "text/css"
            else -> "application/octet-stream"
        }
    }

    /** Called by host.html, on WebView's background (binder) thread. */
    private inner class Bridge {
        @JavascriptInterface
        fun ready(json: String) {
            readyState.complete(try { JSONObject(json) } catch (e: Exception) { JSONObject() })
        }

        @JavascriptInterface
        fun progress(id: String, pct: Int) {
            jobs[id]?.onPct?.invoke(pct)
        }

        @JavascriptInterface
        fun chunk(id: String, b64: String): Boolean {
            val j = jobs[id] ?: return false
            val s = j.stream ?: return false
            return try { s.write(Base64.decode(b64, Base64.DEFAULT)); true } catch (e: Exception) { false }
        }

        @JavascriptInterface
        fun finish(id: String, json: String) {
            val j = jobs[id] ?: return
            try { j.stream?.close() } catch (e: Exception) { }
            j.stream = null
            j.done.complete(try { JSONObject(json) } catch (e: Exception) { JSONObject().put("status", "err").put("note", "unreadable") })
        }
    }

    /** Creates the hidden WebView (main thread). Safe to call many times. */
    @SuppressLint("SetJavaScriptEnabled")
    fun warmUp() {
        if (web != null) return
        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", AssetsHandler())
            .addPathHandler("/suri-file/", FileHandler())
            .build()
        val w = WebView(activity)
        w.settings.javaScriptEnabled = true
        w.settings.domStorageEnabled = true
        w.settings.allowFileAccess = false
        w.settings.allowContentAccess = false
        w.settings.mediaPlaybackRequiresUserGesture = false
        w.addJavascriptInterface(Bridge(), "SuriBridge")
        w.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                // only the app's own pages and the file being squeezed: no other network
                return loader.shouldInterceptRequest(request.url)
                    ?: WebResourceResponse("text/plain", null, 403, "Forbidden", emptyMap(), null)
            }
        }
        // attached (1 px, invisible) so the page keeps running timers and workers
        w.alpha = 0f
        w.isFocusable = false
        w.isClickable = false
        w.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        (activity.window.decorView as? ViewGroup)?.addView(w, FrameLayout.LayoutParams(1, 1))
        web = w
        w.loadUrl("https://appassets.androidplatform.net/assets/suri/host.html")
    }

    /** null if the engine never answered (e.g. built without ./schiaccia). */
    suspend fun info(): JSONObject? {
        withContext(Dispatchers.Main) { warmUp() }
        return withTimeoutOrNull(20_000) { readyState.await() }
    }

    suspend fun canVideo(): Boolean = info()?.optBoolean("canVideo") == true

    /** Squeezes one file with Schiaccia's rules; on "done" the light copy is in [Result.out] (a temp file next to the original). */
    suspend fun squeeze(file: File, level: String, onPct: (Int) -> Unit): Result {
        val inf = info()
        if (inf == null || !inf.optBoolean("ok")) return Result("err", "noEngine", file.name, null)
        val id = "j" + seq.incrementAndGet()
        val token = UUID.randomUUID().toString()
        val tmp = File(file.parentFile, ".suri-$id-${file.name}.part")
        val job = try { Job(tmp, onPct) } catch (e: IOException) { return Result("err", "readOnly", file.name, null) }
        files[token] = file
        jobs[id] = job
        try {
            val src = "https://appassets.androidplatform.net/suri-file/$token"
            val js = "suriSqueeze(${JSONObject.quote(id)},${JSONObject.quote(src)},${JSONObject.quote(file.name)}," +
                "${JSONObject.quote(SqueezeKinds.mime(file.name))},${JSONObject.quote(level)})"
            withContext(Dispatchers.Main) { web?.evaluateJavascript(js, null) }
            val o = job.done.await()
            val status = o.optString("status", "err")
            val name = o.optString("name", file.name).ifBlank { file.name }
            if (status == "done" && tmp.length() > 0 && tmp.length() == o.optLong("size", -1)) return Result("done", "", name, tmp)
            tmp.delete()
            return Result(if (status == "done") "err" else status, o.optString("note"), name, null)
        } catch (e: CancellationException) {
            withContext(kotlinx.coroutines.NonCancellable + Dispatchers.Main) { web?.evaluateJavascript("suriCancel(${JSONObject.quote(id)})", null) }
            try { job.stream?.close() } catch (x: Exception) { }
            tmp.delete()
            throw e
        } finally {
            files.remove(token)
            jobs.remove(id)
        }
    }

    /** Main thread, from Activity.onDestroy. */
    fun destroy() {
        web?.let { (it.parent as? ViewGroup)?.removeView(it); it.destroy() }
        web = null
        readyState = CompletableDeferred()
        jobs.values.forEach { j -> try { j.stream?.close() } catch (e: Exception) { }; j.done.complete(JSONObject().put("status", "err").put("note", "aborted")) }
    }
}
