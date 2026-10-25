import Foundation
import AppKit

struct Target {
    let path: String           // relative to home
    let name: String
    var risk: Risk = .safe
    var recommended: Bool = true
    var perChild: Bool = false
    var olderThanDays: Int? = nil
}

enum Targets {
    static func electron(_ app: String, _ label: String) -> [Target] {
        ["Cache", "CachedData", "Code Cache", "GPUCache", "CachedExtensionVSIXs", "DawnCache", "DawnGraphiteCache", "logs", "Crashpad/completed"]
            .map { Target(path: "Library/Application Support/\(app)/\($0)", name: "\(label) · \($0)") }
    }

    static var ai: [Target] {
        let base: [Target] = [
        Target(path: ".claude/projects", name: "Claude Code · \(t("mac.tg.sessioni"))", risk: .review, recommended: false, perChild: true, olderThanDays: 30),
        Target(path: ".claude/file-history", name: "Claude Code · \(t("mac.tg.storico_file_modificati"))"),
        Target(path: ".claude/shell-snapshots", name: "Claude Code · \(t("mac.tg.snapshot_della_shell"))"),
        Target(path: ".claude/todos", name: "Claude Code · \(t("mac.tg.liste_todo_vecchie"))"),
        Target(path: ".claude/debug", name: "Claude Code · \(t("mac.tg.log_di_debug"))"),
        Target(path: ".claude/statsig", name: "Claude Code · \(t("mac.tg.cache_telemetria"))"),
        Target(path: ".claude/paste-cache", name: "Claude Code · \(t("mac.tg.cache_incolla"))"),
        Target(path: "Library/Caches/claude-cli-nodejs", name: "Claude Code · \(t("mac.tg.log_mcp_e_cache"))"),
        Target(path: ".codex/sessions", name: "Codex · \(t("mac.tg.sessioni"))", risk: .review, recommended: false, perChild: true, olderThanDays: 30),
        Target(path: ".codex/archived_sessions", name: "Codex · \(t("mac.tg.sessioni_archiviate"))", risk: .review, recommended: false),
        Target(path: ".codex/log", name: "Codex · \(t("mac.tg.log"))"),
        Target(path: ".gemini/tmp", name: "Gemini CLI · \(t("mac.tg.temporanei"))"),
        Target(path: "Library/Caches/com.anthropic.claudefordesktop", name: "Claude Desktop · \(t("mac.tg.cache"))"),
        Target(path: "Library/Caches/com.anthropic.claudefordesktop.ShipIt", name: "Claude Desktop · \(t("mac.tg.aggiornamenti_scaricati"))"),
        Target(path: "Library/Application Support/Claude/vm_bundles", name: "Claude Desktop · \(t("mac.tg.immagini_vm"))", risk: .review, recommended: false),
        Target(path: "Library/Logs/Claude", name: "Claude Desktop · \(t("mac.tg.log"))"),
        Target(path: "Library/Caches/com.openai.chat", name: "ChatGPT · \(t("mac.tg.cache"))"),
        Target(path: "Library/Caches/com.todesktop.230313mzl4w4u92", name: "Cursor · \(t("mac.tg.cache"))"),
        Target(path: "Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt", name: "Cursor · \(t("mac.tg.aggiornamenti_scaricati"))"),
        Target(path: ".cache/huggingface", name: "Hugging Face · \(t("mac.tg.modelli_scaricati"))", risk: .review, recommended: false),
        Target(path: ".ollama/models", name: "Ollama · \(t("mac.tg.modelli"))", risk: .review, recommended: false),
        Target(path: ".lmstudio/models", name: "LM Studio · \(t("mac.tg.modelli"))", risk: .review, recommended: false),
        Target(path: ".cache/lm-studio", name: "LM Studio · \(t("mac.tg.cache"))", risk: .review, recommended: false),
        Target(path: ".cache/whisper", name: "Whisper · \(t("mac.tg.modelli"))", risk: .review, recommended: false),
        Target(path: ".cache/torch", name: "PyTorch · \(t("mac.tg.cache_modelli"))", risk: .review, recommended: false)
    ]
        return base + electron("Claude", "Claude Desktop") + electron("Cursor", "Cursor")
            + electron("Code", "VS Code") + electron("Windsurf", "Windsurf")
    }

