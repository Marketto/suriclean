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
    @Published var showFDAGuide = false
    @Published var passwordPrompt: PasswordPrompt?
    private var passwordWaiter: CheckedContinuation<Bool, Never>?
    private var fullScanAfterFDA = false
    private var fullDiskAfterFDA = false
    @Published var trashSize: Int64 = 0
    @Published var askEmptyTrash = false
    @Published var snapshotCount: Int?
    @Published var toast: String?
    /// Current UI language (see L10n); the whole window is rebuilt when it changes.
    @Published var lang: String = L10n.shared.code
    @Published var langChoice: String? = L10n.shared.chosen

    func setLanguage(_ code: String?) {
        L10n.shared.set(code: code)
        langChoice = code
        lang = L10n.shared.code
        Chiptune.shared.sfx(.pop)
    }

    @Published var remix: Bool = UserDefaults.standard.bool(forKey: "suri.remix") {
        didSet {
            UserDefaults.standard.set(remix, forKey: "suri.remix")
            Chiptune.shared.remix = remix
        }
    }
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
    @Published var deniedPaths: [String] = []
    @Published var snapshotNames: [String] = []
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
        Chiptune.shared.remix = remix
        Chiptune.shared.mood = .menu
        refreshDisk()
        hasFDA = FS.hasFullDiskAccess()
        if !hasFDA && UserDefaults.standard.string(forKey: "fdaSnoozedVersion") != Updater.currentVersion {
            showFDAGuide = true
        }
        if UserDefaults.standard.bool(forKey: "fullScanAfterRelaunch") {
            UserDefaults.standard.set(false, forKey: "fullScanAfterRelaunch")
            if hasFDA { askScanScope = true }
        }
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
            var failed = false
            switch action {
            case .deleteBranch(let b):
                let r = await Task.detached { GitTools.deleteBranch(repo, b) }.value
                if let m = try? r.get() { message = m } else { message = t("mac.toast.ehh", r.failureMessage); failed = true }
            case .dropStash(let s):
                let r = await Task.detached { GitTools.dropStash(repo, s) }.value
                if let m = try? r.get() { message = m } else { message = t("mac.toast.ehh", r.failureMessage); failed = true }
            case .compact:
                let r = await Task.detached { GitTools.compact(repo) }.value
                if let saved = try? r.get() {
                    totalFreed += saved
                    message = saved > 0 ? t("mac.git.compacted", Fmt.bytes(saved)) : t("mac.git.alreadycompact")
                } else { message = t("mac.toast.ehh", r.failureMessage); failed = true }
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
            Chiptune.shared.sfx(failed ? .error : .coin)
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
            if manual { showToast(t("mac.upd.latest", Updater.currentVersion)) }
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
            showToast(t("mac.upd.ready", info.version))
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
        showToast(hasFDA ? t("mac.fda.yatta") : t("mac.fda.still"))
    }

    // MARK: administrator password (see Admin)

    /// Makes sure root commands can keep Full Disk Access: asks the password in Suri's window.
    /// Returns false only if the user cancels.
    func ensureAdmin(_ reason: String) async -> Bool {
        if Admin.password != nil || !Admin.isAdminUser { return true }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            passwordWaiter?.resume(returning: false)
            passwordWaiter = c
            passwordPrompt = PasswordPrompt(reason: reason)
            Chiptune.shared.sfx(.pop)
        }
    }

    func submitPassword(_ pw: String) {
        guard !pw.isEmpty, passwordPrompt?.checking != true else { return }
        passwordPrompt?.checking = true
        passwordPrompt?.error = nil
        Task {
            let ok = await Task.detached(priority: .userInitiated) { Admin.validate(pw) }.value
            if ok {
                Admin.remember(pw)
                passwordPrompt = nil
                Chiptune.shared.sfx(.coin)
                passwordWaiter?.resume(returning: true)
                passwordWaiter = nil
            } else {
                passwordPrompt?.checking = false
                passwordPrompt?.error = t("mac.pw.wrong")
                Chiptune.shared.sfx(.error)
            }
        }
    }

    func cancelPassword() {
        passwordPrompt = nil
        passwordWaiter?.resume(returning: false)
        passwordWaiter = nil
    }

    func fdaGuideDismissed() {
        showFDAGuide = false
        UserDefaults.standard.set(Updater.currentVersion, forKey: "fdaSnoozedVersion")
        if fullScanAfterFDA { fullScanAfterFDA = false; scanAll(full: true, askedFDA: true) }
        if fullDiskAfterFDA { fullDiskAfterFDA = false; scanFullDisk(askedFDA: true) }
    }

    /// Full Disk Access only applies to a fresh process: quit and open again.
    func relaunch() {
        showFDAGuide = false
        UserDefaults.standard.set(fullScanAfterFDA || fullDiskAfterFDA, forKey: "fullScanAfterRelaunch")
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let pid = ProcessInfo.processInfo.processIdentifier
        // wait until this copy has really quit, otherwise `open` would only bring it to the front
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n '\(path)'"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }   // never stay stuck
    }

    /// Permission granted: carry on without restarting (macOS usually applies it right away).
    func fdaGrantedContinue() {
        hasFDA = FS.hasFullDiskAccess()
        showFDAGuide = false
        showToast(t("mac.fda.yatta"))
        if fullScanAfterFDA { fullScanAfterFDA = false; scanAll(full: true, askedFDA: true) }
        if fullDiskAfterFDA { fullDiskAfterFDA = false; scanFullDisk(askedFDA: true) }
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
                return t("mac.greet.full", pct)
            } else if pct >= 70 {
                return t("mac.greet.mid", pct)
            }
            return t("mac.greet.ok", pct)
        }
        return t("mac.greet.found", Fmt.bytes(foundTotal), Fmt.bytes(recommendedTotal))
    }

    var level: (title: String, emoji: String, progress: Double, next: String) {
        let gb = Double(totalFreed) / 1_000_000_000
        let steps: [(Double, String, String)] = [
            (1, t("mac.level.1"), "🐣"), (5, t("mac.level.2"), "🌱"),
            (20, t("mac.level.3"), "👀"), (50, t("mac.level.4"), "👑")
        ]
        var prev = 0.0
        for s in steps {
            if gb < s.0 { return (s.1, s.2, (gb - prev) / (s.0 - prev), t("mac.level.next", Int(s.0))) }
            prev = s.0
        }
        return (t("mac.level.5"), "🌟", 1, t("mac.level.max"))
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
    func scanAll(full: Bool, askedFDA: Bool = false) {
        if full && !askedFDA && !FS.hasFullDiskAccess() {
            fullScanAfterFDA = true
            showFDAGuide = true
            return
        }
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
        updateBusy { $0.title = t("mac.busy.stop") }
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
                        $0.title = t("mac.busy.index")
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
                updateBusy { $0.activity = .lookout; $0.title = t("mac.busy.nowfull"); $0.progress = nil; $0.detail = t("mac.busy.onepwonly") }
                Chiptune.shared.mood = .scanning
                let allowed = await ensureAdmin(t("mac.pw.reason.full"))
                var full = HelperMode.FullResult(error: t("mac.err.cancelfull"))
                if allowed { full = await Task.detached(priority: .userInitiated) { HelperMode.fullScan(rep) }.value }
                if let e = full.error { showToast(e) }
                if !full.map.isEmpty {
                    deniedPaths = full.denied
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
            if !cancelled && cats.count > 1 { showToast(t("mac.toast.mission", Fmt.bytes(foundTotal))) }
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
            if safe.count < items.count { showToast(t("mac.toast.keptdup")) }
            items = safe
        }
        guard !items.isEmpty else { return }
        let toTrash = items
        let rep = Reporter()
        reporter = rep
        busy = BusyState(activity: .sweeping, title: tp("mac.busy.sweep", items.count, items.count), progress: 0)
        rep.onUpdate = { [weak self] text, p in
            guard let self = self, var b = self.busy else { return }
            b.detail = text
            if let p = p { b.progress = p }
            self.busy = b
            Chiptune.shared.sfx(.coin)
        }
        Chiptune.shared.mood = .cleaning
        Chiptune.shared.sfx(.whoosh)
        let fm = FileManager.default
        let needsAdmin = toTrash.contains { !$0.owner.isEmpty || !fm.isWritableFile(atPath: $0.url.deletingLastPathComponent().path) }
        Task {
            if needsAdmin { _ = await ensureAdmin(t("mac.pw.reason.trash")) }
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
                msg = t("mac.clean.failed", o.failed.count, o.failed.prefix(3).joined(separator: ", ") + (o.failed.count > 3 ? "…" : ""))
            }
            if toTrash.contains(where: { $0.copyText != nil }) && o.bytes > 0 {
                msg += (msg.isEmpty ? "" : "\n") + t("mac.clean.repolog")
            }
            celebrate(Celebration(kind: .trashed, bytes: o.bytes, failed: o.failed.count, message: msg))
        }
    }

    func emptyTrash() {
        guard busy == nil else { return }
        celebration = nil
        busy = BusyState(activity: .sweeping, title: t("mac.busy.emptytrash"), progress: nil)
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
                                  message: after > 0 ? t("mac.trash.left") : ""))
        }
    }

    func scanFullDisk(askedFDA: Bool = false) {
        guard busy == nil else { return }
        if !askedFDA && !FS.hasFullDiskAccess() {
            fullDiskAfterFDA = true
            showFDAGuide = true
            return
        }
        let rep = Reporter()
        reporter = rep
        busy = BusyState(activity: .lookout, title: t("mac.busy.diskfull"), progress: nil)
        rep.onUpdate = { [weak self] text, _ in self?.updateBusy { $0.detail = text } }
        Chiptune.shared.mood = .scanning
        Task {
            guard await ensureAdmin(t("mac.pw.reason.disk")) else {
                busy = nil
                reporter = nil
                Chiptune.shared.mood = .menu
                return
            }
            let r = await Task.detached(priority: .userInitiated) { Scanners.diskMapFull(rep) }.value
            busy = nil
            reporter = nil
            switch r {
            case .success(let (list, denied)):
                deniedPaths = denied
                setResults(.diskMap, list)
                diskMapIsFull = true
                refreshBreakdown()
                Chiptune.shared.mood = .results
                Chiptune.shared.sfx(.coin)
                showToast(t("mac.toast.fulldisk"))
            case .failure(let e):
                Chiptune.shared.mood = .menu
                Chiptune.shared.sfx(.error)
                showToast((e as NSError).localizedDescription)
            }
        }
    }

    func refreshBreakdown() {
        let measured = displayTotal(.diskMap)
        let label = diskMapIsFull ? t("mac.slice.measuredall") : t("mac.slice.home")
        let purgeable = DiskInfo.current().purgeable
        let denied = diskMapIsFull ? deniedPaths.count : 0
        if !diskMapIsFull { deniedPaths = [] }
        Task {
            let snaps = await Task.detached(priority: .utility) { APFSInfo.snapshots() }.value
            snapshotNames = snaps
            let slices = await Task.detached(priority: .utility) {
                APFSInfo.breakdown(measured: measured, measuredLabel: label, purgeable: purgeable, snapshots: snaps, denied: denied)
            }.value
            diskBreakdown = slices
        }
    }

    /// Deletes local APFS snapshots of the data volume with one password (system-update ones are left alone).
    func deleteSnapshots() {
        guard busy == nil else { return }
        let names = snapshotNames.filter { !$0.hasPrefix("com.apple.os.update") }
        guard !names.isEmpty else { return }
        busy = BusyState(activity: .sweeping, title: t("mac.busy.snaps"), progress: nil)
        Chiptune.shared.mood = .cleaning
        let before = DiskInfo.current().availableImportant
        Task {
            guard await ensureAdmin(t("mac.pw.reason.snaps")) else { busy = nil; Chiptune.shared.mood = .menu; return }
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                var lines = ["/usr/bin/tmutil deletelocalsnapshots / >/dev/null 2>&1"]
                for n in names { lines.append("/usr/sbin/diskutil apfs deleteSnapshot /System/Volumes/Data -name \(q(n)) >/dev/null 2>&1") }
                return Admin.run(lines, prompt: t("mac.prompt.snaps")).ok
            }.value
            busy = nil
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // APFS frees space asynchronously
            refreshDisk()
            refreshSnapshots()
            refreshBreakdown()
            let freed = max(0, disk.availableImportant - before)
            if ok {
                celebrate(Celebration(kind: .info, bytes: freed, message: t("mac.snaps.done")))
            } else {
                Chiptune.shared.mood = .menu
                showToast(t("mac.snaps.fail"))
            }
        }
    }

    func thinSnapshots() {
        guard busy == nil else { return }
        busy = BusyState(activity: .sweeping, title: t("mac.busy.tmthin"), progress: nil)
        Chiptune.shared.mood = .cleaning
        let before = DiskInfo.current().availableImportant
        Task {
            let r = await Task.detached { Shell.run("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"], mergeStderr: true) }.value
            busy = nil
            refreshDisk()
            refreshSnapshots()
            if r.status == 0 {
                celebrate(Celebration(kind: .info, bytes: max(0, disk.availableImportant - before),
                                      message: t("mac.tm.thinned")))
            } else {
                Chiptune.shared.mood = .menu
                showToast(t("mac.tm.fail", String(r.output.prefix(120))))
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

struct PasswordPrompt: Equatable {
    var reason: String
    var error: String? = nil
    var checking = false
}
