import Foundation
import CryptoKit

// MARK: - Git

struct RepoInfo {
    var lastActivity: Date?
    var remote: String?
    var dirty: Bool
    var unpushed: Int
    var stashed: Bool
    var safe: Bool { remote != nil && !dirty && unpushed == 0 && !stashed }
}

enum GitInspector {
    /// /usr/bin/git is only a shim: without Command Line Tools it would pop up an install dialog.
    static let available: Bool = {
        let r = Shell.run("/usr/bin/xcode-select", ["-p"])
        return r.status == 0 && !r.output.isEmpty && FileManager.default.fileExists(atPath: r.output)
    }()

    static func sanitize(_ remote: String) -> String {
        // strip credentials like https://user:token@github.com/…
        guard let schemeEnd = remote.range(of: "://"), let at = remote.range(of: "@", range: schemeEnd.upperBound..<remote.endIndex) else {
            return remote
        }
        return String(remote[..<schemeEnd.upperBound]) + String(remote[at.upperBound...])
    }

    static func shortRemote(_ r: String) -> String {
        var s = r
        for p in ["https://", "http://", "ssh://", "git@"] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s.replacingOccurrences(of: ":", with: "/")
    }

    static let regenerable: Set<String> = [
        "node_modules", ".venv", "venv", "env", "target", "build", ".build", "Pods", "DerivedData", ".next", ".nuxt",
        "dist", "out", ".gradle", ".dart_tool", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".DS_Store", ".turbo", ".parcel-cache", ".angular", ".cache", "coverage", ".idea", ".vscode", "vendor", ".swiftpm"
    ]

    static func inspect(_ repo: URL) -> RepoInfo {
        func g(_ args: [String]) -> ShellResult {
            Shell.run("/usr/bin/git", ["-C", repo.path] + args,
                      env: ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"])
        }
        var dates: [Date] = []
        let last = g(["log", "-1", "--format=%ct"])
        if last.status == 0, let ts = Double(last.output) { dates.append(Date(timeIntervalSince1970: ts)) }
        for f in ["index", "FETCH_HEAD", "HEAD", "ORIG_HEAD"] {
            if let d = FS.modDate(repo.appendingPathComponent(".git/\(f)")) { dates.append(d) }
        }
        var remote: String? = nil
        let origin = g(["remote", "get-url", "origin"])
        if origin.status == 0, !origin.output.isEmpty {
            remote = origin.output
        } else if let first = g(["remote"]).output.split(separator: "\n").first {
            let u = g(["remote", "get-url", String(first)])
            if u.status == 0, !u.output.isEmpty { remote = u.output }
        }
        let st = g(["status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=none"])
        var dirty = st.status != 0 || !st.output.isEmpty
        // Ignored files that can't be regenerated (.env, local data…) can't be re-cloned either.
        let ign = g(["status", "--porcelain", "--ignored", "--untracked-files=normal"])
        if ign.status != 0 { dirty = true }
        for line in ign.output.split(separator: "\n") where line.hasPrefix("!! ") {
            let path = line.dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: "\"/"))
            let first = String(path.split(separator: "/").first ?? "")
            let last = String(path.split(separator: "/").last ?? "")
            if !regenerable.contains(first) && !regenerable.contains(last) && !last.hasSuffix(".pyc") && !last.hasSuffix(".log") {
                dirty = true
                break
            }
        }
        let up = g(["log", "--branches", "--tags", "HEAD", "--not", "--remotes", "--oneline", "-n", "99"])
        let unpushed: Int
        if up.status != 0 { unpushed = last.status == 0 ? 1 : 0 }   // unknown = unsafe (empty repos have no log)
        else { unpushed = up.output.isEmpty ? 0 : up.output.split(separator: "\n").count }
        let stash = g(["stash", "list"])
        let networkRemote = remote.map { r in (r.contains("://") && !r.hasPrefix("file:")) || r.contains("@") } ?? false
        return RepoInfo(lastActivity: dates.max(), remote: networkRemote ? remote.map(sanitize) : nil, dirty: dirty,
                        unpushed: unpushed, stashed: !stash.output.isEmpty)
    }
}

// MARK: - Duplicates

enum Duplicates {
    static func hex(_ d: SHA256.Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func partialHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        if let d = try? h.read(upToCount: 65_536) { hasher.update(data: d) }
        if let end = try? h.seekToEnd(), end > 131_072 {
            try? h.seek(toOffset: end - 65_536)
            if let d = try? h.read(upToCount: 65_536) { hasher.update(data: d) }
        }
        return hex(hasher.finalize())
    }

