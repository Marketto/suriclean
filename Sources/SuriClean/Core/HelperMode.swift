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
            lines.append("\(q(exe)) --scan-user \(q(h.path)) --categories \(cats) --out \(q(out.path)) >/dev/null 2>&1")
        }
        let script = work.appendingPathComponent("full.sh")
        guard (try? lines.joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)) != nil else {
            r.error = "Non riesco a preparare la scansione"
            return r
        }
        rep.report(homes.isEmpty ? "Misuro tutto il disco… 🔐" : "Misuro tutto il disco e le cartelle di \(homes.map { $0.lastPathComponent }.joined(separator: ", "))… 🔐", force: true)
        let cmd = "/bin/bash " + q(script.path)
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let o = Shell.run("/usr/bin/osascript", ["-e", "do shell script \"\(esc)\" with administrator privileges with prompt \"SuriClean vuole misurare tutto il disco e le cartelle di tutti gli utenti.\""], mergeStderr: true)
        if o.output.contains("-128") {
            r.error = "Hai annullato la richiesta della password"
            return r
        }
        if let text = try? String(contentsOf: duOut, encoding: .utf8), !text.isEmpty {
            r.map = Scanners.parseDu(text)
            r.denied = Scanners.parseDuErrors((try? String(contentsOf: duErr, encoding: .utf8)) ?? "")
        } else {
            r.error = "Non sono riuscita a misurare il disco"
        }
        for h in homes {
            let f = work.appendingPathComponent("user-\(h.lastPathComponent).json")
            guard let d = try? Data(contentsOf: f), let dict = try? JSONDecoder().decode([String: [CleanItem]].self, from: d) else { continue }
            for (k, v) in dict { if let c = CleanCategory(rawValue: k) { r.others[c, default: []] += v } }
        }
        return r
    }
}
