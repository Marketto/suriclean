import Foundation
import AppKit
import CoreServices

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, b), countStyle: .file)
    }

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.unitsStyle = .full
        return f
    }()

    static func relative(_ d: Date?) -> String {
        guard let d = d else { return "mai" }
        return relativeFormatter.localizedString(for: d, relativeTo: Date())
    }
}

func frac(_ x: Double) -> Double { x - floor(x) }

// MARK: - Shell

struct ShellResult {
    let status: Int32
    let output: String
}

enum Shell {
    static func run(_ exe: String, _ args: [String], env extra: [String: String] = [:], mergeStderr: Bool = false) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extra { env[k] = v }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = mergeStderr ? out : FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return ShellResult(status: -1, output: "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellResult(status: p.terminationStatus, output: text)
    }
}

// MARK: - Progress reporter (thread-safe cancel flag + throttled UI updates)

final class Reporter {
    private let lock = NSLock()
    private var cancelledFlag = false
    private var last = Date.distantPast
    var onUpdate: (@MainActor (String, Double?) -> Void)?

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelledFlag
    }

    func cancel() {
        lock.lock(); cancelledFlag = true; lock.unlock()
    }

    func report(_ text: String, progress: Double? = nil, force: Bool = false) {
        lock.lock()
        let now = Date()
        let tooSoon = now.timeIntervalSince(last) < 0.08
        if !tooSoon || force { last = now }
        lock.unlock()
        if tooSoon && !force { return }
        guard let cb = onUpdate else { return }
        Task { @MainActor in cb(text, progress) }
    }
}

// MARK: - Disk

struct DiskInfo {
    var total: Int64 = 0
    var available: Int64 = 0
    var availableImportant: Int64 = 0

    var used: Int64 { max(0, total - availableImportant) }
    var purgeable: Int64 { max(0, availableImportant - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? FS.home.resourceValues(forKeys: keys) else { return DiskInfo() }
        let avail = Int64(v.volumeAvailableCapacity ?? 0)
        return DiskInfo(total: Int64(v.volumeTotalCapacity ?? 0),
                        available: avail,
                        availableImportant: v.volumeAvailableCapacityForImportantUsage ?? avail)
    }
}

// MARK: - File system helpers

enum FS {
    static let fm = FileManager.default
    /// Overridden when SuriClean runs as the admin helper for another user's folder.
    static var home = FileManager.default.homeDirectoryForCurrentUser
    static var isHelper = false
    static var library: URL { home.appendingPathComponent("Library") }
    static var trashURL: URL { home.appendingPathComponent(".Trash") }
    static let ownBundleID = "com.suriclean.app"

    static func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }

    static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    static func children(_ u: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [])) ?? []
    }

    static func modDate(_ u: URL) -> Date? {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey])
        return v?.contentModificationDate
    }

    /// Newest modification date among the item and its direct children.
    static func newestModDate(_ u: URL, excluding: Set<String> = []) -> Date? {
        var best = modDate(u)
        for c in children(u) where !excluding.contains(c.lastPathComponent) {
            if let d = modDate(c), d > (best ?? .distantPast) { best = d }
        }
        return best
    }

    static func daysSince(_ d: Date?) -> Int {
        guard let d = d else { return 99_999 }
        return Int(Date().timeIntervalSince(d) / 86_400)
    }

    static func pretty(_ u: URL) -> String {
        let p = u.path
        let h = home.path
        if p.hasPrefix(h) { return "~" + String(p.dropFirst(h.count)) }
        return p
    }

    private static let sizeKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// Real space on disk (allocated size), recursing into folders and packages.
    static func allocatedSize(_ url: URL, reporter: Reporter? = nil) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var n = 0
        while let obj = en.nextObject() {
            guard let f = obj as? URL else { continue }
            n += 1
            if n % 500 == 0 {
                if reporter?.isCancelled == true { break }
                reporter?.report(pretty(f))
            }
            guard let fv = try? f.resourceValues(forKeys: sizeKeys), fv.isRegularFile == true else { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Reading TCC.db is only possible with Full Disk Access.
    static func hasFullDiskAccess() -> Bool {
        let probe = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        if let h = try? FileHandle(forReadingFrom: probe) {
            try? h.close()
            return true
        }
        return (try? fm.contentsOfDirectory(atPath: library.appendingPathComponent("Safari").path)) != nil
    }

    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        guard let raw = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return raw as? Date
    }

    /// Support files an app usually leaves in ~/Library.
    static func leftovers(bundleID id: String, name: String) -> [URL] {
        var rel: [String] = []
        if !id.isEmpty {
            rel += [
                "Application Support/\(id)", "Caches/\(id)", "Caches/\(id).ShipIt",
                "Preferences/\(id).plist", "Containers/\(id)", "Application Scripts/\(id)",
                "Saved Application State/\(id).savedState", "HTTPStorages/\(id)",
                "HTTPStorages/\(id).binarycookies", "WebKit/\(id)", "Cookies/\(id).binarycookies",
                "Logs/\(id)"
            ]
        }
        if name.count > 3 {
            rel += ["Application Support/\(name)", "Logs/\(name)"]
        }
        var seen = Set<String>()
        return rel.map { library.appendingPathComponent($0) }
            .filter { exists($0) && seen.insert($0.path).inserted }
    }

    static let knownNames: [String: String] = [
        "Homebrew": "Homebrew (download)",
        "pip": "Python pip",
        "pypoetry": "Poetry",
        "Yarn": "Yarn",
        "ms-playwright": "Playwright (browser di test)",
        "node-gyp": "node-gyp",
        "typescript": "TypeScript",
        "pnpm": "pnpm",
        "go-build": "Go · cache di build",
        "JetBrains": "JetBrains IDE",
        "CocoaPods": "CocoaPods",
        "Google": "Google (Chrome & co.)",
        "Firefox": "Firefox",
        "Mozilla": "Mozilla",
        "com.spotify.client": "Spotify",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.microsoft.VSCode": "VS Code",
        "com.apple.Safari": "Safari",
        "com.apple.dt.Xcode": "Xcode",
        "SiriTTS": "Voci di Siri",
        "GeoServices": "Mappe (cache)",
        "electron": "Electron",
        "deno": "Deno",
        "bun": "Bun"
    ]

    static func friendlyName(_ raw: String) -> String {
        if let k = knownNames[raw] { return k }
        if raw.contains("."), let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        if raw.hasPrefix("com.apple.") {
            return "Apple · " + raw.replacingOccurrences(of: "com.apple.", with: "")
        }
        if raw.contains("."), let last = raw.split(separator: ".").last {
            return "\(last) (\(raw))"
        }
        return raw
    }

    static func appendToRepoLog(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let docs = home.appendingPathComponent("Documents")
        let log = docs.appendingPathComponent("SuriClean - repo rimossi.txt")
        let text = lines.joined(separator: "\n\n") + "\n\n"
        if let h = try? FileHandle(forWritingTo: log) {
            _ = try? h.seekToEnd()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            let header = "# Repo spostati nel Cestino da SuriClean.\n# Per riaverli basta lanciare il comando git clone sotto ciascuno.\n\n"
            try? (header + text).write(to: log, atomically: true, encoding: .utf8)
        }
    }
}

enum IconCache {
    static let cache = NSCache<NSString, NSImage>()
    static func icon(_ url: URL) -> NSImage {
        let key = url.path as NSString
        if let i = cache.object(forKey: key) { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(i, forKey: key)
        return i
    }
}
