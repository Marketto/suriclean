import Foundation

struct GitBranch: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
    let date: Date?
    let upstream: String?
    let unpushed: Int        // commits that exist on no remote
    let merged: Bool         // already merged into the default branch
    var canDelete: Bool { !isCurrent && (merged || unpushed == 0) }
}

struct GitStash: Identifiable, Hashable {
    let id: String           // stash@{n}
    let message: String
    let date: Date?
}

struct GitDetails {
    var defaultBranch: String
    var branches: [GitBranch]
    var stashes: [GitStash]
    var gitSize: Int64
}

/// Read details of one repo and do the small, recoverable clean-ups (branch, stash, gc).
enum GitTools {
    private static func g(_ repo: URL, _ args: [String], readOnly: Bool = true) -> ShellResult {
        var env = ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]
        if readOnly { env["GIT_OPTIONAL_LOCKS"] = "0" }
        return Shell.run("/usr/bin/git", ["-C", repo.path] + args, env: env)
    }

    static func details(_ repo: URL) -> GitDetails {
        var def = ""
        let head = g(repo, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        if head.status == 0, let b = head.output.split(separator: "/", maxSplits: 1).last { def = String(b) }
        let current = g(repo, ["rev-parse", "--abbrev-ref", "HEAD"]).output
        if def.isEmpty {
            for c in ["main", "master", "develop"] where g(repo, ["rev-parse", "--verify", "--quiet", "refs/heads/\(c)"]).status == 0 { def = c; break }
        }
        if def.isEmpty { def = current }
        let mergedOut = g(repo, ["branch", "--merged", def, "--format=%(refname:short)"]).output
        let merged = Set(mergedOut.split(separator: "\n").map(String.init))
        let refs = g(repo, ["for-each-ref", "refs/heads", "--format=%(refname:short)%09%(committerdate:unix)%09%(upstream:short)%09%(HEAD)"]).output
        var branches: [GitBranch] = []
        for line in refs.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { continue }
            let name = f[0]
            let date = Double(f[1]).map { Date(timeIntervalSince1970: $0) }
            let up = f[2].isEmpty ? nil : f[2]
            let cnt = g(repo, ["rev-list", "--count", "refs/heads/\(name)", "--not", "--remotes"])
            let unpushed = cnt.status == 0 ? (Int(cnt.output) ?? 1) : 1
            branches.append(GitBranch(name: name, isCurrent: f[3] == "*", date: date, upstream: up, unpushed: unpushed,
                                      merged: merged.contains(name) && name != def))
        }
        branches.sort { ($0.isCurrent ? 0 : 1, -($0.date?.timeIntervalSince1970 ?? 0)) < ($1.isCurrent ? 0 : 1, -($1.date?.timeIntervalSince1970 ?? 0)) }
        var stashes: [GitStash] = []
        for line in g(repo, ["stash", "list", "--format=%gd%x09%ct%x09%gs"]).output.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { continue }
            stashes.append(GitStash(id: f[0], message: f[2], date: Double(f[1]).map { Date(timeIntervalSince1970: $0) }))
        }
        return GitDetails(defaultBranch: def, branches: branches, stashes: stashes,
                          gitSize: FS.allocatedSize(repo.appendingPathComponent(".git")))
    }

    private static var backupDir: URL {
        let d = FS.home.appendingPathComponent("Documents/SuriClean - backup git")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func log(_ text: String) {
        let f = backupDir.appendingPathComponent("da leggere - come recuperare.txt")
        let header = t("mac.git.logheader") + "\n\n"
        if let h = try? FileHandle(forWritingTo: f) {
            _ = try? h.seekToEnd(); h.write(Data((text + "\n\n").utf8)); try? h.close()
        } else {
            try? (header + text + "\n\n").write(to: f, atomically: true, encoding: .utf8)
        }
    }

    private static let stamp: () -> String = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"; return f.string(from: Date())
    }

    /// Deletes a branch only if it is merged or all its commits are on a remote. Notes the commit to restore it.
    static func deleteBranch(_ repo: URL, _ b: GitBranch) -> Result<String, Error> {
        guard b.canDelete else { return .failure(err(t("mac.git.branchunique", b.name))) }
        let sha = g(repo, ["rev-parse", "refs/heads/\(b.name)"]).output
        let r = g(repo, ["branch", "-D", b.name], readOnly: false)
        guard r.status == 0 else { return .failure(err(t("mac.git.branchfail", b.name))) }
        log("# \(stamp()) · \(repo.path) · " + t("mac.git.branchword", b.name) + "\ncd \"\(repo.path)\" && git branch \"\(b.name)\" \(sha)")
        return .success(t("mac.git.branchdone", b.name))
    }

    /// Saves the stash as a .patch in Documents, then drops it.
    static func dropStash(_ repo: URL, _ s: GitStash) -> Result<String, Error> {
        let sha = g(repo, ["rev-parse", s.id]).output
        var patch = g(repo, ["stash", "show", "-p", "--include-untracked", s.id])
        if patch.status != 0 { patch = g(repo, ["stash", "show", "-p", s.id]) }
        let safeName = repo.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let file = backupDir.appendingPathComponent("\(safeName) · \(stamp()) · \(s.id.replacingOccurrences(of: "/", with: "-")).patch")
        do {
            try ("# \(s.message)\n" + t("mac.git.patchheader", sha, repo.path) + "\n" + patch.output + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return .failure(err(t("mac.git.stashsavefail")))
        }
        let r = g(repo, ["stash", "drop", s.id], readOnly: false)
        guard r.status == 0 else { return .failure(err(t("mac.git.stashfail"))) }
        log("# \(stamp()) · \(repo.path) · stash «\(s.message)»\ncd \"\(repo.path)\" && git apply \"\(file.path)\"\n" + t("mac.git.stashalt", sha))
        return .success(t("mac.git.stashdone"))
    }

    /// git gc: packs objects and removes unreachable garbage. Returns bytes saved.
    static func compact(_ repo: URL) -> Result<Int64, Error> {
        let before = FS.allocatedSize(repo.appendingPathComponent(".git"))
        let r = g(repo, ["gc", "--quiet"], readOnly: false)
        guard r.status == 0 else { return .failure(err(t("mac.git.gcfail"))) }
        let after = FS.allocatedSize(repo.appendingPathComponent(".git"))
        return .success(max(0, before - after))
    }

    private static func err(_ s: String) -> NSError {
        NSError(domain: "SuriClean.Git", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }
}