    static var dev: [Target] { [
        Target(path: "Library/Developer/Xcode/DerivedData", name: "Xcode · DerivedData"),
        Target(path: "Library/Developer/Xcode/iOS DeviceSupport", name: "Xcode · iOS DeviceSupport"),
        Target(path: "Library/Developer/Xcode/watchOS DeviceSupport", name: "Xcode · watchOS DeviceSupport"),
        Target(path: "Library/Developer/Xcode/Archives", name: "Xcode · \(t("mac.tg.archivi_delle_build"))", risk: .review, recommended: false),
        Target(path: "Library/Developer/CoreSimulator/Caches", name: "\(t("mac.tg.label.sims")) · \(t("mac.tg.cache"))"),
        Target(path: ".npm/_cacache", name: "npm · \(t("mac.tg.cache"))"),
        Target(path: ".npm/_npx", name: "npx · \(t("mac.tg.pacchetti_temporanei"))"),
        Target(path: ".npm/_logs", name: "npm · \(t("mac.tg.log"))"),
        Target(path: ".yarn/berry/cache", name: "Yarn Berry · \(t("mac.tg.cache"))"),
        Target(path: ".cache/yarn", name: "Yarn · \(t("mac.tg.cache"))"),
        Target(path: "Library/pnpm/store", name: "pnpm · store"),
        Target(path: ".pnpm-store", name: "pnpm · store"),
        Target(path: ".bun/install/cache", name: "Bun · \(t("mac.tg.cache"))"),
        Target(path: ".nvm/.cache", name: "nvm · \(t("mac.tg.download_di_node"))"),
        Target(path: ".cache/node-gyp", name: "node-gyp · \(t("mac.tg.header"))"),
        Target(path: ".electron-gyp", name: "electron-gyp · \(t("mac.tg.header"))"),
        Target(path: ".gradle/caches", name: "Gradle · \(t("mac.tg.cache"))"),
        Target(path: ".gradle/wrapper/dists", name: "Gradle · \(t("mac.tg.distribuzioni"))"),
        Target(path: ".m2/repository", name: "Maven · \(t("mac.tg.repository_locale"))"),
        Target(path: ".cargo/registry", name: "Cargo · registry"),
        Target(path: ".cargo/git", name: "Cargo · \(t("mac.tg.dipendenze_git"))"),
        Target(path: ".rustup/toolchains", name: "Rust · \(t("mac.tg.toolchain_installate"))", risk: .review, recommended: false),
        Target(path: "go/pkg/mod", name: "Go · \(t("mac.tg.moduli"))"),
        Target(path: ".cocoapods/repos", name: "CocoaPods · \(t("mac.tg.repo_delle_spec"))"),
        Target(path: ".pub-cache", name: "Dart/Flutter · pub cache"),
        Target(path: ".android/cache", name: "Android · \(t("mac.tg.cache"))"),
        Target(path: ".android/avd", name: "Android · \(t("mac.tg.emulatori"))", risk: .review, recommended: false),
        Target(path: ".cache/uv", name: "uv · \(t("mac.tg.cache_python"))"),
        Target(path: ".cache/pre-commit", name: "pre-commit · \(t("mac.tg.ambienti"))"),
        Target(path: ".cache/puppeteer", name: "Puppeteer · \(t("mac.tg.browser"))"),
        Target(path: "Library/Containers/com.docker.docker/Data/vms", name: "Docker · \(t("mac.tg.disco_della_vm"))", risk: .careful, recommended: false),
        Target(path: "Library/Developer/CoreSimulator/Devices", name: "\(t("mac.tg.label.iossims")) · \(t("mac.tg.dispositivi"))", risk: .review, recommended: false),
        Target(path: "Library/Developer/Xcode/UserData/Previews", name: "Xcode · \(t("mac.tg.anteprime_swiftui"))"),
        Target(path: "Library/Developer/XCPGDevices", name: "Xcode · \(t("mac.tg.dispositivi_dei_playground"))"),
        Target(path: "Library/Developer/Xcode/Products", name: "Xcode · \(t("mac.tg.prodotti_delle_build"))"),
        Target(path: "miniconda3/pkgs", name: "Conda · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: "anaconda3/pkgs", name: "Anaconda · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: "miniforge3/pkgs", name: "Miniforge · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: "mambaforge/pkgs", name: "Mamba · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: "opt/miniconda3/pkgs", name: "Conda · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: "opt/anaconda3/pkgs", name: "Anaconda · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: ".conda/pkgs", name: "Conda · \(t("mac.tg.pacchetti_scaricati"))"),
        Target(path: ".pyenv/cache", name: "pyenv · \(t("mac.tg.download"))"),
        Target(path: ".gem/specs", name: "RubyGems · \(t("mac.tg.cache"))"),
        Target(path: ".cache/pip", name: "Python pip · \(t("mac.tg.cache"))"),
        Target(path: ".vagrant.d/boxes", name: "Vagrant · box", risk: .review, recommended: false),
        Target(path: ".minikube/cache", name: "Minikube · \(t("mac.tg.cache"))"),
        Target(path: ".colima", name: "Colima · VM", risk: .careful, recommended: false),
        Target(path: ".orbstack", name: "OrbStack · \(t("mac.tg.dati"))", risk: .careful, recommended: false)
    ] }
}

enum Scanners {
    static func scan(_ c: CleanCategory, index: HomeIndex?, reporter: Reporter) -> [CleanItem] {
        switch c {
        case .diskMap: return diskMap(reporter)
        case .appData: return appData(reporter)
        case .caches: return caches(reporter)
        case .logsTemp: return logsTemp(reporter)
        case .systemAreas: return SystemAreas.scan(reporter)
        case .aiTools: return fixed(Targets.ai, reporter)
        case .devCaches: return fixed(Targets.dev, reporter) + homebrewOld(reporter)
        case .buildDeps: return buildDeps(index, reporter)
        case .gitRepos: return gitRepos(index, reporter)
        case .duplicates: return Duplicates.find(index, reporter)
        case .bigFiles: return bigFiles(index, reporter)
        case .squeeze: return Squeeze.candidates(index, reporter)
        case .installers: return installers(index, reporter)
        case .oldDownloads: return oldDownloads(reporter)
        case .apps: return apps(reporter)
        case .leftovers: return leftovers(reporter)
        case .appleExtras: return appleExtras(reporter)
        }
    }

