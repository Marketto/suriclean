import Foundation

/// SuriClean can run without UI, as administrator, to scan another user's home folder:
///   SuriClean --scan-user /Users/bob --categories caches,bigFiles --out /tmp/x.json
/// The app starts it (once for every user, under a single password prompt) and merges the JSON.
enum HelperMode {
    static let helperCategories: [CleanCategory] = [
        .caches, .logsTemp, .aiTools, .devCaches, .buildDeps, .gitRepos, .duplicates, .appData,
        .bigFiles, .installers, .oldDownloads, .leftovers, .appleExtras
    ]

    static func runIfRequested() {
        let a = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
            return a[i + 1]
        }
        guard let homePath = value("--scan-user"), let outPath = value("--out") else { return }
        if let lang = value("--lang") { L10n.shared.use(code: lang) }
        let home = URL(fileURLWithPath: homePath)
        FS.home = home
        FS.isHelper = true
        let cats = (value("--categories") ?? "").split(separator: ",").compactMap { CleanCategory(rawValue: String($0)) }
        let owner = home.lastPathComponent
        let rep = Reporter()
        var index: HomeIndex?
        var res: [String: [CleanItem]] = [:]
        for c in cats {
            if c.needsIndex && index == nil { index = HomeIndex.build(reporter: rep) }
            var items = Scanners.scan(c, index: index, reporter: rep)
            for k in items.indices {
                items[k].owner = owner
                items[k].recommended = false          // never preselect someone else's things
                items[k].badges.insert("👤 \(owner)", at: 0)
            }
            res[c.rawValue] = items
        }
        if let data = try? JSONEncoder().encode(res) {
            try? data.write(to: URL(fileURLWithPath: outPath))
            _ = Shell.run("/bin/chmod", ["644", outPath])
        }
        exit(0)
    }

    /// Other people's home folders on this Mac.
    static func otherHomes() -> [URL] {
        let me = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return FS.children(URL(fileURLWithPath: "/Users")).filter { u in
            let n = u.lastPathComponent
            return FS.isDir(u) && !n.hasPrefix(".") && n != "Shared" && n != "Guest" && n != "Deleted Users"
                && u.standardizedFileURL.path != me
        }
    }

    struct FullResult {
        var map: [CleanItem] = []
        var others: [CleanCategory: [CleanItem]] = [:]
        var denied: [String] = []
        var error: String?
    }

    /// ONE admin prompt: measures the whole disk and scans every other user's folder.
    static func fullScan(_ rep: Reporter) -> FullResult {
        var r = FullResult()
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("suriclean-full-\(Int(Date().timeIntervalSince1970))")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let duOut = work.appendingPathComponent("du.txt")
        let duErr = work.appendingPathComponent("du-err.txt")
        var lines = ["#!/bin/bash",
                     "/usr/bin/du -x -k -d 4 '/System/Volumes/Data' > \(q(duOut.path)) 2> \(q(duErr.path)); /bin/chmod 644 \(q(duOut.path)) \(q(duErr.path))"]
        let homes = otherHomes()
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let cats = helperCategories.map { $0.rawValue }.joined(separator: ",")
        for h in homes {
            let out = work.appendingPathComponent("user-\(h.lastPathComponent).json")
            lines.append("\(q(exe)) --scan-user \(q(h.path)) --categories \(cats) --lang \(q(L10n.shared.code)) --out \(q(out.path)) >/dev/null 2>&1")
        }
        rep.report(homes.isEmpty ? t("mac.busy.full") : t("mac.busy.fullusers", homes.map { $0.lastPathComponent }.joined(separator: ", ")), force: true)
        let o = Admin.run(Array(lines.dropFirst()), prompt: t("mac.prompt.fullscan"))
        if o.cancelled {
            r.error = t("mac.err.pwcancel")
            return r
        }
        if let text = try? String(contentsOf: duOut, encoding: .utf8), !text.isEmpty {
            r.map = Scanners.parseDu(text)
            r.denied = Scanners.parseDuErrors((try? String(contentsOf: duErr, encoding: .utf8)) ?? "")
        } else {
            r.error = t("mac.err.measurefail")
        }
        for h in homes {
            let f = work.appendingPathComponent("user-\(h.lastPathComponent).json")
            guard let d = try? Data(contentsOf: f), let dict = try? JSONDecoder().decode([String: [CleanItem]].self, from: d) else { continue }
            for (k, v) in dict { if let c = CleanCategory(rawValue: k) { r.others[c, default: []] += v } }
        }
        return r
    }
}
