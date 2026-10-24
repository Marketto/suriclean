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

    static func build(reporter: Reporter) -> HomeIndex {
        let idx = HomeIndex()
        let fm = FileManager.default
        let home = FS.home
        var skip = Set(skipTop.map { home.appendingPathComponent($0).path })
        skip.insert(home.appendingPathComponent("go/pkg").path)
        let downloads = home.appendingPathComponent("Downloads").path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        let keySet = Set(keys)
        guard let en = fm.enumerator(at: home, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return idx
        }
        while let obj = en.nextObject() {
            guard let url = obj as? URL else { continue }
            idx.scannedCount += 1
            if idx.scannedCount % 400 == 0 {
                if reporter.isCancelled { break }
                reporter.report(t("mac.busy.sniffed", idx.scannedCount, FS.pretty(url)))
            }
            guard let v = try? url.resourceValues(forKeys: keySet) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                if skip.contains(url.path) { en.skipDescendants(); continue }
                let name = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                if name == ".git" {
                    let repo = url.deletingLastPathComponent()
                    // never offer the home folder itself (dotfiles repos)
                    if repo.standardizedFileURL.path != home.standardizedFileURL.path { idx.repos.append(repo) }
                    en.skipDescendants(); continue
                }
                if ext == "app" {
                    if url.deletingLastPathComponent().path == downloads { idx.downloadApps.append(url) }
                    en.skipDescendants(); continue
                }
                if packageExts.contains(ext) {
                    idx.packages.append(url)
                    en.skipDescendants(); continue
                }
                // dependency folders inside hidden tool dirs (~/.volta, ~/.npm-global, editor
                // extensions…) are installed tools, not project deps
                let rel = url.path.dropFirst(home.path.count + 1)
                let insideHidden = rel.split(separator: "/").dropLast().contains { $0.hasPrefix(".") }
                if !insideHidden, let kind = depKind(url) {
                    idx.deps.append((url, kind))
                    en.skipDescendants(); continue
                }
                continue
            }
            if v.isRegularFile == true {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if size >= 1_048_576 {
                    idx.files.append(IndexedFile(url: url, size: size, modified: v.contentModificationDate))
                }
            }
        }
        reporter.report(t("mac.busy.explored", idx.scannedCount), force: true)
        return idx
    }
}
