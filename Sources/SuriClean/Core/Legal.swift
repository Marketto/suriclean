import Foundation

/// Terms, privacy and third-party licenses (legal/README.md). Texts come from the `legal.*` i18n keys;
/// the version, the component list and the full license texts from Resources/legal/.
enum Legal {
    struct Component: Identifiable, Hashable {
        let name: String
        let by: String
        let copyright: String?
        let license: String
        let url: String
        let sameAuthor: Bool
        var id: String { name }
    }

    struct Section: Identifiable, Hashable {
        let title: String
        let body: String
        var id: String { title }
    }

    private static let acceptedKey = "suri.legal.accepted"
    private static let acceptedDateKey = "suri.legal.acceptedDate"

    static var dir: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("legal"), FileManager.default.fileExists(atPath: r.path) { return r }
        // `swift run` / development: the repo's legal folder
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("legal")
        return FileManager.default.fileExists(atPath: cwd.path) ? cwd : nil
    }

    /// Date of the documents in force (legal/VERSION), e.g. "2026-11-04".
    static let version: String = {
        guard let u = dir?.appendingPathComponent("VERSION"), let s = try? String(contentsOf: u, encoding: .utf8) else { return "1" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var acceptedVersion: String? { UserDefaults.standard.string(forKey: acceptedKey) }

    /// The documents in force have been accepted on this Mac.
    static var isAccepted: Bool { acceptedVersion == version }

    /// An older version was accepted: the documents changed since.
    static var isUpdate: Bool { acceptedVersion != nil && !isAccepted }

    static func accept() {
        UserDefaults.standard.set(version, forKey: acceptedKey)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: acceptedDateKey)
    }

    /// Sections legal.<kind>.s1…sN (kind = "terms" or "privacy").
    static func sections(_ kind: String) -> [Section] {
        var out: [Section] = []
        var i = 1
        while true {
            let tk = "legal.\(kind).s\(i).title", bk = "legal.\(kind).s\(i).body"
            let title = t(tk), body = t(bk)
            if title == tk || body == bk { break }
            out.append(Section(title: title, body: body))
            i += 1
        }
        return out
    }

    /// Components bundled in the Mac app (third-party.json, platform "mac").
    static let components: [Component] = {
        guard let u = dir?.appendingPathComponent("third-party.json"), let d = try? Data(contentsOf: u),
              let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return list.compactMap { e in
            guard let plats = e["platforms"] as? [String], plats.contains("mac"),
                  let name = e["name"] as? String, let lic = e["license"] as? String else { return nil }
            return Component(name: name, by: (e["by"] as? String) ?? "", copyright: e["copyright"] as? String,
                             license: lic, url: (e["url"] as? String) ?? "", sameAuthor: (e["sameAuthor"] as? Bool) ?? false)
        }
    }()

    /// SuriClean's own license (the repo's LICENSE).
    static var appLicense: String { read("LICENSE") ?? read("licenses/MIT.txt") ?? "MIT License" }

    /// Full original text(s) of a license expression such as "MIT", "MPL-2.0" or "MIT OR Apache-2.0".
    static func licenseText(_ expr: String, copyright: String? = nil) -> String {
        let ids = expr.components(separatedBy: " OR ").map { $0.trimmingCharacters(in: .whitespaces) }
        let texts: [String] = ids.compactMap { id in
            guard var s = read("licenses/\(id).txt") else { return nil }
            if id == "MIT", let c = copyright { s = s.replacingOccurrences(of: "Copyright (c) <year> <copyright holders>", with: c) }
            return s
        }
        return texts.isEmpty ? expr : texts.joined(separator: "\n\n――――――――――\n\n")
    }

    private static func read(_ rel: String) -> String? {
        guard let u = dir?.appendingPathComponent(rel) else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }
}
