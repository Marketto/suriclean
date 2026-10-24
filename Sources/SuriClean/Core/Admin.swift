import Foundation

/// Runs shell scripts as root.
///
/// Since macOS 10.15 AppleScript's `with administrator privileges` runs commands through the
/// `com.apple.security.authtrampoline` launchd daemon, so they lose their link to SuriClean and
/// with it the Full Disk Access the user granted (Apple: "inherent in the new implementation").
/// `sudo` started directly by SuriClean keeps SuriClean as the responsible process, exactly like
/// `sudo` in Terminal uses Terminal's Full Disk Access. So when the user is an administrator,
/// Suri asks the password in her own window and feeds it to `sudo -S`; otherwise she falls back
/// to the standard macOS password window.
enum Admin {
    private static let lock = NSLock()
    private static var _password: String?
    private static var _since = Date.distantPast
    /// Forget the password after a while: it only lives in memory, never on disk.
    private static let keepFor: TimeInterval = 15 * 60

    static var password: String? {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(_since) > keepFor { _password = nil }
        return _password
    }

    static func remember(_ pw: String?) {
        lock.lock(); _password = pw; _since = Date(); lock.unlock()
    }

    /// Only administrators can use sudo.
    static let isAdminUser: Bool = {
        let groups = Shell.run("/usr/bin/id", ["-Gn"]).output.split(whereSeparator: { $0 == " " || $0 == "\n" })
        return groups.contains("admin")
    }()

    /// Checks the password with `sudo -v` (nothing is run).
    static func validate(_ pw: String) -> Bool {
        sudo(["-v"], password: pw).status == 0
    }

    struct Outcome { var ok: Bool; var cancelled: Bool; var output: String }

    /// Runs the script lines as root: with sudo when we have the password (keeps Full Disk Access),
    /// otherwise through the macOS password window.
    static func run(_ lines: [String], prompt: String) -> Outcome {
        let fm = FileManager.default
        let script = fm.temporaryDirectory.appendingPathComponent("suriclean-root-\(UUID().uuidString).sh")
        guard (try? (["#!/bin/bash"] + lines).joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)) != nil else {
            return Outcome(ok: false, cancelled: false, output: t("mac.err.script"))
        }
        _ = Shell.run("/bin/chmod", ["700", script.path])
        defer { try? fm.removeItem(at: script) }
        if let pw = password {
            let r = sudo(["/bin/bash", script.path], password: pw)
            if r.status == 0 { return Outcome(ok: true, cancelled: false, output: r.output) }
            if r.output.contains("incorrect password") || r.output.contains("Sorry, try again") || r.output.contains("password is required") {
                remember(nil)
            } else {
                return Outcome(ok: false, cancelled: false, output: r.output)
            }
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let cmd = ("/bin/bash " + q(script.path)).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = prompt.replacingOccurrences(of: "\"", with: "'")
        let r = Shell.run("/usr/bin/osascript", ["-e", "do shell script \"\(cmd)\" with administrator privileges with prompt \"\(p)\""], mergeStderr: true)
        return Outcome(ok: r.status == 0, cancelled: r.output.contains("-128"), output: r.output)
    }

    /// `sudo -S -k`: password from stdin (never on the command line), no cached ticket, no prompt text.
    private static func sudo(_ args: [String], password: String) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-S", "-k", "-p", ""] + args
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do { try p.run() } catch { return ShellResult(status: -1, output: error.localizedDescription) }
        input.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
        try? input.fileHandleForWriting.close()
        p.waitUntilExit()
        group.wait()
        return ShellResult(status: p.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
}