    static func fullHash(_ url: URL, _ rep: Reporter) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            if rep.isCancelled { return nil }
            guard let d = try? h.read(upToCount: 1 << 20), !d.isEmpty else { break }
            hasher.update(data: d)
        }
        return hex(hasher.finalize())
    }

    static func inode(_ url: URL) -> UInt64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    /// Lower = better candidate to keep.
    static func keepScore(_ f: IndexedFile) -> Int {
        let p = f.url.path.lowercased()
        var s = f.url.pathComponents.count * 10
        if p.contains("/downloads/") || p.contains("/desktop/") { s += 1000 }
        let n = f.url.lastPathComponent.lowercased()
        if n.contains("copy") || n.contains("copia") || n.contains(" (1)") || n.contains(" (2)") || n.contains(" 2.") { s += 500 }
        return s
    }

    static func find(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index else { return [] }
        let bySize = Dictionary(grouping: index.files, by: { $0.size }).values.filter { $0.count > 1 }
        var candidates: [[IndexedFile]] = []
        for (i, group) in bySize.enumerated() {
            if rep.isCancelled { return [] }
            rep.report("Confronto impronte: \(group[0].url.lastPathComponent)", progress: Double(i) / Double(max(bySize.count, 1)) * 0.4)
            var seen = Set<UInt64>()
            let uniq = group.filter { f in
                guard let ino = inode(f.url) else { return true }
                return seen.insert(ino).inserted   // skip hard links
            }
            guard uniq.count > 1 else { continue }
            let byPartial = Dictionary(grouping: uniq, by: { partialHash($0.url) ?? UUID().uuidString })
            for g in byPartial.values where g.count > 1 { candidates.append(g) }
        }
        var groups: [[IndexedFile]] = []
        for (i, g) in candidates.enumerated() {
            if rep.isCancelled { return [] }
            rep.report("SHA-256 di \(g[0].url.lastPathComponent)", progress: 0.4 + Double(i) / Double(max(candidates.count, 1)) * 0.6)
            let byFull = Dictionary(grouping: g, by: { fullHash($0.url, rep) ?? UUID().uuidString })
            for gg in byFull.values where gg.count > 1 { groups.append(gg) }
        }
        groups.sort { $0[0].size * Int64($0.count) > $1[0].size * Int64($1.count) }
        var out: [CleanItem] = []
        for (gid, g) in groups.enumerated() {
            let sorted = g.sorted { keepScore($0) < keepScore($1) }
            let label = "\(sorted[0].url.lastPathComponent) · \(g.count) copie da \(Fmt.bytes(g[0].size))"
            for (j, f) in sorted.enumerated() {
                let keep = j == 0
                out.append(CleanItem(url: f.url, name: f.url.lastPathComponent,
                                     detail: FS.pretty(f.url.deletingLastPathComponent()),
                                     size: f.size, date: f.modified, risk: keep ? .careful : .safe,
                                     recommended: !keep, badges: [keep ? "💎 da tenere" : "👯 copia"],
                                     group: gid, groupLabel: label))
            }
        }
        return out
    }
}

// MARK: - Cleaner

enum Cleaner {
    struct Outcome {
        var removed: [UUID] = []
        var removedURLs: [URL] = []
        var bytes: Int64 = 0
        var failed: [String] = []
    }

    static func trash(_ items: [CleanItem], reporter: Reporter) -> Outcome {
        var o = Outcome()
        let fm = FileManager.default
        var repoLog: [String] = []
        let stamp = ISO8601DateFormatter().string(from: Date())
        for (i, item) in items.enumerated() {
            if reporter.isCancelled { break }
            reporter.report(item.name, progress: Double(i) / Double(max(items.count, 1)), force: true)
            if !fm.fileExists(atPath: item.url.path) {
                o.removed.append(item.id)        // already gone (e.g. inside a repo removed earlier)
                continue
            }
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                for extra in item.extraURLs where fm.fileExists(atPath: extra.path) {
                    try? fm.trashItem(at: extra, resultingItemURL: nil)
                }
                o.removed.append(item.id)
                o.removedURLs.append(item.url)
                o.bytes += item.size
                if let c = item.copyText { repoLog.append("# \(item.url.path)  (rimosso \(stamp))\n\(c)") }
            } catch {
                o.failed.append(item.name)
            }
        }
        FS.appendToRepoLog(repoLog)
        reporter.report("Fatto!", progress: 1, force: true)
        return o
    }

    @discardableResult
    static func emptyTrash() -> Bool {
        let fm = FileManager.default
        var allOK = true
        if let kids = try? fm.contentsOfDirectory(at: FS.trashURL, includingPropertiesForKeys: nil, options: []) {
            for k in kids {
                if (try? fm.removeItem(at: k)) == nil {
                    // e.g. Go modules are read-only
                    _ = Shell.run("/bin/chmod", ["-R", "u+w", k.path])
                    if (try? fm.removeItem(at: k)) == nil { allOK = false }
                }
            }
        } else {
            allOK = false
        }
        if !allOK {
            _ = Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
        }
        return allOK
    }
}
