import Foundation
import AppKit
import WebKit

/// Schiaccia's engine (motore.js) for PDFs and photos, in a hidden WKWebView (docs/SCHIACCIA.md).
///
/// Everything goes through one custom scheme, so the page, its scripts and the file share one origin:
///   suri-app://app/host.html          the tiny host page below
///   suri-app://app/schiaccia/<path>   motore.js, engine.js, config.js, vendor/… from the app bundle
///   suri-app://app/file/<token>       the local file being squeezed (only the one registered for the job)
/// The light file comes back through the "suri" message handler in base64 chunks, appended to a temp file
/// next to the original. Nothing leaves the Mac.
@MainActor
final class SchiacciaWeb: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    struct Outcome {
        var status: String          // "done" | "same" | "err"
        var note: String = ""
        var out: URL? = nil
        var name: String? = nil
    }

    private var web: WKWebView?
    private var readyCont: CheckedContinuation<Bool, Never>?
    private var isReady = false
    private var files: [String: URL] = [:]
    private var jobCont: CheckedContinuation<Outcome, Never>?
    private var jobOut: URL?
    private var jobHandle: FileHandle?
    private var jobPct: ((Double) -> Void)?

    private static let host = """
    <!doctype html><html><head><meta charset="utf-8">
    <script src="schiaccia/config.js"></script>
    <script src="schiaccia/motore.js"></script>
    </head><body><script>
    var ctl = null;
    function post(m) { window.webkit.messageHandlers.suri.postMessage(m); }
    function b64(u8) { var s = ""; for (var i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); }
    async function run(token, name, level) {
      ctl = (typeof AbortController !== "undefined") ? new AbortController() : null;
      try {
        var r = await fetch("file/" + token);
        var b = await r.blob();
        var f = new File([b], name, { type: b.type || "" });
        var last = -1;
        var res = await Motore.squeeze(f, { level: level, signal: ctl ? ctl.signal : undefined,
          onPct: function (p) { p = Math.round(p); if (p !== last) { last = p; post({ t: "pct", p: p }); } } });
        if (res.status === "done") {
          var u8 = new Uint8Array(await res.blob.arrayBuffer()), CH = 786432;
          for (var i = 0; i < u8.length; i += CH) post({ t: "chunk", d: b64(u8.subarray(i, i + CH)) });
          post({ t: "end", s: "done", n: res.name || name });
        } else {
          post({ t: "end", s: res.status, n: res.note || "" });
        }
        try { if (res.release) res.release(); } catch (e) {}
      } catch (e) {
        post({ t: "end", s: "err", n: "unreadable" });
      }
    }
    post({ t: "ready", ok: !!window.Motore });
    </script></body></html>
    """

    /// Loads the engine. False if Schiaccia isn't in the app or the page didn't come up.
    func start() async -> Bool {
        guard Squeeze.bundleDir != nil else { return false }
        if isReady { return true }
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(self, forURLScheme: "suri-app")
        cfg.userContentController.add(self, name: "suri")
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: cfg)
        w.alphaValue = 0.01
        // attached to a window so WebKit keeps running it at full speed
        NSApp.windows.first(where: { $0.isVisible })?.contentView?.addSubview(w)
        web = w
        w.load(URLRequest(url: URL(string: "suri-app://app/host.html")!))
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            readyCont = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if let c = self?.readyCont { self?.readyCont = nil; c.resume(returning: false) }
            }
        }
        isReady = ok
        return ok
    }

    /// One PDF or JPG with Schiaccia's rules; the light file (if any) is a temp file next to the original.
    func squeeze(_ url: URL, level: SqueezeLevel, onPct: @escaping (Double) -> Void) async -> Outcome {
        guard isReady, let web = web else { return Outcome(status: "err", note: "unreadable") }
        let token = UUID().uuidString
        files[token] = url
        defer { files[token] = nil }
        let out = SqueezeFiles.tempURL(for: url)
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
              let h = try? FileHandle(forWritingTo: out) else { return Outcome(status: "err", note: "unreadable") }
        jobOut = out
        jobHandle = h
        jobPct = onPct
        let js = "run(\(jsString(token)), \(jsString(url.lastPathComponent)), \(jsString(level.rawValue)))"
        let r = await withCheckedContinuation { (c: CheckedContinuation<Outcome, Never>) in
            jobCont = c
            web.evaluateJavaScript(js, completionHandler: nil)
        }
        try? h.close()
        jobHandle = nil
        jobPct = nil
        jobOut = nil
        if r.status != "done" { try? FileManager.default.removeItem(at: out) }
        return r
    }

    func cancel() {
        web?.evaluateJavaScript("if (ctl) ctl.abort();", completionHandler: nil)
    }

    func stop() {
        if let c = jobCont { jobCont = nil; c.resume(returning: Outcome(status: "err", note: "aborted")) }
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "suri")
        web?.stopLoading()
        web?.removeFromSuperview()
        web = nil
        isReady = false
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let arr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    // MARK: messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let kind = m["t"] as? String else { return }
        switch kind {
        case "ready":
            let ok = (m["ok"] as? Bool) ?? ((m["ok"] as? NSNumber)?.boolValue ?? false)
            if let c = readyCont { readyCont = nil; c.resume(returning: ok) }
        case "pct":
            if let p = (m["p"] as? NSNumber)?.doubleValue { jobPct?(p / 100) }
        case "chunk":
            if let s = m["d"] as? String, let d = Data(base64Encoded: s) { jobHandle?.write(d) }
        case "end":
            let status = (m["s"] as? String) ?? "err"
            let n = (m["n"] as? String) ?? ""
            let r = status == "done" ? Outcome(status: "done", out: jobOut, name: n) : Outcome(status: status, note: n)
            if let c = jobCont { jobCont = nil; c.resume(returning: r) }
        default:
            break
        }
    }

    // MARK: the custom scheme

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let u = urlSchemeTask.request.url else { return }
        let path = u.path
        var data: Data?
        var mime = "application/octet-stream"
        if path == "/host.html" {
            data = Self.host.data(using: .utf8)
            mime = "text/html"
        } else if path.hasPrefix("/schiaccia/"), let dir = Squeeze.bundleDir {
            let rel = String(path.dropFirst("/schiaccia/".count))
            let f = dir.appendingPathComponent(rel).standardizedFileURL
            if !rel.contains(".."), f.path.hasPrefix(dir.standardizedFileURL.path) {
                data = try? Data(contentsOf: f, options: .mappedIfSafe)
                switch f.pathExtension.lowercased() {
                case "js", "mjs": mime = "text/javascript"
                case "svg": mime = "image/svg+xml"
                case "txt": mime = "text/plain"
                default: break
                }
            }
        } else if path.hasPrefix("/file/") {
            let token = String(path.dropFirst("/file/".count))
            if let f = files[token] {
                data = try? Data(contentsOf: f, options: .mappedIfSafe)
                switch f.pathExtension.lowercased() {
                case "pdf": mime = "application/pdf"
                case "jpg", "jpeg": mime = "image/jpeg"
                default: break
                }
            }
        }
        guard let body = data else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let resp = HTTPURLResponse(url: u, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": "\(body.count)"])!
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
