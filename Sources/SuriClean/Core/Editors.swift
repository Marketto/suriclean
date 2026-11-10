import Foundation

/// What code editors (VS Code and its cousins) and Claude Code leave behind as they update and as
/// projects come and go: per-project storage of projects long gone, extension versions no longer
/// installed, old versions of Claude Code.
enum Editors {
    /// (Application Support folder, extensions folder in the home, label)
    static let editors: [(String, String, String)] = [
        ("Code", ".vscode/extensions", "VS Code"),
        ("Code - Insiders", ".vscode-insiders/extensions", "VS Code Insiders"),
        ("Cursor", ".cursor/extensions", "Cursor"),
        ("Windsurf", ".windsurf/extensions", "Windsurf"),
        ("VSCodium", ".vscode-oss/extensions", "VSCodium")
    ]

    static func scan(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for (support, ext, label) in editors {
            if rep.isCancelled { break }
            rep.report(label, force: true)
            out += workspaces(FS.library.appendingPathComponent("Application Support/\(support)/User/workspaceStorage"), label, rep)
            out += oldExtensions(FS.home.appendingPathComponent(ext), label, rep)
            if let it = Scanners.makeItem(FS.library.appendingPathComponent("Application Support/\(support)/User/History"),
                                          name: "\(label) · \(t("mac.tg.cronologia_locale"))", risk: .review, recommended: false,
                                          rep: rep, minSize: 50 * 1_048_576) { out.append(it) }
        }
        out += claudeVersions(rep)
        return out
    }

    /// Where a workspaceStorage entry points ("folder" or "workspace" in workspace.json).
    static func workspaceTarget(_ dir: URL) -> URL? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("workspace.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = (j["folder"] ?? j["workspace"]) as? String, let u = URL(string: s), u.isFileURL else { return nil }
        return u
    }

    /// Per-project state (open tabs, extension data): useless when the project is gone or untouched for months.
    static func workspaces(_ root: URL, _ label: String, _ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for dir in FS.children(root) where FS.isDir(dir) {
            if rep.isCancelled { break }
            let target = workspaceTarget(dir)
            let gone = target.map { !FS.exists($0) } ?? false
            let used = FS.newestModDate(dir)
            let idle = FS.daysSince(used) > 90
            let name = target.map { $0.deletingPathExtension().lastPathComponent } ?? dir.lastPathComponent
            var badges: [String] = []
            if gone { badges.append(t("mac.badge.projgone")) } else if idle { badges.append(t("mac.badge.oldf")) }
            if let it = Scanners.makeItem(dir, name: "\(label) · \(t("mac.tg.dati_progetto", name))",
                                          detail: t("mac.detail.lastmod", target.map { FS.pretty($0) } ?? FS.pretty(dir), Fmt.relative(used)),
                                          risk: .review, recommended: gone || idle, rep: rep, minSize: 5 * 1_048_576,
                                          badges: badges, date: used) {
                out.append(it)
            }
        }
        return out
    }

    /// Extension folders the editor no longer uses: not listed in extensions.json, or listed in .obsolete.
    static func oldExtensions(_ root: URL, _ label: String, _ rep: Reporter) -> [CleanItem] {
        guard FS.exists(root) else { return [] }
        var installed = Set<String>()
        if let d = try? Data(contentsOf: root.appendingPathComponent("extensions.json")),
           let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            for e in list {
                if let rel = e["relativeLocation"] as? String { installed.insert(rel) }
                if let loc = e["location"] as? [String: Any], let p = (loc["path"] ?? loc["fsPath"]) as? String {
                    installed.insert(URL(fileURLWithPath: p).lastPathComponent)
                }
            }
        }
        var obsolete = Set<String>()
        if let d = try? Data(contentsOf: root.appendingPathComponent(".obsolete")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            obsolete = Set(j.keys)
        }
        guard !installed.isEmpty || !obsolete.isEmpty else { return [] }   // no list: cannot tell, leave them alone
        var out: [CleanItem] = []
        for dir in FS.children(root) where FS.isDir(dir) {
            let n = dir.lastPathComponent
            guard !n.hasPrefix("."), obsolete.contains(n) || (!installed.isEmpty && !installed.contains(n)) else { continue }
            if let it = Scanners.makeItem(dir, name: "\(label) · \(t("mac.tg.estensione_vecchia", n))",
                                          detail: FS.pretty(dir), risk: .safe, recommended: true, rep: rep,
                                          minSize: 256 * 1024, badges: [t("mac.badge.notinstalled")]) {
                out.append(it)
            }
        }
        return out
    }

    /// The native Claude Code installer keeps every version it downloaded: only the one in use
    /// (and the newest, in case an update is pending) are needed.
    static func claudeVersions(_ rep: Reporter) -> [CleanItem] {
        let root = FS.home.appendingPathComponent(".local/share/claude/versions")
        let versions = FS.children(root).filter { !$0.lastPathComponent.hasPrefix(".") }
        guard versions.count > 1 else { return [] }
        let link = FS.home.appendingPathComponent(".local/bin/claude")
        let current = link.resolvingSymlinksInPath().standardizedFileURL.path
        // only when we know which one is in use
        guard FS.exists(link), current.hasPrefix(root.standardizedFileURL.path + "/") else { return [] }
        let newest = versions.max { (FS.modDate($0) ?? .distantPast) < (FS.modDate($1) ?? .distantPast) }
        var out: [CleanItem] = []
        for v in versions {
            let p = v.standardizedFileURL.path
            if p == current || current.hasPrefix(p + "/") || v == newest { continue }
            if let it = Scanners.makeItem(v, name: "Claude Code · \(t("mac.tg.versione_vecchia", v.lastPathComponent))",
                                          detail: FS.pretty(v), risk: .safe, recommended: true, rep: rep,
                                          minSize: 1_048_576, badges: [t("mac.badge.notinuse")]) {
                out.append(it)
            }
        }
        return out
    }
}
