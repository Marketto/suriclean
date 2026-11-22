import Foundation

/// Moves items to the Trash (one password for the protected ones) and empties it.
enum Cleaner {
    struct Outcome {
        var removed: [UUID] = []
        var removedURLs: [URL] = []
        var bytes: Int64 = 0
        var failed: [String] = []
    }

    static func trash(_ items: [CleanItem], reporter: Reporter) -> Outcome {
        var o = Outcome()
        let fm = FileManager.default
        var repoLog: [String] = []
        let stamp = ISO8601DateFormatter().string(from: Date())
        var protected: [CleanItem] = []

        func done(_ item: CleanItem) {
            for extra in item.extraURLs where fm.fileExists(atPath: extra.path) {
                try? fm.trashItem(at: extra, resultingItemURL: nil)
            }
            o.removed.append(item.id)
            o.removedURLs.append(item.url)
            // count only what really moved
            let left = item.extraURLs.filter { fm.fileExists(atPath: $0.path) }
            o.bytes += max(0, item.size - left.reduce(Int64(0)) { $0 + FS.allocatedSize($1) })
            if !left.isEmpty { o.failed.append(item.name) }
            if let c = item.copyText { repoLog.append(t("mac.repolog.entry", item.url.path, stamp) + "\n\(c)") }
        }

        for (i, item) in items.enumerated() {
            if reporter.isCancelled { break }
            reporter.report(item.name, progress: Double(i) / Double(max(items.count, 1)) * 0.8, force: true)
            if !fm.fileExists(atPath: item.url.path) {
                o.removed.append(item.id)        // already gone (e.g. inside a repo removed earlier)
                continue
            }
            if !item.owner.isEmpty {
                protected.append(item)           // another user's file: goes to *their* Trash, as admin
            } else if (try? fm.trashItem(at: item.url, resultingItemURL: nil)) != nil {
                done(item)
            } else {
                protected.append(item)           // admin-owned: handled all together below
            }
        }

        if !protected.isEmpty && !reporter.isCancelled {
            reporter.report(tp("mac.busy.onepw", protected.count, protected.count), progress: 0.85, force: true)
            adminTrash(protected.flatMap { it in ([it.url] + it.extraURLs).map { ($0, it.owner) } })
            for item in protected {
                if fm.fileExists(atPath: item.url.path) { o.failed.append(item.name) } else { done(item) }
            }
        }
        FS.appendToRepoLog(repoLog)
        reporter.report(t("mac.busy.done"), progress: 1, force: true)
        return o
    }

    /// Moves admin-owned items into the user's Trash with ONE password prompt,
    /// giving them back to the user so the Trash can be emptied normally.
    static func adminTrash(_ entries: [(URL, String)]) {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let me = NSUserName()
        let stamp = Int(Date().timeIntervalSince1970)
        var lines = ["#!/bin/bash"]
        for (i, (u, owner)) in entries.enumerated() where FileManager.default.fileExists(atPath: u.path) {
            let user = owner.isEmpty ? me : owner
            let trash = owner.isEmpty ? FS.trashURL.path : "/Users/\(owner)/.Trash"
            let base = u.deletingPathExtension().lastPathComponent
            let dest = trash + "/" + base + " \(stamp)-\(i)" + (u.pathExtension.isEmpty ? "" : "." + u.pathExtension)
            lines.append("mkdir -p \(q(trash)) && /usr/sbin/chown \(q(user)) \(q(trash))")
            lines.append("/usr/sbin/chown -R \(q(user)) \(q(u.path)) 2>/dev/null; /bin/mv \(q(u.path)) \(q(dest))")
        }
        guard lines.count > 1 else { return }
        _ = Admin.run(Array(lines.dropFirst()), prompt: t("mac.prompt.admintrash", entries.count))
    }

    @discardableResult
    static func emptyTrash() -> Bool {
        // Same as Finder › Empty Trash: fast and it handles protected items itself.
        let r = Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
        let fm = FileManager.default
        let left = (try? fm.contentsOfDirectory(atPath: FS.trashURL.path))?.filter { $0 != ".DS_Store" } ?? []
        if r.status == 0 && left.isEmpty { return true }
        // Fallback (no permission to talk to Finder): remove what we can ourselves.
        var allOK = true
        for name in left {
            let k = FS.trashURL.appendingPathComponent(name)
            if Shell.run("/bin/rm", ["-rf", k.path]).status != 0 || fm.fileExists(atPath: k.path) {
                _ = Shell.run("/bin/chmod", ["-R", "u+w", k.path])
                if Shell.run("/bin/rm", ["-rf", k.path]).status != 0 { allOK = false }
            }
        }
        return allOK
    }
}
