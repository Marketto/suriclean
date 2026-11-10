import Foundation

/// «Cosa cresce»: every home disk map is remembered (folder sizes, home, Applications, used space),
/// so the next one can tell which folders grew and how much grew outside the home folder.
/// Only sizes and paths, only on this Mac (Application Support/SuriClean/growth.json).
enum Growth {
    /// Smallest growth worth a badge or a row.
    static let minShown: Int64 = 200 * 1_048_576
    /// Folders smaller than this are not remembered (keeps the file small).
    static let minKept: Int64 = 20 * 1_048_576

    struct Snapshot: Codable {
        var date: Date
        var used: Int64
        var home: Int64
        var apps: Int64
        var sizes: [String: Int64]
    }

    struct Report {
        var since: Date
        var usedDelta: Int64
        var homeDelta: Int64
        var appsDelta: Int64
        /// Grown space not in the home folder nor in Applications: system, other users, snapshots, swap.
        var outside: Int64 { usedDelta - homeDelta - appsDelta }
        /// The folders that explain the growth, most specific first-come (no parent of a listed child).
        var top: [Entry]
    }

    struct Entry: Identifiable {
        let path: String
        let delta: Int64
        var id: String { path }
    }

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SuriClean/growth.json")
    }

    static func load() -> [Snapshot] {
        guard let d = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([Snapshot].self, from: d)) ?? []
    }

    private static func store(_ list: [Snapshot]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(list) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
    }

    /// What to compare with: the newest snapshot at least 12 hours older than `now`,
    /// otherwise the oldest one that is at least 10 minutes old.
    static func baseline(_ list: [Snapshot], now: Date) -> Snapshot? {
        let older = list.filter { now.timeIntervalSince($0.date) >= 12 * 3600 }
        if let b = older.max(by: { $0.date < $1.date }) { return b }
        return list.filter { now.timeIntervalSince($0.date) >= 600 }.min(by: { $0.date < $1.date })
    }

    /// Growth of every measured folder since the baseline (before saving the new map).
    static func compare(sizes: [String: Int64], home: Int64) -> (since: Date, grew: [String: Int64])? {
        guard let b = baseline(load(), now: Date()) else { return nil }
        var grew: [String: Int64] = [:]
        for (p, s) in sizes {
            let d = s - (b.sizes[p] ?? 0)
            if d > 0 { grew[p] = d }
        }
        return (b.date, grew)
    }

    /// Remembers this map. A map less than 6 hours after the previous one replaces it,
    /// so frequent scans do not push the baseline away; at most 12 are kept.
    static func save(sizes: [String: Int64], home: Int64, apps: Int64, used: Int64) {
        var list = load().sorted { $0.date < $1.date }
        let snap = Snapshot(date: Date(), used: used, home: home, apps: apps, sizes: sizes.filter { $0.value >= minKept })
        if let last = list.last, snap.date.timeIntervalSince(last.date) < 6 * 3600, list.count > 1 {
            list[list.count - 1] = snap
        } else {
            list.append(snap)
        }
        store(Array(list.suffix(12)))
    }

    /// Latest map compared with its baseline.
    static func report() -> Report? {
        let list = load().sorted { $0.date < $1.date }
        guard let last = list.last, let b = baseline(Array(list.dropLast()), now: last.date) else { return nil }
        var grew: [String: Int64] = [:]
        for (p, s) in last.sizes {
            let d = s - (b.sizes[p] ?? 0)
            if d >= minShown { grew[p] = d }
        }
        return Report(since: b.date, usedDelta: last.used - b.used, homeDelta: last.home - b.home,
                      appsDelta: last.apps - b.apps, top: specific(grew, limit: 5))
    }

    /// Picks the folders that explain the growth: a folder is left out when one of its
    /// subfolders accounts for most (70%) of its growth, since that subfolder is listed instead.
    static func specific(_ grew: [String: Int64], limit: Int) -> [Entry] {
        let sorted = grew.sorted { $0.value > $1.value }
        var out: [Entry] = []
        for (p, d) in sorted {
            let prefix = p + "/"
            let explained = grew.contains { $0.key.hasPrefix(prefix) && $0.value >= d * 7 / 10 }
            if explained { continue }
            if out.contains(where: { $0.path.hasPrefix(prefix) || p.hasPrefix($0.path + "/") }) { continue }
            out.append(Entry(path: p, delta: d))
            if out.count == limit { break }
        }
        return out
    }
}
