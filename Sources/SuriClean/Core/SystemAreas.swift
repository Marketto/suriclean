import Foundation

/// Things outside the home folder that macOS (or the admin) leaves behind and that can go away.
/// Measured without a password; moving them to the Trash goes through the single admin prompt of `Cleaner.adminTrash`.
enum SystemAreas {
    private static let fm = FileManager.default

    static func scan(_ rep: Reporter) -> [CleanItem] {
        if FS.isHelper { return [] }
        var out: [CleanItem] = []
        let steps: [(String, () -> [CleanItem])] = [
            (t("mac.sys.step.logs"), { libraryLogs(rep) }),
            (t("mac.sys.step.rotated"), { rotatedLogs(rep) }),
            (t("mac.sys.step.caches"), { sharedCaches(rep) }),
            (t("mac.sys.step.temp"), { oldTemp(rep) }),
            (t("mac.sys.step.updates"), { updates(rep) }),
            (t("mac.sys.step.cores"), { coreDumps(rep) }),
            (t("mac.sys.step.redl"), { redownloadable(rep) }),
        ]
        for (i, s) in steps.enumerated() {
            if rep.isCancelled { break }
            rep.report(s.0, progress: Double(i) / Double(steps.count), force: true)
            out += s.1()
        }
        let pw = t("mac.badge.password")
        for k in out.indices where !out[k].badges.contains(pw) { out[k].badges.append(pw) }
        return out
    }

    private static func item(_ u: URL, _ name: String, _ detail: String? = nil, risk: Risk = .safe, rec: Bool = true,
                             min: Int64 = 256 * 1024, badges: [String] = [], _ rep: Reporter) -> CleanItem? {
        Scanners.makeItem(u, name: name, detail: detail, risk: risk, recommended: rec, rep: rep, minSize: min, badges: badges)
    }

    /// /Library/Logs: crash reports and logs of every user and of the system.
    static func libraryLogs(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for k in FS.children(URL(fileURLWithPath: "/Library/Logs")) {
            if rep.isCancelled { break }
            let n = k.lastPathComponent
            let name = n == "DiagnosticReports" ? t("mac.sys.crashall") : t("mac.sys.log", FS.friendlyName(n))
            if let it = item(k, name, "/Library/Logs/\(n)", badges: [t("mac.badge.log")], rep) { out.append(it) }
        }
        return out
    }

