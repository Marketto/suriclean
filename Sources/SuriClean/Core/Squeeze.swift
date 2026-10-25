import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// «Da schiacciare» (docs/SCHIACCIA.md): PDF, photos and videos that Schiaccia's engine can make lighter.
enum SqueezeKind: String, CaseIterable, Identifiable {
    case pdf, jpg, video
    var id: String { rawValue }

    /// AVFoundation can't read WebM/MKV, so on the Mac only MP4/MOV/M4V videos are proposed.
    static func of(_ url: URL) -> SqueezeKind? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "jpg", "jpeg": return .jpg
        case "mp4", "mov", "m4v": return .video
        default: return nil
        }
    }

    var minSize: Int64 { self == .video ? 20 * 1_048_576 : 1_048_576 }
    var label: String { t("mac.sq.kind.\(rawValue)") }
    var badge: String { t("mac.sq.badge.\(rawValue)") }
    /// Text on the little file card of the animation.
    var tag: String {
        switch self {
        case .pdf: return "PDF"
        case .jpg: return "JPG"
        case .video: return "MP4"
        }
    }
}

/// Schiaccia's three strengths: Carezza, Stretta, Martellata (CONFIG.levels).
enum SqueezeLevel: String, CaseIterable, Identifiable {
    case soft, mid, hard
    var id: String { rawValue }
    var label: String { t("mac.sq.level.\(rawValue)") }
    var note: String { t("mac.sq.level.\(rawValue).note") }
}

enum Squeeze {
    static func candidates(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index else { return [] }
        var out: [CleanItem] = []
        for f in index.files {
            guard let k = SqueezeKind.of(f.url), f.size >= k.minSize, isLocal(f.url) else { continue }
            out.append(CleanItem(url: f.url, name: f.url.lastPathComponent,
                                 detail: t("mac.detail.modified", FS.pretty(f.url.deletingLastPathComponent()), Fmt.relative(f.modified)),
                                 size: f.size, date: f.modified, risk: .review, recommended: false, badges: [k.badge]))
        }
        return out.sorted { $0.size > $1.size }
    }

    /// iCloud files whose content isn't on this Mac are skipped: reading them would download them.
    static func isLocal(_ u: URL) -> Bool {
        #if os(macOS)
        guard let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              v.isUbiquitousItem == true else { return true }
        return v.ubiquitousItemDownloadingStatus == .current
        #else
        return true
        #endif
    }

    /// Schiaccia's files inside the app (build.sh copies ./schiaccia, made by scripts/fetch-schiaccia.sh).
    static var bundleDir: URL? {
        guard let d = Bundle.main.resourceURL?.appendingPathComponent("schiaccia"),
              FileManager.default.fileExists(atPath: d.appendingPathComponent("motore.js").path) else { return nil }
        return d
    }

