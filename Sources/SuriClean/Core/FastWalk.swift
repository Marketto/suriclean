import Foundation
import Darwin

/// Fast walk of a folder tree with BSD `fts` (several times quicker than FileManager's enumerator,
/// which builds an URL and a resource-values dictionary for every entry).
/// Never follows symbolic links and never leaves the volume it starts on.
enum FastWalk {
    enum Kind { case dir, dirEnd, file, other }
    enum Step { case go, skip, stop }

    struct Entry {
        let kind: Kind
        let path: String
        let level: Int
        /// Allocated size on disk (st_blocks × 512), 0 for folders.
        let size: Int64
        let modified: TimeInterval
        var name: Substring {
            guard let i = path.lastIndex(of: "/") else { return Substring(path) }
            return path[path.index(after: i)...]
        }
    }

    /// Calls `visit` for every entry: folders twice (`.dir` before their content, `.dirEnd` after,
    /// also when skipped or unreadable). `.skip` on a `.dir` leaves its content out.
    static func walk(_ root: String, _ visit: (Entry) -> Step) {
        guard let cpath = strdup(root) else { return }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
        defer { fts_close(fts) }
        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            let kind: Kind
            switch info {
            case FTS_D: kind = .dir
            case FTS_DP, FTS_DNR: kind = .dirEnd
            case FTS_F: kind = .file
            case FTS_ERR, FTS_NS, FTS_DC: continue
            default: kind = .other     // symbolic links, sockets, …
            }
            var size: Int64 = 0
            var mtime: TimeInterval = 0
            if kind == .file || kind == .dir, let st = ent.pointee.fts_statp {
                if kind == .file { size = Int64(st.pointee.st_blocks) * 512 }
                mtime = TimeInterval(st.pointee.st_mtimespec.tv_sec)
            }
            let e = Entry(kind: kind, path: String(cString: ent.pointee.fts_path), level: Int(ent.pointee.fts_level),
                          size: size, modified: mtime)
            switch visit(e) {
            case .go: break
            case .skip: if kind == .dir { fts_set(fts, ent, FTS_SKIP) }
            case .stop: return
            }
        }
    }

    /// Total allocated size of a file or folder.
    static func size(_ path: String, reporter: Reporter? = nil) -> Int64 {
        var total: Int64 = 0
        var n = 0
        walk(path) { e in
            n += 1
            if n % 2000 == 0 {
                if reporter?.isCancelled == true { return .stop }
                reporter?.report(FS.pretty(URL(fileURLWithPath: e.path)))
            }
            total += e.size
            return .go
        }
        return total
    }
}