    // MARK: helpers

    static func makeItem(_ url: URL, name: String, detail: String? = nil, risk: Risk, recommended: Bool,
                         rep: Reporter, minSize: Int64 = 512 * 1024, badges: [String] = [], date: Date? = nil) -> CleanItem? {
        guard FS.exists(url) else { return nil }
        rep.report(FS.pretty(url))
        let size = FS.allocatedSize(url, reporter: rep)
        guard size >= minSize else { return nil }
        return CleanItem(url: url, name: name, detail: detail ?? FS.pretty(url), size: size,
                         date: date ?? FS.modDate(url), risk: risk, recommended: recommended, badges: badges)
    }

    static func prettyChild(_ s: String) -> String {
        // Claude Code encodes project paths as "-Users-name-dev-project"
        if s.hasPrefix("-") {
            let parts = s.split(separator: "-").map(String.init).filter { !$0.isEmpty }
            return parts.suffix(2).joined(separator: "/")
        }
        return s
    }

    static func fixed(_ list: [Target], _ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for (i, tg) in list.enumerated() {
            if rep.isCancelled { break }
            rep.report(tg.name, progress: Double(i) / Double(max(list.count, 1)))
            let url = FS.home.appendingPathComponent(tg.path)
            guard FS.exists(url) else { continue }
            if tg.perChild {
                for child in FS.children(url) {
                    if rep.isCancelled { break }
                    let d = FS.newestModDate(child)
                    var rec = tg.recommended
                    var badges: [String] = []
                    if let days = tg.olderThanDays {
                        rec = FS.daysSince(d) > days
                        badges = rec ? [t("mac.badge.oldf")] : [t("mac.badge.recentf")]
                    }
                    if let it = makeItem(child, name: "\(tg.name) · \(prettyChild(child.lastPathComponent))",
                                         detail: t("mac.detail.lastmod", FS.pretty(child), Fmt.relative(d)),
                                         risk: tg.risk, recommended: rec, rep: rep, minSize: 100 * 1024, badges: badges, date: d) {
                        out.append(it)
                    }
                }
            } else if let it = makeItem(url, name: tg.name, risk: tg.risk, recommended: tg.recommended, rep: rep) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: Homebrew

    /// Old formula versions `brew cleanup` would remove.
    static func homebrewOld(_ rep: Reporter) -> [CleanItem] {
        guard let brew = ["/usr/local/bin/brew", "/opt/homebrew/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return [] }
        rep.report("brew cleanup --dry-run…", force: true)
        let r = Shell.run(brew, ["cleanup", "-n"], env: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
        var out: [CleanItem] = []
        for line in r.output.split(separator: "\n") where line.hasPrefix("Would remove: ") {
            var path = String(line.dropFirst("Would remove: ".count))
            if let paren = path.range(of: " (", options: .backwards) { path = String(path[..<paren.lowerBound]) }
            let url = URL(fileURLWithPath: path)
            guard FS.exists(url), !url.path.contains("/Caches/") else { continue }
            let parent = url.deletingLastPathComponent().lastPathComponent
            if let it = makeItem(url, name: t("mac.item.brewold", parent, url.lastPathComponent), risk: .safe, recommended: true, rep: rep, minSize: 1_048_576, badges: ["🍺 brew cleanup"]) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: disk map

    /// Every folder >= 300 MB down to 4 levels below Home, plus Applications. View-only.
    static func diskMap(_ rep: Reporter) -> [CleanItem] {
        let fm = FileManager.default
        let home = FS.home
        let homeDepth = home.pathComponents.count
        var sizes: [String: Int64] = [:]
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let keySet = Set(keys)
        var n = 0
        if let en = fm.enumerator(at: home, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            while let obj = en.nextObject() {
                guard let url = obj as? URL else { continue }
                n += 1
                if n % 500 == 0 {
                    if rep.isCancelled { return [] }
                    rep.report(t("mac.busy.measured", n, FS.pretty(url)))
                }
                guard let v = try? url.resourceValues(forKeys: keySet), v.isRegularFile == true else { continue }
                let sz = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if sz == 0 { continue }
                total += sz
                let comps = url.pathComponents
                var path = home.path
                let maxDepth = min(comps.count - 1, homeDepth + 4)
                if homeDepth < maxDepth {
                    for i in homeDepth..<maxDepth {
                        path += "/" + comps[i]
                        sizes[path, default: 0] += sz
                    }
                }
            }
        }
        var out: [CleanItem] = []
        out.append(CleanItem(url: home, name: t("mac.item.home"), detail: "~", size: total, date: nil,
                             risk: .careful, recommended: false, badges: [t("mac.badge.burrow")]))
        for (path, size) in sizes {
            let depth = URL(fileURLWithPath: path).pathComponents.count - homeDepth
            let threshold: Int64 = depth == 1 ? 50 * 1_048_576 : 300 * 1_048_576
            guard size >= threshold else { continue }
            let url = URL(fileURLWithPath: path)
            out.append(CleanItem(url: url, name: url.lastPathComponent, detail: FS.pretty(url), size: size, date: nil,
                                 risk: .careful, recommended: false))
        }
        rep.report(t("mac.busy.measureapps"), progress: 0.95, force: true)
        let apps = URL(fileURLWithPath: "/Applications")
        var appsTotal: Int64 = 0
        var appItems: [CleanItem] = []
        for a in FS.children(apps) {
            if rep.isCancelled { break }
            let s = FS.allocatedSize(a, reporter: rep)
            appsTotal += s
            if s >= 300 * 1_048_576 {
                appItems.append(CleanItem(url: a, name: a.deletingPathExtension().lastPathComponent, detail: a.path, size: s, date: nil, risk: .careful, recommended: false))
            }
        }
        out.append(CleanItem(url: apps, name: t("mac.item.applications"), detail: "/Applications", size: appsTotal, date: nil, risk: .careful, recommended: false, badges: [t("mac.badge.apps")]))
        out += appItems
        return out
    }

    /// Whole data volume, every user included. Needs the admin password once (runs `du` as root).
    static func diskMapFull(_ rep: Reporter) -> Result<([CleanItem], [String]), Error> {
        let root = "/System/Volumes/Data"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("suriclean-du-\(Int(Date().timeIntervalSince1970)).txt")
        let err = out.appendingPathExtension("err")
        let cmd = "/usr/bin/du -x -k -d 4 '\(root)' > '\(out.path)' 2> '\(err.path)'; /bin/chmod 644 '\(out.path)' '\(err.path)'"
        rep.report(t("mac.busy.measurefull"), force: true)
        let r = Admin.run([cmd], prompt: t("mac.prompt.measurefull"))
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: err) }
        guard let text = try? String(contentsOf: out, encoding: .utf8), !text.isEmpty else {
            let why = r.cancelled ? t("mac.err.pwcancel") : t("mac.err.measurefail")
            return .failure(NSError(domain: "SuriClean", code: 2, userInfo: [NSLocalizedDescriptionKey: why]))
        }
        return .success((parseDu(text), parseDuErrors((try? String(contentsOf: err, encoding: .utf8)) ?? "")))
    }

    /// Folders `du` could not read (macOS privacy protection), as shown paths, most relevant first.
    static func parseDuErrors(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(separator: "\n") where line.contains("not permitted") || line.contains("Permission denied") {
            var p = String(line)
            if p.hasPrefix("du: ") { p = String(p.dropFirst(4)) }
            if let r = p.range(of: ": ", options: .backwards) { p = String(p[..<r.lowerBound]) }
            p = p.replacingOccurrences(of: "/System/Volumes/Data", with: "")
            if p.isEmpty { p = "/" }
            if seen.insert(p).inserted { out.append(p) }
        }
        return out.sorted { $0.split(separator: "/").count < $1.split(separator: "/").count }
    }

    /// Turns `du -k -d 4 /System/Volumes/Data` output into disk-map rows.
    static func parseDu(_ text: String) -> [CleanItem] {
        let root = "/System/Volumes/Data"
        let base = URL(fileURLWithPath: root).pathComponents.count
        let me = FS.home.path
        var items: [CleanItem] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kb = Int64(parts[0]) else { continue }
            let path = String(parts[1])
            let url = URL(fileURLWithPath: path)
            let depth = url.pathComponents.count - base
            let size = kb * 1024
            let shown = path == root ? "/" : String(path.dropFirst(root.count))
            var badges: [String] = []
            if depth == 2 && shown.hasPrefix("/Users/") {
                badges.append(("/System/Volumes/Data" + shown) == "/System/Volumes/Data" + me || shown == me ? t("mac.badge.you") : t("mac.badge.otheruser"))
            }
            if shown.hasPrefix("/private/var/vm") { badges.append(t("mac.badge.vm")) }
            if shown.hasPrefix("/Library") || shown.hasPrefix("/private") || shown.hasPrefix("/usr") || shown.hasPrefix("/opt") { badges.append(t("mac.badge.system")) }
            if depth == 0 {
                items.append(CleanItem(url: url, name: t("mac.item.wholedisk"), detail: "/", size: size, date: nil,
                                       risk: .careful, recommended: false, badges: [t("mac.badge.all")]))
                continue
            }
            let threshold: Int64 = depth == 1 ? 100 * 1_048_576 : 300 * 1_048_576
            guard size >= threshold else { continue }
            items.append(CleanItem(url: url, name: url.lastPathComponent, detail: shown, size: size, date: nil,
                                   risk: .careful, recommended: false, badges: badges))
        }
        return items
    }

    // MARK: app data

    static func appData(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let L = FS.library
        let skipSupport: Set<String> = ["MobileSync", "Claude", "Cursor", "Code", "Windsurf", "CrashReporter", "AddressBook", "CallHistoryDB", "Knowledge", "com.apple.TCC"]
        var candidates: [(URL, String)] = []
        for d in FS.children(L.appendingPathComponent("Application Support")) where FS.isDir(d) && !skipSupport.contains(d.lastPathComponent) {
            candidates.append((d, FS.friendlyName(d.lastPathComponent)))
        }
        for c in FS.children(L.appendingPathComponent("Containers")) where !c.lastPathComponent.hasPrefix("com.apple.") || c.lastPathComponent == "com.apple.mail" {
            candidates.append((c.appendingPathComponent("Data"), FS.friendlyName(c.lastPathComponent) + " " + t("mac.suffix.sandbox")))
        }
        for g in FS.children(L.appendingPathComponent("Group Containers")) {
            let name = g.lastPathComponent
            var label = name
            if name.lowercased().contains("whatsapp") { label = "WhatsApp" }
            else if name.lowercased().contains("telegram") { label = "Telegram" }
            else if name.contains("com.apple.podcasts") || name.contains("UBF8T346G9.Office") || name.lowercased().contains("office") { label = name.contains("podcasts") ? "Podcast" : "Microsoft Office" }
            candidates.append((g, label + " " + t("mac.suffix.group")))
        }
        candidates.append((L.appendingPathComponent("Mail"), t("mac.item.mail")))
        candidates.append((FS.home.appendingPathComponent("Library/Messages"), t("mac.item.messages")))
        for (i, c) in candidates.enumerated() {
            if rep.isCancelled { break }
            rep.report(FS.pretty(c.0), progress: Double(i) / Double(max(candidates.count, 1)))
            if let it = makeItem(c.0, name: c.1, risk: .careful, recommended: false, rep: rep, minSize: 500 * 1_048_576, badges: [t("mac.badge.greedy")]) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: caches

    static let cacheSkip: Set<String> = [
        FS.ownBundleID, "claude-cli-nodejs", "com.anthropic.claudefordesktop", "com.anthropic.claudefordesktop.ShipIt",
        "com.openai.chat", "com.todesktop.230313mzl4w4u92", "com.todesktop.230313mzl4w4u92.ShipIt"
    ]
    static let electronSkip: Set<String> = ["Claude", "Cursor", "Code", "Code - Insiders", "Windsurf"]
    static let electronSubs = ["Cache", "Code Cache", "GPUCache", "CachedData", "DawnCache", "DawnGraphiteCache",
                               "Service Worker/CacheStorage", "Crashpad/completed", "ShaderCache", "GrShaderCache"]

    static func caches(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let kids = FS.children(FS.library.appendingPathComponent("Caches"))
        for (i, k) in kids.enumerated() {
            if rep.isCancelled { return out }
            if cacheSkip.contains(k.lastPathComponent) { continue }
            rep.report(FS.pretty(k), progress: Double(i) / Double(max(kids.count, 1)) * 0.6)
            if let it = makeItem(k, name: FS.friendlyName(k.lastPathComponent), risk: .safe, recommended: true, rep: rep, minSize: 1_048_576) {
                out.append(it)
            }
        }
        // Electron / Chromium caches in Application Support
        let support = FS.library.appendingPathComponent("Application Support")
        for app in FS.children(support) where FS.isDir(app) && !electronSkip.contains(app.lastPathComponent) {
            if rep.isCancelled { return out }
            for s in electronSubs {
                let u = app.appendingPathComponent(s)
                if let it = makeItem(u, name: "\(app.lastPathComponent) · \(s)", risk: .safe, recommended: true, rep: rep, minSize: 1_048_576) {
                    out.append(it)
                }
            }
        }
        rep.report(t("mac.busy.browsers"), progress: 0.75)
        for browser in ["Google/Chrome", "BraveSoftware/Brave-Browser", "Microsoft Edge", "Vivaldi", "Arc/User Data"] {
            let base = support.appendingPathComponent(browser)
            for profile in FS.children(base) where FS.isDir(profile) {
                for s in ["Service Worker/CacheStorage", "Code Cache", "GPUCache"] {
                    let u = profile.appendingPathComponent(s)
                    if let it = makeItem(u, name: "\(browser.split(separator: "/").last ?? "") (\(profile.lastPathComponent)) · \(s)",
                                         risk: .safe, recommended: true, rep: rep, minSize: 1_048_576) {
                        out.append(it)
                    }
                }
            }
        }
        // Caches inside sandboxed app containers
        rep.report(t("mac.busy.containers"), progress: 0.85)
        for c in FS.children(FS.library.appendingPathComponent("Containers")) {
            if rep.isCancelled { return out }
            let u = c.appendingPathComponent("Data/Library/Caches")
            if let it = makeItem(u, name: t("mac.item.sandboxcache", FS.friendlyName(c.lastPathComponent)), risk: .safe,
                                 recommended: true, rep: rep, minSize: 5 * 1_048_576) {
                out.append(it)
            }
        }
        return out
    }

    static func logsTemp(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let logs = FS.library.appendingPathComponent("Logs")
        for k in FS.children(logs) where k.lastPathComponent != "Claude" {
            if rep.isCancelled { return out }
            if let it = makeItem(k, name: t("mac.item.log", FS.friendlyName(k.lastPathComponent)), risk: .safe, recommended: true, rep: rep, minSize: 256 * 1024) {
                out.append(it)
            }
        }
        if let it = makeItem(FS.library.appendingPathComponent("Saved Application State"), name: t("mac.item.savedstate"),
                             risk: .safe, recommended: true, rep: rep) { out.append(it) }
        if let it = makeItem(FS.library.appendingPathComponent("Application Support/CrashReporter"), name: t("mac.item.crashreports"),
                             risk: .safe, recommended: true, rep: rep) { out.append(it) }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        for k in (FS.isHelper ? [] : FS.children(tmp)) {
            if rep.isCancelled { return out }
            let d = FS.newestModDate(k)
            guard FS.daysSince(d) >= 3 else { continue }
            if let it = makeItem(k, name: t("mac.item.temp", k.lastPathComponent), detail: t("mac.detail.temp", Fmt.relative(d)),
                                 risk: .safe, recommended: true, rep: rep, minSize: 256 * 1024) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: index-based

    static func projectActivity(_ project: URL, excluding: String) -> Date? {
        var best = FS.newestModDate(project, excluding: [excluding, ".git", ".DS_Store"])
        if let d = FS.modDate(project.appendingPathComponent(".git/index")), d > (best ?? .distantPast) { best = d }
        return best
    }

    static func buildDeps(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index else { return [] }
        var out: [CleanItem] = []
        for (i, d) in index.deps.enumerated() {
            if rep.isCancelled { break }
            rep.report(FS.pretty(d.url), progress: Double(i) / Double(max(index.deps.count, 1)))
            let project = d.url.deletingLastPathComponent()
            let active = projectActivity(project, excluding: d.url.lastPathComponent)
            let days = FS.daysSince(active)
            let old = days > 60
            if let it = makeItem(d.url, name: "\(project.lastPathComponent) · \(d.url.lastPathComponent)",
                                 detail: t("mac.detail.dep", d.kind, FS.pretty(project), Fmt.relative(active)),
                                 risk: .safe, recommended: old, rep: rep, minSize: 1_048_576,
                                 badges: [old ? t("mac.badge.projidle") : t("mac.badge.projactive")], date: active) {
                out.append(it)
            }
        }
        return out
    }

    static func gitRepos(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index, GitInspector.available else { return [] }
        var out: [CleanItem] = []
        for (i, repo) in index.repos.enumerated() {
            if rep.isCancelled { break }
            rep.report("git status · \(FS.pretty(repo))", progress: Double(i) / Double(max(index.repos.count, 1)))
            if let it = repoItem(repo, rep: rep) { out.append(it) }
        }
        return out
    }

    /// One row for a repository (also used to refresh it after a branch/stash clean-up).
    static func repoItem(_ repo: URL, rep: Reporter?) -> CleanItem? {
        let info = GitInspector.inspect(repo)
        let size = FS.allocatedSize(repo, reporter: rep)
        guard size >= 1_048_576 else { return nil }
        let days = FS.daysSince(info.lastActivity)
        var badges: [String] = []
        if info.safe { badges.append(t("mac.badge.gitsafe")) }
        if info.remote == nil { badges.append(t("mac.badge.gitlocal")) }
        if info.dirty { badges.append(t("mac.badge.gitdirty")) }
        if info.unpushed > 0 { badges.append(t("mac.badge.gitunpushed", info.unpushed)) }
        if info.stashed { badges.append(t("mac.badge.gitstash")) }
        if days > 365 { badges.append(t("mac.badge.idleyear")) }
        let risk: Risk = info.safe ? .safe : (info.remote != nil ? .review : .careful)
        var detail = t("mac.detail.repo", FS.pretty(repo), Fmt.relative(info.lastActivity))
        if let r = info.remote { detail += " · \(GitInspector.shortRemote(r))" }
        var it = CleanItem(url: repo, name: repo.lastPathComponent, detail: detail, size: size,
                           date: info.lastActivity, risk: risk, recommended: info.safe && days > 180,
                           badges: badges,
                           copyText: info.remote.map { "git clone \($0) \"\(repo.path)\"" })
        it.isGitRepo = true
        return it
    }

    static func badge(forExt ext: String) -> String? {
        switch ext {
        case "mov", "mp4", "mkv", "avi", "m4v", "webm": return t("mac.badge.video")
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz": return t("mac.badge.archive")
        case "dmg", "iso", "img", "sparseimage": return t("mac.badge.diskimage")
        case "vmdk", "vdi", "qcow2", "utm", "pvm", "vmwarevm", "hdd": return t("mac.badge.vmimage")
        case "psd", "ai", "sketch", "fig": return t("mac.badge.graphics")
        case "wav", "aif", "aiff", "flac": return t("mac.badge.audio")
        case "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "aplibrary": return t("mac.badge.library")
        default: return nil
        }
    }

    static func bigFiles(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index else { return [] }
        var out: [CleanItem] = []
        let big = index.files.filter { $0.size >= 100 * 1_048_576 }.sorted { $0.size > $1.size }.prefix(250)
        for f in big {
            let ext = f.url.pathExtension.lowercased()
            out.append(CleanItem(url: f.url, name: f.url.lastPathComponent,
                                 detail: t("mac.detail.modified", FS.pretty(f.url.deletingLastPathComponent()), Fmt.relative(f.modified)),
                                 size: f.size, date: f.modified, risk: .careful, recommended: false,
                                 badges: badge(forExt: ext).map { [$0] } ?? []))
        }
        for (i, p) in index.packages.enumerated() {
            if rep.isCancelled { break }
            rep.report(FS.pretty(p), progress: Double(i) / Double(max(index.packages.count, 1)))
            if let it = makeItem(p, name: p.lastPathComponent, detail: FS.pretty(p.deletingLastPathComponent()),
                                 risk: .careful, recommended: false, rep: rep, minSize: 200 * 1_048_576,
                                 badges: [badge(forExt: p.pathExtension.lowercased()) ?? t("mac.badge.package")]) {
                out.append(it)
            }
        }
        return out
    }

    static func installers(_ index: HomeIndex?, _ rep: Reporter) -> [CleanItem] {
        guard let index = index else { return [] }
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
        let dl = FS.home.appendingPathComponent("Downloads").path + "/"
        let desk = FS.home.appendingPathComponent("Desktop").path + "/"
        var out: [CleanItem] = []
        for f in index.files where exts.contains(f.url.pathExtension.lowercased()) {
            let ext = f.url.pathExtension.lowercased()
            let inDownloads = f.url.path.hasPrefix(dl)
            let inDesktop = f.url.path.hasPrefix(desk)
            // Disk images can be personal (encrypted) storage: only suggest old ones sitting in Downloads.
            let isImage = ext == "dmg" || ext == "iso"
            let rec = isImage ? (inDownloads && FS.daysSince(f.modified) > 30) : (inDownloads || inDesktop)
            out.append(CleanItem(url: f.url, name: f.url.lastPathComponent,
                                 detail: "\(FS.pretty(f.url.deletingLastPathComponent())) · \(Fmt.relative(f.modified))",
                                 size: f.size, date: f.modified, risk: rec ? .safe : .review,
                                 recommended: rec, badges: [isImage ? t("mac.badge.diskimage") : t("mac.badge.installer")]))
        }
        for app in index.downloadApps {
            if let it = makeItem(app, name: app.lastPathComponent, detail: t("mac.detail.appindl"),
                                 risk: .review, recommended: false, rep: rep, badges: [t("mac.badge.appindl")]) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: downloads

    static func oldDownloads(_ rep: Reporter) -> [CleanItem] {
        let dl = FS.home.appendingPathComponent("Downloads")
        let kids = FS.children(dl).filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
        var out: [CleanItem] = []
        for (i, k) in kids.enumerated() {
            if rep.isCancelled { break }
            rep.report(FS.pretty(k), progress: Double(i) / Double(max(kids.count, 1)))
            let v = try? k.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
            let d = v?.addedToDirectoryDate ?? v?.contentModificationDate
            let days = FS.daysSince(d)
            guard days >= 90 else { continue }
            if let it = makeItem(k, name: k.lastPathComponent, detail: t("mac.detail.downloaded", Fmt.relative(d)), risk: .review,
                                 recommended: false, rep: rep, minSize: 100 * 1024,
                                 badges: days > 365 ? [t("mac.badge.overyear")] : [], date: d) {
                out.append(it)
            }
        }
        return out
    }

    // MARK: apps

    static func apps(_ rep: Reporter) -> [CleanItem] {
        var appURLs: [URL] = []
        for dir in [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")] {
            for c in FS.children(dir) {
                if c.pathExtension == "app" { appURLs.append(c) }
                else if FS.isDir(c) {
                    for cc in FS.children(c) where cc.pathExtension == "app" { appURLs.append(cc) }
                }
            }
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var out: [CleanItem] = []
        for (i, app) in appURLs.enumerated() {
            if rep.isCancelled { break }
            rep.report(app.lastPathComponent, progress: Double(i) / Double(max(appURLs.count, 1)))
            let bundle = Bundle(url: app)
            let id = bundle?.bundleIdentifier ?? ""
            let isInstaller = id.hasPrefix("com.apple.InstallAssistant") || app.lastPathComponent.hasPrefix("Install macOS") || app.lastPathComponent.hasPrefix("Installa macOS")
            if (id.hasPrefix("com.apple.") && !isInstaller) || id == FS.ownBundleID { continue }
            let name = app.deletingPathExtension().lastPathComponent
            let last = FS.lastUsedDate(app)
            let size = FS.allocatedSize(app, reporter: rep)
            let extras = FS.leftovers(bundleID: id, name: name)
            let extraSize = extras.reduce(Int64(0)) { $0 + FS.allocatedSize($1) }
            let days = FS.daysSince(last)
            var badges: [String] = []
            if running.contains(id) { badges.append(t("mac.badge.running")) }
            if last == nil { badges.append(t("mac.badge.neveropened")) }
            else if days > 365 { badges.append(t("mac.badge.sleepyear")) }
            else if days > 90 { badges.append(t("mac.badge.sleepmonths")) }
            if extraSize > 0 { badges.append(t("mac.badge.extradata", Fmt.bytes(extraSize))) }
            let version = (bundle?.infoDictionary?["CFBundleShortVersionString"] as? String).map { " · v\($0)" } ?? ""
            let detail = (last.map { t("mac.detail.lastused", Fmt.relative($0)) } ?? t("mac.detail.nouse")) + version
            if isInstaller {
                out.append(CleanItem(url: app, name: name, detail: t("mac.detail.macosinstaller"), size: size, date: last,
                                     risk: .safe, recommended: true, badges: [t("mac.badge.macosinstaller")]))
                continue
            }
            out.append(CleanItem(url: app, name: name, detail: detail, size: size + extraSize, date: last,
                                 risk: .careful, recommended: false, badges: badges, extraURLs: extras))
        }
        return out
    }

    static let tlds: Set<String> = ["com", "org", "net", "io", "de", "it", "co", "app", "dev", "me", "us", "uk",
                                     "fr", "ru", "jp", "ch", "at", "nl", "se", "info", "tv", "cc", "ai", "es", "ca", "eu"]

    static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, let first = parts.first, tlds.contains(first.lowercased()) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    static func appInstalled(_ id: String) -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
        var parts = id.split(separator: ".").map(String.init)
        while parts.count > 3 {
            parts.removeLast()
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) != nil { return true }
        }
        return false
    }

    static func leftovers(_ rep: Reporter) -> [CleanItem] {
        let dirs = ["Containers", "Caches", "Application Support", "Saved Application State", "HTTPStorages", "WebKit", "Preferences", "Application Scripts"]
        var byID: [String: [URL]] = [:]
        for d in dirs {
            for c in FS.children(FS.library.appendingPathComponent(d)) {
                var n = c.lastPathComponent
                for suf in [".savedState", ".plist", ".binarycookies", ".ShipIt"] where n.hasSuffix(suf) {
                    n = String(n.dropLast(suf.count))
                }
                guard looksLikeBundleID(n), !n.hasPrefix("com.apple."), n != FS.ownBundleID else { continue }
                byID[n, default: []].append(c)
            }
        }
        var out: [CleanItem] = []
        let ids = byID.keys.sorted()
        for (i, id) in ids.enumerated() {
            if rep.isCancelled { break }
            rep.report(id, progress: Double(i) / Double(max(ids.count, 1)))
            guard let urls = byID[id], !appInstalled(id) else { continue }
            let size = urls.reduce(Int64(0)) { $0 + FS.allocatedSize($1) }
            guard size >= 200 * 1024 else { continue }
            let onlyCaches = urls.allSatisfy { $0.path.contains("/Library/Caches/") }
            let name = String(id.split(separator: ".").last ?? Substring(id))
            out.append(CleanItem(url: urls[0], name: name.capitalized,
                                 detail: "\(id) · " + tp("mac.detail.folders", urls.count, urls.count),
                                 size: size, date: urls.compactMap { FS.modDate($0) }.max(),
                                 risk: onlyCaches ? .safe : .review, recommended: onlyCaches,
                                 badges: [t("mac.badge.appnotfound")], extraURLs: Array(urls.dropFirst())))
        }
        return out
    }

    // MARK: apple extras

    static func appleExtras(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let backups = FS.library.appendingPathComponent("Application Support/MobileSync/Backup")
        for b in FS.children(backups) where FS.isDir(b) {
            if rep.isCancelled { return out }
            let info = NSDictionary(contentsOf: b.appendingPathComponent("Info.plist"))
            let device = info?["Device Name"] as? String ?? t("mac.word.device")
            let date = info?["Last Backup Date"] as? Date ?? FS.modDate(b)
            if let it = makeItem(b, name: t("mac.item.backup", device), detail: t("mac.detail.lastbackup", Fmt.relative(date)),
                                 risk: .careful, recommended: false, rep: rep, badges: [t("mac.badge.localbackup")], date: date) {
                out.append(it)
            }
        }
        let simple: [(String, String, Risk, Bool)] = [
            ("Library/iTunes/iPhone Software Updates", t("mac.item.iosupd"), .safe, true),
            ("Library/iTunes/iPad Software Updates", t("mac.item.ipadupd"), .safe, true),
            ("Library/iTunes/iPod Software Updates", t("mac.item.ipodupd"), .safe, true),
            ("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", t("mac.item.mailatt"), .safe, true),
            ("Music/iTunes/iTunes Media/Mobile Applications", t("mac.item.ipa"), .safe, true),
            ("Library/Messages/Attachments", t("mac.item.msgatt"), .careful, false),
            ("Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache", t("mac.item.podcasts"), .review, false)
        ]
        for (i, s) in simple.enumerated() {
            if rep.isCancelled { return out }
            rep.report(s.1, progress: Double(i) / Double(simple.count))
            if let it = makeItem(FS.home.appendingPathComponent(s.0), name: s.1, risk: s.2, recommended: s.3, rep: rep) {
                out.append(it)
            }
        }
        return out
    }
}