    /// Rotated and compressed logs in /private/var/log (the live ones are left alone).
    static func rotatedLogs(_ rep: Reporter) -> [CleanItem] {
        let root = URL(fileURLWithPath: "/private/var/log")
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                     options: [], errorHandler: { _, _ in true }) else { return [] }
        let rotated = try! NSRegularExpression(pattern: "\\.(gz|bz2|xz|zip|\\d+)$|\\.asl$")
        var files: [URL] = []
        var size: Int64 = 0
        var newest: Date?
        while let obj = en.nextObject() {
            guard let f = obj as? URL else { continue }
            if rep.isCancelled { break }
            let n = f.lastPathComponent
            guard rotated.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil else { continue }
            guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]), v.isRegularFile == true else { continue }
            guard FS.daysSince(v.contentModificationDate) >= 2 else { continue }
            files.append(f)
            size += FS.allocatedSize(f)
            if let d = v.contentModificationDate, d > (newest ?? .distantPast) { newest = d }
        }
        guard size >= 512 * 1024, let first = files.first else { return [] }
        var it = CleanItem(url: first, name: t("mac.sys.rotated", files.count),
                           detail: t("mac.sys.rotated.detail"), size: size, date: newest,
                           risk: .safe, recommended: true, badges: [t("mac.badge.log")])
        it.extraURLs = Array(files.dropFirst())
        return [it]
    }

    /// /Library/Caches: caches shared by every user. Apple's own are rebuilt too, but left to you.
    static func sharedCaches(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for k in FS.children(URL(fileURLWithPath: "/Library/Caches")) {
            if rep.isCancelled { break }
            let n = k.lastPathComponent
            let apple = n.hasPrefix("com.apple.")
            if let it = item(k, t("mac.sys.cache", FS.friendlyName(n)), "/Library/Caches/\(n)",
                             risk: apple ? .review : .safe, rec: !apple, min: 1_048_576,
                             badges: apple ? [t("mac.badge.applecache")] : [t("mac.badge.rebuilt")], rep) { out.append(it) }
        }
        return out
    }

    /// /private/var/tmp survives reboots: anything untouched for 3 days is forgotten.
    static func oldTemp(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for k in FS.children(URL(fileURLWithPath: "/private/var/tmp")) {
            if rep.isCancelled { break }
            let d = FS.newestModDate(k)
            guard FS.daysSince(d) >= 3 else { continue }
            if let it = item(k, t("mac.sys.temp", k.lastPathComponent), t("mac.sys.temp.detail", Fmt.relative(d)),
                             badges: [t("mac.badge.temp")], rep) { out.append(it) }
        }
        return out
    }

    /// Downloaded macOS updates and macOS installers.
    static func updates(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for k in FS.children(URL(fileURLWithPath: "/Library/Updates")) where k.pathExtension != "plist" {
            if let it = item(k, t("mac.sys.update", k.lastPathComponent), t("mac.sys.update.detail"),
                             min: 1_048_576, badges: [t("mac.badge.redl")], rep) { out.append(it) }
        }
        if let it = item(URL(fileURLWithPath: "/macOS Install Data"), t("mac.sys.installdata"), "/macOS Install Data",
                         min: 1_048_576, badges: [t("mac.badge.leftover")], rep) { out.append(it) }
        for k in FS.children(URL(fileURLWithPath: "/Applications")) {
            let n = k.lastPathComponent
            guard n.hasSuffix(".app"), n.hasPrefix("Install macOS") || n.hasPrefix("Install OS X") || n.hasPrefix("Installa macOS") else { continue }
            if let it = item(k, t("mac.sys.installer", k.deletingPathExtension().lastPathComponent),
                             t("mac.sys.installer.detail"),
                             risk: .review, rec: false, min: 1_048_576, badges: [t("mac.badge.redl")], rep) { out.append(it) }
        }
        return out
    }

    /// Memory dumps left by crashed programs.
    static func coreDumps(_ rep: Reporter) -> [CleanItem] {
        FS.children(URL(fileURLWithPath: "/cores")).compactMap {
            item($0, t("mac.sys.core", $0.lastPathComponent), t("mac.sys.core.detail"),
                 min: 1_048_576, badges: [t("mac.badge.crash")], rep)
        }
    }

    /// Big things Apple lets you download again.
    static func redownloadable(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let fixed: [(String, String, String)] = [
            ("/Library/Audio/Apple Loops", t("mac.sys.loops"), t("mac.sys.loops.detail")),
            ("/Library/Application Support/GarageBand", t("mac.sys.gb"), t("mac.sys.gb.detail")),
            ("/Library/Application Support/Logic", t("mac.sys.logic"), t("mac.sys.logic.detail")),
        ]
        for f in fixed {
            if let it = item(URL(fileURLWithPath: f.0), f.1, "\(f.0) · \(f.2)", risk: .review, rec: false, min: 10 * 1_048_576,
                             badges: [t("mac.badge.redl")], rep) { out.append(it) }
        }
        for dir in ["/Library/Developer/CoreSimulator/Profiles/Runtimes", "/Library/Developer/CoreSimulator/Images"] {
            for k in FS.children(URL(fileURLWithPath: dir)) where k.pathExtension != "plist" {
                if let it = item(k, t("mac.sys.sim", k.deletingPathExtension().lastPathComponent), t("mac.sys.sim.detail", dir),
                                 risk: .careful, rec: false, min: 10 * 1_048_576, badges: [t("mac.badge.redl")], rep) { out.append(it) }
            }
        }
        return out
    }
}
