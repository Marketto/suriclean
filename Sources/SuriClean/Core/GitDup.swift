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

    /// A remote somewhere else (not a folder on this disk), so the repo can be cloned again.
    static func isNetwork(_ r: String) -> Bool { (r.contains("://") && !r.hasPrefix("file:")) || r.contains("@") }

    /// The url of `origin`, read from .git/config as plain text (no git run).
    static func originFromConfig(_ repo: URL) -> String? {
        guard let text = try? String(contentsOf: repo.appendingPathComponent(".git/config"), encoding: .utf8) else { return nil }
        var inOrigin = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"; continue }
            if inOrigin, line.hasPrefix("url"), let eq = line.firstIndex(of: "=") {
                let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    static func inspect(_ repo: URL) -> RepoInfo {
        var dates: [Date] = []
        // As administrator, on another user's repo, git must not run at all: the repo's own config
        // (core.fsmonitor, filters…) could make root run that user's commands. Unknown = not safe.
        if FS.isHelper {
            for f in ["index", "FETCH_HEAD", "HEAD", "ORIG_HEAD"] {
                if let d = FS.modDate(repo.appendingPathComponent(".git/\(f)")) { dates.append(d) }
            }
            return RepoInfo(lastActivity: dates.max(), remote: originFromConfig(repo).flatMap { isNetwork($0) ? sanitize($0) : nil }, dirty: true, unpushed: 0, stashed: false)
        }
        func g(_ args: [String]) -> ShellResult {
            Shell.run("/usr/bin/git", ["-C", repo.path, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"] + args,
                      env: ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C",
                            "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.directory", "GIT_CONFIG_VALUE_0": "*"])
        }
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
        let networkRemote = remote.map(isNetwork) ?? false
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
            rep.report(t("mac.busy.compare", group[0].url.lastPathComponent), progress: Double(i) / Double(max(bySize.count, 1)) * 0.4)
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
            rep.report(t("mac.busy.sha", g[0].url.lastPathComponent), progress: 0.4 + Double(i) / Double(max(candidates.count, 1)) * 0.6)
            let byFull = Dictionary(grouping: g, by: { fullHash($0.url, rep) ?? UUID().uuidString })
            for gg in byFull.values where gg.count > 1 { groups.append(gg) }
        }
        groups.sort { $0[0].size * Int64($0.count) > $1[0].size * Int64($1.count) }
        var out: [CleanItem] = []
        for (gid, g) in groups.enumerated() {
            let sorted = g.sorted { keepScore($0) < keepScore($1) }
            let label = t("mac.dup.group", sorted[0].url.lastPathComponent, g.count, Fmt.bytes(g[0].size))
            for (j, f) in sorted.enumerated() {
                let keep = j == 0
                out.append(CleanItem(url: f.url, name: f.url.lastPathComponent,
                                     detail: FS.pretty(f.url.deletingLastPathComponent()),
                                     size: f.size, date: f.modified, risk: keep ? .careful : .safe,
                                     recommended: !keep, badges: [keep ? t("mac.badge.keep") : t("mac.badge.copy")],
                                     group: gid, groupLabel: label))
            }
        }
        return out
    }
}
