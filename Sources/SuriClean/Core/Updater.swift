import Foundation
import AppKit

struct UpdateInfo: Equatable {
    let version: String
    let notes: String
    let dmgURL: URL
    let pageURL: URL
}

/// Checks GitHub Releases for a newer SuriClean, downloads the DMG and swaps the app bundle.
enum Updater {
    static let latestAPI = URL(string: "https://api.github.com/repos/Marketto/suriclean/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// "1.12" > "1.9" (numeric, component by component).
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func check() async -> UpdateInfo? {
        var req = URLRequest(url: latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("SuriClean/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(version, than: currentVersion) else { return nil }
        guard let asset = assets.first(where: { ($0["name"] as? String) == "SuriClean.dmg" }),
              let s = asset["browser_download_url"] as? String, let dmg = URL(string: s),
              dmg.host == "github.com" || dmg.host?.hasSuffix(".githubusercontent.com") == true else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/Marketto/suriclean/releases")!
        return UpdateInfo(version: version, notes: json["body"] as? String ?? "", dmgURL: dmg, pageURL: page)
    }

    /// Downloads the DMG and copies the new app into a staging folder. Returns the staged .app.
    static func stage(_ info: UpdateInfo) async throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("SuriClean-update-\(info.version)", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let (tmp, resp) = try await URLSession.shared.download(from: info.dmgURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw err(t("mac.upd.err.download")) }
        let dmg = work.appendingPathComponent("SuriClean.dmg")
        try fm.moveItem(at: tmp, to: dmg)
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let a = Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noverify", "-noautoopen", "-mountpoint", mount.path], mergeStderr: true)
        guard a.status == 0 else { throw err(t("mac.upd.err.mount", a.output)) }
        defer { _ = Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let src = mount.appendingPathComponent("SuriClean.app")
        guard fm.fileExists(atPath: src.path) else { throw err(t("mac.upd.err.missing")) }
        let staged = work.appendingPathComponent("SuriClean.app")
        let c = Shell.run("/usr/bin/ditto", [src.path, staged.path], mergeStderr: true)
        guard c.status == 0 else { throw err(t("mac.upd.err.copy", c.output)) }
        _ = Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        // make sure it's really our app and newer
        guard let b = Bundle(url: staged), b.bundleIdentifier == Bundle.main.bundleIdentifier,
              let v = b.infoDictionary?["CFBundleShortVersionString"] as? String, isNewer(v, than: currentVersion) else {
            throw err(t("mac.upd.err.invalid"))
        }
        return staged
    }

    /// Where the running app lives (if macOS "translocated" it, fall back to /Applications).
    static var installTarget: URL {
        let here = Bundle.main.bundleURL
        if here.path.contains("/AppTranslocation/") {
            return URL(fileURLWithPath: "/Applications/SuriClean.app")
        }
        return here
    }

    /// Replaces the app once this process exits; optionally relaunches it.
    static func apply(staged: URL, relaunch: Bool) {
        let target = installTarget
        let pid = ProcessInfo.processInfo.processIdentifier
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let old = target.path + ".old"
        var script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf \(q(old))
        if mv \(q(target.path)) \(q(old)) && mv \(q(staged.path)) \(q(target.path)); then rm -rf \(q(old)); else [ -d \(q(old)) ] && mv \(q(old)) \(q(target.path)); fi
        """
        if relaunch { script += "\nopen \(q(target.path))" }
        let scriptURL = staged.deletingLastPathComponent().appendingPathComponent("install.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let parentWritable = FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: target.path)
        let p = Process()
        if parentWritable {
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [scriptURL.path]
        } else {
            // e.g. a standard (non-admin) account: ask for the password once
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "do shell script \"/bin/bash \(scriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")) > /dev/null 2>&1 &\" with administrator privileges"]
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private static func err(_ s: String) -> NSError {
        NSError(domain: "SuriClean.Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }

    /// Set by the model when an update is staged; run at quit time.
    static var pendingApply: (() -> Void)?
}
