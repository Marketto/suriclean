import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var results: [CleanCategory: [CleanItem]] = [:]
    @Published var selection: Set<UUID> = []
    @Published var busy: BusyState?
    @Published var celebration: Celebration?
    @Published var disk = DiskInfo.current()
    @Published var selectedCategory: CleanCategory?
    @Published var hasFDA = true
    @Published var trashSize: Int64 = 0
    @Published var askEmptyTrash = false
    @Published var snapshotCount: Int?
    @Published var toast: String?
    @Published var muted: Bool = UserDefaults.standard.bool(forKey: "suri.muted") {
        didSet {
            UserDefaults.standard.set(muted, forKey: "suri.muted")
            Chiptune.shared.muted = muted
        }
    }
    @Published var totalFreed: Int64 = Int64(UserDefaults.standard.double(forKey: "suri.totalFreed")) {
        didSet { UserDefaults.standard.set(Double(totalFreed), forKey: "suri.totalFreed") }
    }

    enum UpdateState: Equatable {
        case idle, checking, downloading, ready, failed(String), upToDate
    }
    @Published var update: UpdateInfo?
    @Published var updateState: UpdateState = .idle
    @Published var autoUpdate: Bool = UserDefaults.standard.object(forKey: "suri.autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoUpdate, forKey: "suri.autoUpdate") }
    }
    private var stagedUpdate: URL?

    @Published var expandedRepos: Set<UUID> = []
    @Published var diskBreakdown: [DiskSlice] = []
    @Published var diskMapIsFull = false
    enum Scope { case me, all }
    @Published var scope: Scope = .all
    @Published var fullScanDone = false
    @Published var askScanScope = false
    @Published var gitDetails: [URL: GitDetails] = [:]
    @Published var gitWorking: Set<URL> = []

    private var homeIndex: HomeIndex?
    private var reporter: Reporter?
    private var started = false

    // MARK: lifecycle

    func start() {
        guard !started else { return }
        started = true
        Chiptune.shared.start()
        Chiptune.shared.muted = muted
        Chiptune.shared.mood = .menu
        refreshDisk()
        hasFDA = FS.hasFullDiskAccess()
        refreshTrash()
        refreshSnapshots()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            while true {
                await self.checkForUpdates(manual: false)
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in
                model.pruneMissing()
                model.refreshDisk()
            }
        }
    }

    func refreshDisk() { disk = DiskInfo.current() }

    // MARK: git repo details

    func toggleRepo(_ item: CleanItem) {
        Chiptune.shared.sfx(.blip)
        if expandedRepos.contains(item.id) { expandedRepos.remove(item.id); return }
        expandedRepos.insert(item.id)
        if gitDetails[item.url] == nil { reloadGit(item.url) }
    }

    func reloadGit(_ repo: URL) {
        gitWorking.insert(repo)
        Task {
            let d = await Task.detached(priority: .userInitiated) { GitTools.details(repo) }.value
            gitDetails[repo] = d
            gitWorking.remove(repo)
        }
    }

    enum GitAction { case deleteBranch(GitBranch), dropStash(GitStash), compact }

    func runGit(_ action: GitAction, on repo: URL) {
        gitWorking.insert(repo)
        Chiptune.shared.sfx(.whoosh)
        Task {
            let message: String
            switch action {
            case .deleteBranch(let b):
                let r = await Task.detached { GitTools.deleteBranch(repo, b) }.value
                message = (try? r.get()) ?? "Ehh… \((r.failureMessage))"
            case .dropStash(let s):
                let r = await Task.detached { GitTools.dropStash(repo, s) }.value
                message = (try? r.get()) ?? "Ehh… \((r.failureMessage))"
            case .compact:
                let r = await Task.detached { GitTools.compact(repo) }.value
                if let saved = try? r.get() {
                    totalFreed += saved
                    message = saved > 0 ? "Repo compattato! Risparmiati \(Fmt.bytes(saved)) ✨" : "Il repo era già bello compatto ☆"
                } else { message = "Ehh… \((r.failureMessage))" }
            }
            // refresh the row (badges, size, recommendation) and the details
            let updated = await Task.detached { Scanners.repoItem(repo, rep: nil) }.value
            if let idx = results[.gitRepos]?.firstIndex(where: { $0.url == repo }) {
                if var u = updated {
                    let old = results[.gitRepos]![idx]
                    u = CleanItem(url: u.url, name: u.name, detail: u.detail, size: u.size, date: u.date, risk: u.risk,
                                  recommended: u.recommended, badges: u.badges, copyText: u.copyText)
                    u.isGitRepo = true
                    let wasExpanded = expandedRepos.contains(old.id)
                    let wasSelected = selection.contains(old.id)
                    results[.gitRepos]![idx] = u
                    if wasExpanded { expandedRepos.remove(old.id); expandedRepos.insert(u.id) }
                    if wasSelected { selection.remove(old.id); selection.insert(u.id) }
                }
            }
            let d = await Task.detached { GitTools.details(repo) }.value
            gitDetails[repo] = d
            gitWorking.remove(repo)
            Chiptune.shared.sfx(message.hasPrefix("Ehh") ? .error : .coin)
            showToast(message)
        }
    }

    // MARK: updates

    func checkForUpdates(manual: Bool) async {
        if case .downloading = updateState { return }
        if updateState == .ready { return }
        updateState = .checking
        guard let info = await Updater.check() else {
            updateState = manual ? .upToDate : .idle
            if manual { showToast("Sei già all'ultima versione (\(Updater.currentVersion)) ✨") }
            return
        }
        update = info
        updateState = .idle
        if autoUpdate || manual { await downloadUpdate() }
    }

    func downloadUpdate() async {
        guard let info = update else { return }
        updateState = .downloading
        do {
            let staged = try await Task.detached(priority: .utility) { try await Updater.stage(info) }.value
            stagedUpdate = staged
            updateState = .ready
            Updater.pendingApply = { Updater.apply(staged: staged, relaunch: false) }
            Chiptune.shared.sfx(.coin)
            showToast("Kyaa~! SuriClean \(info.version) è pronta ✨ Si installa quando chiudi l'app")
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func installUpdateNow() {
        guard let staged = stagedUpdate else { return }
        Updater.pendingApply = nil
        Chiptune.shared.sfx(.whoosh)
        Updater.apply(staged: staged, relaunch: true)
        NSApp.terminate(nil)
    }

    func refreshTrash() {
        Task {
            let s = await Task.detached(priority: .utility) { FS.allocatedSize(FS.trashURL) }.value
            self.trashSize = s
        }
    }

    func refreshSnapshots() {
        Task {
            let n = await Task.detached(priority: .utility) { () -> Int in
                let r = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
                return r.output.components(separatedBy: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
            }.value
            self.snapshotCount = n
        }
    }

    func recheckFDA() {
        hasFDA = FS.hasFullDiskAccess()
        showToast(hasFDA ? "Yatta! Ora vedo tutte le stanze ✨" : "Ancora niente accesso completo: dopo averlo concesso riapri l'app")
    }

    func openFDASettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }

    func showToast(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.toast == s { self.toast = nil }
        }
    }

    // MARK: derived

    /// Items of a zone, filtered by the «Io / Tutti» switch after a whole-disk scan.
    func items(_ c: CleanCategory) -> [CleanItem] {
        let l = results[c] ?? []
        guard fullScanDone, scope == .me, c != .diskMap else { return l }
        return l.filter { $0.owner.isEmpty }
    }
    /// Size to show for a zone (the disk map's entries are nested, so use the biggest one).
    func displayTotal(_ c: CleanCategory) -> Int64 {
        let l = items(c)
        return c == .diskMap ? (l.map { $0.size }.max() ?? 0) : l.totalSize
    }
    func selectedItems(_ c: CleanCategory) -> [CleanItem] { items(c).filter { selection.contains($0.id) } }
    var foundTotal: Int64 {
        results.filter { $0.key != .diskMap }.values.reduce(Int64(0)) { $0 + $1.totalSize }
    }
    var recommendedTotal: Int64 {
        results.filter { $0.key != .diskMap }.values.reduce(Int64(0)) { acc, list in acc + list.filter { $0.recommended }.totalSize }
    }

    var greeting: String {
        let pct = Int(disk.usedFraction * 100)
        if results.isEmpty {
            if pct >= 90 {
                return "Kyaa~! Sono Suri-chan 🐾 Il tuo disco è pieno al \(pct)%… è un'emergenza kawaii!! Premi il bottone e lo faccio tornare pika-pika ✨"
            } else if pct >= 70 {
                return "Konnichiwa~! Sono Suri-chan 🐾 Il disco è al \(pct)%. Andiamo a caccia di spazio insieme? Ganbarō! ☆"
            }
            return "Yahoo~! Sono Suri-chan 🐾 Il disco sta benino (\(pct)%), ma un po' di brillantezza in più non guasta mai ✧"
        }
        return "Sugoi!! Ho scovato \(Fmt.bytes(foundTotal)) di roba ✨ e \(Fmt.bytes(recommendedTotal)) puoi buttarli senza pensieri! Tocca una zona e diamo un'occhiatina~ ♡"
    }

    var level: (title: String, emoji: String, progress: Double, next: String) {
        let gb = Double(totalFreed) / 1_000_000_000
        let steps: [(Double, String, String)] = [
            (1, "Cucciola curiosa", "🐣"), (5, "Scavatrice in erba", "🌱"),
            (20, "Sentinella del disco", "👀"), (50, "Regina delle dune", "👑")
        ]
        var prev = 0.0
        for s in steps {
            if gb < s.0 { return (s.1, s.2, (gb - prev) / (s.0 - prev), "prossimo livello a \(Int(s.0)) GB") }
            prev = s.0
        }
        return ("Leggenda del deserto", "🌟", 1, "livello MAX!! Sugoi~")
    }

    // MARK: selection

    func toggle(_ item: CleanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        Chiptune.shared.sfx(.pop)
    }

    func selectRecommended(_ c: CleanCategory) {
        let list = items(c)
        selection.subtract(list.map { $0.id })
        selection.formUnion(list.filter { $0.recommended }.map { $0.id })
        Chiptune.shared.sfx(.coin)
    }

    func setSelection(_ ids: [UUID], on: Bool) {
        if on { selection.formUnion(ids) } else { selection.subtract(ids) }
        Chiptune.shared.sfx(on ? .coin : .pop)
    }

    func selectAll(_ c: CleanCategory) { selection.formUnion(items(c).map { $0.id }); Chiptune.shared.sfx(.pop) }
    func selectNone(_ c: CleanCategory) { selection.subtract(items(c).map { $0.id }); Chiptune.shared.sfx(.pop) }

    // MARK: navigation & scanning

    func open(_ c: CleanCategory?) {
        Chiptune.shared.sfx(.pop)
        selectedCategory = c
        pruneMissing()
        if let c = c, results[c] == nil, busy == nil { runScan([c]) }
    }

    /// Drops items that no longer exist (deleted in Finder, by another app, or by an earlier clean).
    func pruneMissing() {
        guard busy == nil else { return }
        var gone: [URL] = []
        for key in Array(results.keys) {
            guard let list = results[key] else { continue }
            let kept = list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            if kept.count != list.count {
                let keptIDs = Set(kept.map { $0.id })
                for it in list where !keptIDs.contains(it.id) { selection.remove(it.id); gone.append(it.url) }
                results[key] = kept
            }
        }
        if !gone.isEmpty {
            homeIndex?.prune(removed: gone)
            refreshDisk()
            refreshTrash()
        }
    }

    func scanAll() { askScanScope = true; Chiptune.shared.sfx(.pop) }

    /// full = also the whole disk and every other user's folder (one admin password).
    func scanAll(full: Bool) {
        if full {
            runScan(CleanCategory.allCases.filter { $0 != .diskMap }, thenFull: true)
        } else {
            runScan(CleanCategory.allCases)
        }
    }

    func rescan(_ c: CleanCategory) {
        if c.needsIndex { homeIndex = nil }
        runScan([c])
    }

    func cancel() {
        reporter?.cancel()
        updateBusy { $0.title = "Okke~ mi fermo! ✋" }
        Chiptune.shared.sfx(.error)
    }

    private func updateBusy(_ f: (inout BusyState) -> Void) {
        if var b = busy { f(&b); busy = b }
    }

    private func setResults(_ c: CleanCategory, _ items: [CleanItem], keepOthers: Bool = true) {
        let old = results[c] ?? []
        // a normal rescan only covers this user: keep what the whole-disk scan found for the others
        let kept = (keepOthers && c != .diskMap) ? old.filter { !$0.owner.isEmpty } : []
        let keptIDs = Set(kept.map { $0.id })
        selection.subtract(old.map { $0.id }.filter { !keptIDs.contains($0) })
        results[c] = items + kept
        selection.formUnion(items.filter { $0.recommended }.map { $0.id })
    }

    private func runScan(_ cats: [CleanCategory], thenFull: Bool = false) {
        guard busy == nil, !cats.isEmpty else { return }
        let rep = Reporter()
        reporter = rep
        busy = BusyState(activity: cats[0].activity, title: cats[0].scanTitle, progress: 0, steps: cats.count)
        rep.onUpdate = { [weak self] text, p in
            guard let self = self, var b = self.busy else { return }
            b.detail = text
            if let p = p {
                b.progress = (Double(b.step) + min(max(p, 0), 1)) / Double(max(b.steps, 1))
            }
            self.busy = b
        }
        Chiptune.shared.sfx(.whoosh)
        Task {
            for (i, cat) in cats.enumerated() {
                if rep.isCancelled { break }
                Chiptune.shared.mood = (cat == .duplicates) ? .detective : .scanning
                Chiptune.shared.intensity = Double(i) / Double(cats.count)
                if cat.needsIndex && (homeIndex == nil || homeIndex?.isStale == true) {
                    updateBusy {
                        $0.step = i
                        $0.activity = .digging
                        $0.title = "Esplorazione della tana, tan-tan! 🏡"
                        $0.progress = cats.count > 1 ? Double(i) / Double(cats.count) : nil
                    }
                    let idx = await Task.detached(priority: .userInitiated) { HomeIndex.build(reporter: rep) }.value
                    if rep.isCancelled { break }
                    homeIndex = idx
                }
                updateBusy {
                    $0.step = i
                    $0.activity = cat.activity
                    $0.title = cat.scanTitle
                    if $0.progress == nil { $0.progress = Double(i) / Double(cats.count) }
                }
                let index = homeIndex
                let found = await Task.detached(priority: .userInitiated) { Scanners.scan(cat, index: index, reporter: rep) }.value
                if rep.isCancelled { break }
                setResults(cat, found)
                if cat == .diskMap { diskMapIsFull = false; refreshBreakdown() }
                let bytes = found.totalSize
                updateBusy { $0.foundCount += found.count; $0.foundBytes += bytes }
                Chiptune.shared.sfx(.coin)
            }
            if thenFull && !rep.isCancelled {
                updateBusy { $0.activity = .lookout; $0.title = "Ora tutto il disco e gli altri utenti! 🔐"; $0.progress = nil; $0.detail = "Serve la password una volta sola" }
                Chiptune.shared.mood = .scanning
                let full = await Task.detached(priority: .userInitiated) { HelperMode.fullScan(rep) }.value
                if let e = full.error { showToast(e) }
                if !full.map.isEmpty {
                    setResults(.diskMap, full.map)
                    diskMapIsFull = true
                    refreshBreakdown()
                }
                if full.error == nil || !full.others.isEmpty {
                    for (c, list) in full.others {
                        let mine = (results[c] ?? []).filter { $0.owner.isEmpty }
                        results[c] = mine + list
                    }
                    fullScanDone = true
                    scope = .all
                }
            }
            let cancelled = rep.isCancelled
            busy = nil
            reporter = nil
            Chiptune.shared.intensity = 0
            Chiptune.shared.mood = cancelled ? .menu : .results
            refreshDisk()
            if !cancelled && cats.count > 1 { showToast("Missione compiuta!! Bottino: \(Fmt.bytes(foundTotal)) ☆ Sugoi~!") }
        }
    }

    // MARK: cleaning

    func clean(_ c: CleanCategory) {
        guard busy == nil else { return }
        var items = selectedItems(c)
        if c == .duplicates {
            // Always keep at least one copy per group, and only if that copy still exists.
            let groups = Dictionary(grouping: self.items(c), by: { $0.group ?? -1 })
            var safe: [CleanItem] = []
            for (_, g) in groups {
                let keepers = g.filter { !selection.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path) }
                if keepers.isEmpty {
                    // whole group selected: spare the 💎 one (or the first)
                    let spare = g.first(where: { !$0.recommended }) ?? g[0]
                    guard FileManager.default.fileExists(atPath: spare.url.path) else { continue }
                    safe += g.filter { selection.contains($0.id) && $0.id != spare.id }
                } else {
                    safe += g.filter { selection.contains($0.id) }
                }
            }
            if safe.count < items.count { showToast("Tranquillo~ ho tenuto almeno un gemellino di ogni file 💎") }
            items = safe
        }
        guard !items.isEmpty else { return }
        let toTrash = items
        let rep = Reporter()
        reporter = rep
        busy = BusyState(activity: .sweeping, title: "Suri spazza via \(items.count) \(items.count == 1 ? "elemento" : "elementi")…", progress: 0)
        rep.onUpdate = { [weak self] text, p in
            guard let self = self, var b = self.busy else { return }
            b.detail = text
            if let p = p { b.progress = p }
            self.busy = b
            Chiptune.shared.sfx(.coin)
        }
        Chiptune.shared.mood = .cleaning
        Chiptune.shared.sfx(.whoosh)
        Task {
            let o = await Task.detached(priority: .userInitiated) { Cleaner.trash(toTrash, reporter: rep) }.value
            let removed = Set(o.removed)
            for key in Array(results.keys) {
                results[key]?.removeAll { removed.contains($0.id) || !FileManager.default.fileExists(atPath: $0.url.path) }
            }
            selection.subtract(removed)
            homeIndex?.prune(removed: o.removedURLs)
            busy = nil
            reporter = nil
            totalFreed += o.bytes
            refreshDisk()
            refreshTrash()
            var msg = ""
            if !o.failed.isEmpty {
                msg = "\(o.failed.count) elementi non si sono lasciati spostare (in uso, protetti o di proprietà del sistema): \(o.failed.prefix(3).joined(separator: ", "))\(o.failed.count > 3 ? "…" : "")"
            }
            if toTrash.contains(where: { $0.copyText != nil }) && o.bytes > 0 {
                msg += (msg.isEmpty ? "" : "\n") + "I comandi per riclonare i repo sono in Documenti › «SuriClean - repo rimossi.txt»."
            }
            celebrate(Celebration(kind: .trashed, bytes: o.bytes, failed: o.failed.count, message: msg))
        }
    }

    func emptyTrash() {
        guard busy == nil else { return }
        celebration = nil
        busy = BusyState(activity: .sweeping, title: "Pulizia finale, pika-pika! 🗑️✨", progress: nil)
        Chiptune.shared.mood = .cleaning
        Chiptune.shared.sfx(.whoosh)
        let before = DiskInfo.current().availableImportant
        let trashBefore = trashSize
        Task {
            _ = await Task.detached(priority: .userInitiated) { Cleaner.emptyTrash() }.value
            let after = await Task.detached(priority: .utility) { FS.allocatedSize(FS.trashURL) }.value
            busy = nil
            trashSize = after
            refreshDisk()
            let freed = max(trashBefore - after, max(0, disk.availableImportant - before))
            celebrate(Celebration(kind: .emptied, bytes: freed,
                                  message: after > 0 ? "Qualcosa è rimasto: forse serve l'Accesso completo al disco o un file è in uso." : ""))
        }
    }

    func scanFullDisk() {
        guard busy == nil else { return }
        let rep = Reporter()
        reporter = rep
        busy = BusyState(activity: .lookout, title: "Misuro tutto il disco, kira-kira! 💽", progress: nil)
        rep.onUpdate = { [weak self] text, _ in self?.updateBusy { $0.detail = text } }
        Chiptune.shared.mood = .scanning
        Task {
            let r = await Task.detached(priority: .userInitiated) { Scanners.diskMapFull(rep) }.value
            busy = nil
            reporter = nil
            switch r {
            case .success(let list):
                setResults(.diskMap, list)
                diskMapIsFull = true
                refreshBreakdown()
                Chiptune.shared.mood = .results
                Chiptune.shared.sfx(.coin)
                showToast("Ecco tutto il disco, anche gli altri utenti ☆")
            case .failure(let e):
                Chiptune.shared.mood = .menu
                Chiptune.shared.sfx(.error)
                showToast((e as NSError).localizedDescription)
            }
        }
    }

    func refreshBreakdown() {
        let measured = displayTotal(.diskMap)
        let label = diskMapIsFull ? "Dati misurati (tutti gli utenti)" : "La tua cartella Inizio"
        Task {
            let slices = await Task.detached(priority: .utility) { APFSInfo.breakdown(measured: measured, measuredLabel: label) }.value
            diskBreakdown = slices
        }
    }

    func thinSnapshots() {
        guard busy == nil else { return }
        busy = BusyState(activity: .sweeping, title: "Dieta per Time Machine! ⏳", progress: nil)
        Chiptune.shared.mood = .cleaning
        let before = DiskInfo.current().availableImportant
        Task {
            let r = await Task.detached { Shell.run("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"], mergeStderr: true) }.value
            busy = nil
            refreshDisk()
            refreshSnapshots()
            if r.status == 0 {
                celebrate(Celebration(kind: .info, bytes: max(0, disk.availableImportant - before),
                                      message: "Istantanee locali di Time Machine assottigliate."))
            } else {
                Chiptune.shared.mood = .menu
                showToast("tmutil non ha potuto procedere: \(r.output.prefix(120))")
            }
        }
    }

    private func celebrate(_ c: Celebration) {
        celebration = c
        Chiptune.shared.mood = .victory
        Task {
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            if Chiptune.shared.mood == .victory { Chiptune.shared.mood = .results }
        }
    }

    func dismissCelebration() {
        celebration = nil
        Chiptune.shared.sfx(.pop)
    }
}


extension Result {
    var failureMessage: String {
        if case .failure(let e) = self { return (e as NSError).localizedDescription }
        return ""
    }
}