    static var version: String {
        guard let d = bundleDir, let s = try? String(contentsOf: d.appendingPathComponent("VERSION"), encoding: .utf8) else { return "?" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: video numbers, read from Schiaccia's config.js (same first guess as Schiaccia's vGuess)

    struct VideoTuning {
        var hiFrom = 0.965
        var bppHi = 0.06, bppLo = 0.04
        var ratioHi: [String: Double] = ["modern": 0.7, "avc": 0.45, "old": 0.3]
        var ratioLo: [String: Double] = ["modern": 0.5, "avc": 0.32, "old": 0.22]
        var avcMul = 1.5
        var fileKeep = 0.9
        var planMargin = 1.05
        var fmin = 0.035, fmax = 0.85
        var lightAvc = 0.035, lightOther = 0.05
        var aacBitrate = 160_000.0
        var audioGain = 0.05
        var ssim: [String: Double] = ["soft": 0.97, "mid": 0.95, "hard": 0.95]
        var box: [String: (Double, Double)] = ["hard": (1920, 1080)]
    }

    static let tuning: VideoTuning = {
        var tu = VideoTuning()
        #if canImport(JavaScriptCore)
        guard let dir = bundleDir,
              let src = try? String(contentsOf: dir.appendingPathComponent("config.js"), encoding: .utf8),
              let ctx = JSContext() else { return tu }
        ctx.evaluateScript("var window = this; var self = this;")
        ctx.evaluateScript(src)
        guard let json = ctx.evaluateScript("JSON.stringify({v: CONFIG.video, l: CONFIG.levels})")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return tu }
        func d(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
        if let v = obj["v"] as? [String: Any] {
            if let x = d(v["fileKeep"]) { tu.fileKeep = x }
            if let x = d(v["planMargin"]) { tu.planMargin = x }
            if let x = d(v["aacBitrate"]) { tu.aacBitrate = x }
            if let x = d(v["audioGain"]) { tu.audioGain = x }
            if let s = v["search"] as? [String: Any] {
                if let x = d(s["fmin"]) { tu.fmin = x }
                if let x = d(s["fmax"]) { tu.fmax = x }
            }
            if let lb = v["lightBpp"] as? [String: Any] {
                if let x = d(lb["avc"]) { tu.lightAvc = x }
                if let x = d(lb["other"]) { tu.lightOther = x }
            }
            if let g = v["guess"] as? [String: Any] {
                if let x = d(g["hiFrom"]) { tu.hiFrom = x }
                if let x = d(g["avcMul"]) { tu.avcMul = x }
                if let b = g["bpp"] as? [String: Any] {
                    if let x = d(b["hi"]) { tu.bppHi = x }
                    if let x = d(b["lo"]) { tu.bppLo = x }
                }
                if let r = g["ratio"] as? [String: Any] {
                    if let hi = r["hi"] as? [String: Any] { for (k, x) in hi { if let n = d(x) { tu.ratioHi[k] = n } } }
                    if let lo = r["lo"] as? [String: Any] { for (k, x) in lo { if let n = d(x) { tu.ratioLo[k] = n } } }
                }
            }
        }
        if let levels = obj["l"] as? [String: Any] {
            for (k, lv) in levels {
                guard let video = (lv as? [String: Any])?["video"] as? [String: Any] else { continue }
                if let s = d(video["ssim"]) { tu.ssim[k] = s }
                if let b = video["box"] as? [Any], b.count == 2, let w = d(b[0]), let h = d(b[1]) { tu.box[k] = (w, h) } else { tu.box[k] = nil }
            }
        }
        #endif
        return tu
    }()

    /// Codec family of the source, as Schiaccia names it.
    static func family(fourCC: String) -> String {
        switch fourCC {
        case "hvc1", "hev1", "av01", "vp09", "dvh1", "dvhe": return "modern"
        case "avc1", "avc3": return "avc"
        default: return "old"
        }
    }

    /// Output size for a level (Schiaccia's vTarget: the level's box, orientation-agnostic, even numbers).
    static func targetSize(level: SqueezeLevel, w: Double, h: Double) -> (Int, Int)? {
        guard let box = tuning.box[level.rawValue], w > 0, h > 0 else { return nil }
        let k = min(1, box.0 / max(w, h), box.1 / min(w, h))
        if k >= 1 { return nil }
        return (max(2, Int((w * k / 2).rounded()) * 2), max(2, Int((h * k / 2).rounded()) * 2))
    }

    /// Target video bitrate (bit/s): Schiaccia's first guess, with its plan margin.
    /// nil when the source is already light (lightBpp) and re-encoding would not pay off.
    static func videoBitrate(level: SqueezeLevel, family: String, srcBitrate: Double,
                             srcW: Double, srcH: Double, outW: Double, outH: Double, fps: Double, outHEVC: Bool) -> Double? {
        let tu = tuning
        let f = fps > 0 ? fps : 30
        let srcBpp = srcBitrate / max(1, srcW * srcH * f)
        if srcBitrate > 0 && srcBpp < (family == "avc" ? tu.lightAvc : tu.lightOther) { return nil }
        let hi = (tu.ssim[level.rawValue] ?? 0.97) >= tu.hiFrom
        let bpp = hi ? tu.bppHi : tu.bppLo
        let ratio = (hi ? tu.ratioHi : tu.ratioLo)[family] ?? 0.3
        let mul = outHEVC ? 1 : tu.avcMul
        let px = outW * outH
        let shrink = (outW * outH < srcW * srcH) ? pow(px / (srcW * srcH), 0.75) : 1
        var b = px * f * bpp * mul
        if srcBitrate > 0 {
            b = min(b, srcBitrate * ratio * mul * shrink)
            b = min(srcBitrate * tu.fmax, max(srcBitrate * tu.fmin, b))
        }
        return max(150_000, b * tu.planMargin)
    }
}

/// Puts the light file in place of the original: original → the user's Trash, light file → the original's place.
enum SqueezeFiles {
    /// A hidden temporary file next to the original (same volume, so the final move is instant).
    static func tempURL(for original: URL, ext: String? = nil) -> URL {
        let dir = original.deletingLastPathComponent()
        let e = ext ?? original.pathExtension
        return dir.appendingPathComponent(".\(original.deletingPathExtension().lastPathComponent).suri-\(UUID().uuidString.prefix(8)).\(e)")
    }

    /// Returns the final URL, or nil if the original could not be moved to the Trash (then nothing changes).
    static func replace(original: URL, with temp: URL, finalName: String? = nil) -> URL? {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: original.path)
        let dest = finalName.map { original.deletingLastPathComponent().appendingPathComponent($0) } ?? original
        var trashed: NSURL?
        do {
            try fm.trashItem(at: original, resultingItemURL: &trashed)
        } catch {
            try? fm.removeItem(at: temp)
            return nil
        }
        do {
            if dest != original && fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.moveItem(at: temp, to: dest)
        } catch {
            // put the original back where it was
            if let tr = trashed as URL? { try? fm.moveItem(at: tr, to: original) }
            try? fm.removeItem(at: temp)
            return nil
        }
        // keep the dates (photo and video timelines sort by them)
        var keep: [FileAttributeKey: Any] = [:]
        if let c = attrs?[.creationDate] { keep[.creationDate] = c }
        if let m = attrs?[.modificationDate] { keep[.modificationDate] = m }
        if !keep.isEmpty { try? fm.setAttributes(keep, ofItemAtPath: dest.path) }
        return dest
    }

    static func size(_ u: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// What the «Schiaccia» overlay shows while files are being squeezed.
struct SqueezeRunState {
    var index = 0
    var total: Int
    var name = ""
    var kind: SqueezeKind = .pdf
    var progress = 0.0
    var saved: Int64 = 0
    var lastSaving: Int? = nil      // % saved on the last finished file (the badge of the animation)
    var tick = 0                    // grows at every file squeezed
    var done = 0, same = 0, failed = 0
    var cancelling = false
    init(total: Int) { self.total = total }
}

/// A thread-safe flag (stop requests from the UI, read by the encoders) with a progress throttle.
final class SqueezeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    private var last = -1.0
    var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
    func set(_ b: Bool) { lock.lock(); on = b; last = -1; lock.unlock() }
    /// True when the progress moved enough to be worth redrawing.
    func throttle(_ p: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if p - last >= 0.01 || p >= 1 { last = p; return true }
        return false
    }
}
