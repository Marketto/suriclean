import Foundation

/// Things outside the home folder that macOS (or the admin) leaves behind and that can go away.
/// Measured without a password; moving them to the Trash goes through the single admin prompt of `Cleaner.adminTrash`.
enum SystemAreas {
    private static let fm = FileManager.default

    static func scan(_ rep: Reporter) -> [CleanItem] {
        if FS.isHelper { return [] }
        var out: [CleanItem] = []
        let steps: [(String, () -> [CleanItem])] = [
            ("Log di sistema", { libraryLogs(rep) }),
            ("Log archiviati di macOS", { rotatedLogs(rep) }),
            ("Cache comuni", { sharedCaches(rep) }),
            ("Temporanei di sistema", { oldTemp(rep) }),
            ("Aggiornamenti e installer di macOS", { updates(rep) }),
            ("Core dump", { coreDumps(rep) }),
            ("Suoni e simulatori riscaricabili", { redownloadable(rep) }),
        ]
        for (i, s) in steps.enumerated() {
            if rep.isCancelled { break }
            rep.report(s.0, progress: Double(i) / Double(steps.count), force: true)
            out += s.1()
        }
        for k in out.indices where !out[k].badges.contains("🔐 password") { out[k].badges.append("🔐 password") }
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
            let name = n == "DiagnosticReports" ? "Report dei crash di tutto il Mac" : "Log di sistema · \(FS.friendlyName(n))"
            if let it = item(k, name, "/Library/Logs/\(n)", badges: ["📜 log"], rep) { out.append(it) }
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
        var it = CleanItem(url: first, name: "Log di macOS archiviati (\(files.count) file)",
                           detail: "/private/var/log · i vecchi log già compressi o ruotati", size: size, date: newest,
                           risk: .safe, recommended: true, badges: ["📜 log"])
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
            if let it = item(k, "Cache comune · \(FS.friendlyName(n))", "/Library/Caches/\(n)",
                             risk: apple ? .review : .safe, rec: !apple, min: 1_048_576,
                             badges: apple ? ["🍎 di macOS, si ricrea"] : ["🧽 si ricrea"], rep) { out.append(it) }
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
            if let it = item(k, "Temporaneo di sistema · \(k.lastPathComponent)", "/private/var/tmp · toccato \(Fmt.relative(d))",
                             badges: ["⏳ temporaneo"], rep) { out.append(it) }
        }
        return out
    }

    /// Downloaded macOS updates and macOS installers.
    static func updates(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        for k in FS.children(URL(fileURLWithPath: "/Library/Updates")) where k.pathExtension != "plist" {
            if let it = item(k, "Aggiornamento di macOS scaricato · \(k.lastPathComponent)", "/Library/Updates · si riscarica da Aggiornamento Software",
                             min: 1_048_576, badges: ["⬇️ riscaricabile"], rep) { out.append(it) }
        }
        if let it = item(URL(fileURLWithPath: "/macOS Install Data"), "Avanzi di un'installazione di macOS", "/macOS Install Data",
                         min: 1_048_576, badges: ["🧹 avanzo"], rep) { out.append(it) }
        for k in FS.children(URL(fileURLWithPath: "/Applications")) {
            let n = k.lastPathComponent
            guard n.hasSuffix(".app"), n.hasPrefix("Install macOS") || n.hasPrefix("Install OS X") || n.hasPrefix("Installa macOS") else { continue }
            if let it = item(k, "Installer · \(k.deletingPathExtension().lastPathComponent)",
                             "Si riscarica dall'App Store · serve solo per creare una chiavetta",
                             risk: .review, rec: false, min: 1_048_576, badges: ["⬇️ riscaricabile"], rep) { out.append(it) }
        }
        return out
    }

    /// Memory dumps left by crashed programs.
    static func coreDumps(_ rep: Reporter) -> [CleanItem] {
        FS.children(URL(fileURLWithPath: "/cores")).compactMap {
            item($0, "Core dump · \($0.lastPathComponent)", "/cores · fotografia della memoria di un programma andato in crash",
                 min: 1_048_576, badges: ["💥 crash"], rep)
        }
    }

    /// Big things Apple lets you download again.
    static func redownloadable(_ rep: Reporter) -> [CleanItem] {
        var out: [CleanItem] = []
        let fixed: [(String, String, String)] = [
            ("/Library/Audio/Apple Loops", "Loop di GarageBand e Logic", "Si riscaricano da GarageBand › Scarica suoni"),
            ("/Library/Application Support/GarageBand", "Strumenti di GarageBand", "Si riscaricano da GarageBand"),
            ("/Library/Application Support/Logic", "Contenuti di Logic Pro", "Si riscaricano da Logic Pro"),
        ]
        for f in fixed {
            if let it = item(URL(fileURLWithPath: f.0), f.1, "\(f.0) · \(f.2)", risk: .review, rec: false, min: 10 * 1_048_576,
                             badges: ["⬇️ riscaricabile"], rep) { out.append(it) }
        }
        for dir in ["/Library/Developer/CoreSimulator/Profiles/Runtimes", "/Library/Developer/CoreSimulator/Images"] {
            for k in FS.children(URL(fileURLWithPath: dir)) where k.pathExtension != "plist" {
                if let it = item(k, "Simulatore · \(k.deletingPathExtension().lastPathComponent)", "\(dir) · si riscarica da Xcode",
                                 risk: .careful, rec: false, min: 10 * 1_048_576, badges: ["⬇️ riscaricabile"], rep) { out.append(it) }
            }
        }
        return out
    }
}
