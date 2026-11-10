import Foundation

struct IndexedFile {
    let url: URL
    let size: Int64
    let modified: Date?
}

/// One single walk of the home folder, shared by several categories.
final class HomeIndex {
    var files: [IndexedFile] = []          // regular files >= 1 MB
    var repos: [URL] = []                  // folders containing .git
    var deps: [(url: URL, kind: String)] = []
    var packages: [URL] = []               // Photos libraries, VMs, …
    var downloadApps: [URL] = []
    var scannedCount = 0
    let built = Date()

    var isStale: Bool { Date().timeIntervalSince(built) > 900 }

    static let packageExts: Set<String> = [
        "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "fcpbundle", "imovielibrary",
        "aplibrary", "logicx", "band", "sparsebundle", "utm", "pvm", "vmwarevm", "xcarchive"
    ]

    /// Folders handled by dedicated scanners (or not worth walking).
    static let skipTop = [
        "Library", ".Trash", ".npm", ".cache", ".gradle", ".m2", ".cargo", ".rustup", ".pub-cache",
        ".cocoapods", ".claude", ".codex", ".gemini", ".ollama", ".docker", ".android", ".lmstudio",
        ".vscode", ".cursor", ".nvm", ".bun", ".yarn", ".pnpm-store", ".local/share/Trash"
    ]

    func prune(removed: [URL]) {
        let prefixes = removed.map { $0.path }
        func gone(_ u: URL) -> Bool { prefixes.contains { u.path == $0 || u.path.hasPrefix($0 + "/") } }
        files.removeAll { gone($0.url) }
        repos.removeAll { gone($0) }
        deps.removeAll { gone($0.url) }
        packages.removeAll { gone($0) }
        downloadApps.removeAll { gone($0) }
    }

