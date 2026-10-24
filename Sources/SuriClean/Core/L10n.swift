import Foundation

/// Translations: flat JSON files (Resources/i18n/<code>.json) shared with the other platforms.
/// See i18n/README.md. Safe to use from any thread and in helper mode.
final class L10n {
    static let shared = L10n()

    struct Language: Hashable {
        let code: String
        let name: String
        let rtl: Bool
    }

    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]
    private(set) var languages: [Language] = []
    private var _code = "it"

    /// The language in use right now.
    var code: String {
        lock.lock(); defer { lock.unlock() }
        return _code
    }

    /// The language chosen by hand, nil when following the system.
    var chosen: String? { UserDefaults.standard.string(forKey: "suri.lang") }

    var isRTL: Bool { languages.first(where: { $0.code == code })?.rtl ?? false }

    var nativeName: String { languages.first(where: { $0.code == code })?.name ?? code }

    var locale: Locale { Locale(identifier: code) }

    private init() {
        if let url = L10n.dir?.appendingPathComponent("languages.json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            languages = list.compactMap { d in
                guard let c = d["code"] as? String, let n = d["name"] as? String else { return nil }
                return Language(code: c, name: n, rtl: (d["rtl"] as? Bool) ?? false)
            }
        }
        if languages.isEmpty { languages = [Language(code: "it", name: "Italiano", rtl: false)] }
        _code = resolve(chosen)
    }

    private static var dir: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("i18n"), FileManager.default.fileExists(atPath: r.path) { return r }
        // `swift run` / development: the repo's i18n folder next to the executable's package
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("i18n")
        return FileManager.default.fileExists(atPath: cwd.path) ? cwd : nil
    }

    /// nil = automatic (system language).
    func set(code: String?) {
        if let c = code { UserDefaults.standard.set(c, forKey: "suri.lang") } else { UserDefaults.standard.removeObject(forKey: "suri.lang") }
        let r = resolve(code)
        lock.lock(); _code = r; lock.unlock()
    }

    /// Use this language for this process only (helper mode gets it from the app).
    func use(code: String) {
        let r = resolve(code)
        lock.lock(); _code = r; lock.unlock()
    }

    private func resolve(_ wanted: String?) -> String {
        let codes = Set(languages.map { $0.code })
        if let w = wanted, codes.contains(w) { return w }
        for pref in Locale.preferredLanguages {
            if let c = match(pref, codes) { return c }
        }
        return codes.contains("en") ? "en" : "it"
    }

    private func match(_ pref: String, _ codes: Set<String>) -> String? {
        let parts = pref.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let lang = parts.first?.lowercased() else { return nil }
        if lang == "zh" {
            let rest = parts.dropFirst().map { $0.lowercased() }
            if rest.contains("hant") || rest.contains("tw") || rest.contains("hk") || rest.contains("mo") { return codes.contains("zh-Hant") ? "zh-Hant" : nil }
            return codes.contains("zh-Hans") ? "zh-Hans" : nil
        }
        if lang == "no" || lang == "nn" || lang == "nb" { return codes.contains("nb") ? "nb" : nil }
        if lang == "iw" { return codes.contains("he") ? "he" : nil }
        return codes.contains(lang) ? lang : nil
    }

    private func table(_ code: String) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let t = tables[code] { return t }
        var t: [String: String] = [:]
        if let url = L10n.dir?.appendingPathComponent("\(code).json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            t = obj
        }
        tables[code] = t
        return t
    }

    func string(_ key: String) -> String {
        for c in [code, "en", "it"] {
            if let s = table(c)[key] { return s }
        }
        return key
    }
}

/// Translated text for `key`, with {0}, {1}… replaced by `args`.
func t(_ key: String, _ args: CustomStringConvertible...) -> String {
    fill(L10n.shared.string(key), args)
}

/// Plural: uses `keyBase.one` when n == 1, else `keyBase.other`. {0} is usually n itself.
func tp(_ keyBase: String, _ n: Int, _ args: CustomStringConvertible...) -> String {
    fill(L10n.shared.string(keyBase + (n == 1 ? ".one" : ".other")), args)
}

private func fill(_ s: String, _ args: [CustomStringConvertible]) -> String {
    guard !args.isEmpty else { return s }
    var out = s
    for (i, a) in args.enumerated() {
        out = out.replacingOccurrences(of: "{\(i)}", with: a.description)
    }
    return out
}
