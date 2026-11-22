import SwiftUI

/// Cleaning: one zone, the worry-free quick clean, the Trash.
extension AppModel {
    // MARK: cleaning

    func clean(_ c: CleanCategory) {
        guard !needsConsent else { return }
        guard busy == nil, c != .diskMap else { return }   // the map is view-only (it holds the home itself)
        var items = selectedItems(c)
        if c == .duplicates { items = keepOneCopy(items) }
        performTrash(withoutNested(items))
    }

    /// Duplicates: always keeps at least one copy per group, and only if that copy still exists.
    func keepOneCopy(_ chosen: [CleanItem]) -> [CleanItem] {
        let ids = Set(chosen.map { $0.id })
        let groups = Dictionary(grouping: self.items(.duplicates), by: { $0.group ?? -1 })
        var safe: [CleanItem] = []
        for (_, g) in groups {
            let keepers = g.filter { !ids.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path) }
            if keepers.isEmpty {
                // whole group chosen: spare the 💎 one (or the first)
                let spare = g.first(where: { !$0.recommended }) ?? g[0]
                guard FileManager.default.fileExists(atPath: spare.url.path) else { continue }
                safe += g.filter { ids.contains($0.id) && $0.id != spare.id }
            } else {
                safe += g.filter { ids.contains($0.id) }
            }
        }
        if safe.count < chosen.count { showToast(t("mac.toast.keptdup")) }
        return safe
    }

    // MARK: quick clean («liberabili senza pensieri»)

    /// The recommended items of every zone (not the map, not Schiaccia), biggest first.
    struct QuickGroup: Identifiable {
        let category: CleanCategory
        let items: [CleanItem]
        var id: CleanCategory { category }
    }

    var quickGroups: [QuickGroup] {
        CleanCategory.allCases.compactMap { c in
            guard c != .diskMap && c != .squeeze else { return nil }
            let l = items(c).filter { $0.recommended }.sorted { $0.size > $1.size }
            return l.isEmpty ? nil : QuickGroup(category: c, items: l)
        }
    }

    /// What the ticked items really free: nested items and the same path in two zones count once.
    func quickSize(_ picked: [CleanItem]) -> Int64 {
        var seen = Set<String>()
        return withoutNested(picked).filter { seen.insert($0.url.standardizedFileURL.path).inserted }.totalSize
    }

    func openQuickClean() {
        guard !needsConsent, busy == nil else { return }
        pruneMissing()
        quickPick = Set(quickGroups.flatMap { $0.items.map { $0.id } })
        showQuickClean = true
        Chiptune.shared.sfx(.pop)
    }

    func toggleQuick(_ ids: [UUID], on: Bool) {
        if on { quickPick.formUnion(ids) } else { quickPick.subtract(ids) }
        Chiptune.shared.sfx(on ? .coin : .pop)
    }

    func runQuickClean(emptyTrashAfter: Bool) {
        var chosen: [CleanItem] = []
        for g in quickGroups {
            let picked = g.items.filter { quickPick.contains($0.id) }
            chosen += g.category == .duplicates ? keepOneCopy(picked) : picked
        }
        showQuickClean = false
        performTrash(withoutNested(sparingCopies(chosen)), emptyTrashAfter: emptyTrashAfter)
    }

    /// A duplicate group must keep one copy even when its copies are reached through other zones
    /// (an old installer, a folder): if every copy would go, the preferred one and whatever contains it stay.
    func sparingCopies(_ chosen: [CleanItem]) -> [CleanItem] {
        var out = chosen
        func covered(_ u: URL, by list: [CleanItem]) -> Bool {
            let set = Set(list.map { $0.url.standardizedFileURL.path })
            var p = u.standardizedFileURL.path
            while p.count > 1 {
                if set.contains(p) { return true }
                p = (p as NSString).deletingLastPathComponent
            }
            return false
        }
        let groups = Dictionary(grouping: items(.duplicates), by: { $0.group ?? -1 })
        for (_, g) in groups {
            let there = g.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            guard !there.isEmpty, there.allSatisfy({ covered($0.url, by: out) }) else { continue }
            let spare = there.first(where: { !$0.recommended }) ?? there[0]
            let keep = spare.url.standardizedFileURL.path
            out.removeAll { it in
                let p = it.url.standardizedFileURL.path
                return p == keep || keep.hasPrefix(p + "/")
            }
        }
        if out.count < chosen.count { showToast(t("mac.toast.keptdup")) }
        return out
    }

    /// An item inside another chosen folder goes with it: counted once.
    func withoutNested(_ items: [CleanItem]) -> [CleanItem] {
        let dirs = Set(items.map { $0.url.standardizedFileURL.path })
        return items.filter { it in
            var p = it.url.standardizedFileURL.deletingLastPathComponent().path
            while p.count > 1 {
                if dirs.contains(p) { return false }
                p = (p as NSString).deletingLastPathComponent
            }
            return true
        }
    }

    /// Moves the items to the Trash (one password for the protected ones), then celebrates.
    func performTrash(_ items: [CleanItem], emptyTrashAfter: Bool = false) {
        guard !needsConsent, busy == nil else { return }
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
            var emptied = false
            if emptyTrashAfter && !o.removed.isEmpty {
                updateBusy { $0.title = t("mac.busy.emptytrash"); $0.progress = nil }
                _ = await Task.detached(priority: .userInitiated) { Cleaner.emptyTrash() }.value
                emptied = true
            }
            busy = nil
            reporter = nil
            totalFreed += o.bytes
            refreshDisk()
            refreshTrash()
            var msg = emptied ? t("mac.quick.emptied") : ""
            if !o.failed.isEmpty {
                msg += (msg.isEmpty ? "" : "\n") + t("mac.clean.failed", o.failed.count, o.failed.prefix(3).joined(separator: ", ") + (o.failed.count > 3 ? "…" : ""))
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
}