    static func depKind(_ dir: URL) -> String? {
        let name = dir.lastPathComponent
        let parent = dir.deletingLastPathComponent()
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: parent.appendingPathComponent(f).path) }
        switch name {
        case "node_modules":
            return has("package.json") ? "Node.js (npm/yarn/pnpm)" : nil
        case ".venv", "venv", "env", ".env":
            return fm.fileExists(atPath: dir.appendingPathComponent("pyvenv.cfg").path) ? "Python virtualenv" : nil
        case "target":
            if has("Cargo.toml") { return "Rust (cargo)" }
            if has("pom.xml") { return "Maven" }
            return nil
        case ".build":
            return has("Package.swift") ? "Swift Package Manager" : nil
        case "Pods":
            return has("Podfile") ? "CocoaPods" : nil
        case ".gradle":
            return (has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") || has("settings.gradle.kts")) ? t("mac.dep.gradlecache") : nil
        case "build":
            return (has("build.gradle") || has("build.gradle.kts")) ? "Gradle (build)" : (has("pubspec.yaml") ? "Flutter (build)" : nil)
        case ".next":
            return has("package.json") ? "Next.js (build)" : nil
        case ".nuxt", ".output":
            return has("nuxt.config.ts") || has("nuxt.config.js") ? "Nuxt (build)" : nil
        case ".dart_tool":
            return has("pubspec.yaml") ? "Dart/Flutter" : nil
        case "vendor":
            return has("composer.json") ? "PHP Composer" : nil
        case ".turbo", ".parcel-cache", ".angular":
            return has("package.json") ? t("mac.dep.jsbuild") : nil
        case "DerivedData":
            return t("mac.dep.derived")
        default:
            return nil
        }
    }

    static let depNames: Set<Substring> = [
        "node_modules", ".venv", "venv", "env", ".env", "target", ".build", "Pods", ".gradle", "build", ".next",
        ".nuxt", ".output", ".dart_tool", "vendor", ".turbo", ".parcel-cache", ".angular", "DerivedData"
    ]

    /// Notes a folder met during the walk; true when its content is not for the index
    /// (handled by a dedicated scanner, a repo, an app or package, a dependency folder).
    private func note(dir path: String, name: Substring, home: String, skip: Set<String>, downloads: String) -> Bool {
        if skip.contains(path) { return true }
        let parent = String(path[..<(path.lastIndex(of: "/") ?? path.endIndex)])
        if name == ".git" {
            if parent != home { repos.append(URL(fileURLWithPath: parent, isDirectory: true)) }   // never the home itself (dotfiles repos)
            return true
        }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let ext = name[name.index(after: dot)...].lowercased()
            if ext == "app" {
                if parent == downloads { downloadApps.append(URL(fileURLWithPath: path, isDirectory: true)) }
                return true
            }
            if HomeIndex.packageExts.contains(ext) {
                packages.append(URL(fileURLWithPath: path, isDirectory: true))
                return true
            }
        }
        guard HomeIndex.depNames.contains(name) else { return false }
        // dependency folders inside hidden tool dirs (~/.volta, ~/.npm-global, editor
        // extensions…) are installed tools, not project deps
        let rel = path.dropFirst(home.count + 1)
        let insideHidden = rel.split(separator: "/").dropLast().contains { $0.hasPrefix(".") }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if !insideHidden, let kind = HomeIndex.depKind(url) {
            deps.append((url, kind))
            return true
        }
        return false
    }

    struct Walk {
        var index: HomeIndex
        /// Size of every folder 1…4 levels below the home (only when measuring).
        var sizes: [String: Int64] = [:]
        var total: Int64 = 0
    }

    static func build(reporter: Reporter) -> HomeIndex { walk(reporter: reporter, measure: false).index }

    /// One single walk of the home folder (FastWalk). With `measure` nothing is skipped and every
    /// folder is measured too, so the disk map and the index cost one walk instead of two.
    static func walk(reporter: Reporter, measure: Bool, mapDepth: Int = 4) -> Walk {
        let idx = HomeIndex()
        let home = FS.home.standardizedFileURL.path
        var skip = Set(skipTop.map { home + "/" + $0 })
        skip.insert(home + "/go/pkg")
        let downloads = home + "/Downloads"
        var w = Walk(index: idx)
        var hidden: String?          // folder being measured whose content the index leaves out
        var hiddenSlash = ""
        var stack: [(path: String, acc: Int64)] = []
        FastWalk.walk(home) { e in
            idx.scannedCount += 1
            if idx.scannedCount % 1000 == 0 {
                if reporter.isCancelled { return .stop }
                reporter.report(t(measure ? "mac.busy.measured" : "mac.busy.sniffed", idx.scannedCount, FS.pretty(URL(fileURLWithPath: e.path))))
            }
            if let h = hidden, e.path != h && !e.path.hasPrefix(hiddenSlash) { hidden = nil }
            switch e.kind {
            case .dir:
                if measure { stack.append((e.path, 0)) }
                if hidden == nil && e.level > 0 && idx.note(dir: e.path, name: e.name, home: home, skip: skip, downloads: downloads) {
                    if !measure { return .skip }
                    hidden = e.path
                    hiddenSlash = e.path + "/"
                }
            case .dirEnd:
                if measure, let top = stack.last, top.path == e.path {
                    stack.removeLast()
                    if e.level >= 1 && e.level <= mapDepth { w.sizes[e.path] = top.acc }
                    if stack.isEmpty { w.total = top.acc } else { stack[stack.count - 1].acc += top.acc }
                }
            case .file:
                if measure, !stack.isEmpty { stack[stack.count - 1].acc += e.size }
                if hidden == nil && e.size >= 1_048_576 {
                    idx.files.append(IndexedFile(url: URL(fileURLWithPath: e.path), size: e.size,
                                                 modified: Date(timeIntervalSince1970: e.modified)))
                }
            case .other:
                break
            }
            return .go
        }
        reporter.report(t("mac.busy.explored", idx.scannedCount), force: true)
        return w
    }
}
