import SwiftUI

enum Risk: Int, Codable {
    case safe, review, careful

    var label: String {
        switch self {
        case .safe: return t("mac.risk.safe")
        case .review: return t("mac.risk.review")
        case .careful: return t("mac.risk.careful")
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.mint
        case .review: return Theme.orange
        case .careful: return Theme.coral
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case size = "Più grandi"
    case date = "Più vecchi"
    case name = "Nome"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .size: return t("mac.sort.size")
        case .date: return t("mac.sort.date")
        case .name: return t("mac.sort.name")
        }
    }
}

struct CleanItem: Identifiable, Hashable, Codable {
    let id = UUID()
    var url: URL
    var name: String
    var detail: String
    var size: Int64
    var date: Date?
    var risk: Risk
    var recommended: Bool
    var badges: [String] = []
    var extraURLs: [URL] = []
    var copyText: String? = nil
    var group: Int? = nil
    var groupLabel: String? = nil
    var isGitRepo = false
    /// Empty for the current user, otherwise the account name the item belongs to.
    var owner = ""
}

extension Array where Element == CleanItem {
    var totalSize: Int64 { reduce(Int64(0)) { $0 + $1.size } }
}

enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case diskMap, caches, logsTemp, systemAreas, aiTools, devCaches, buildDeps, gitRepos, duplicates, appData
    case bigFiles, squeeze, installers, oldDownloads, apps, leftovers, appleExtras

    var id: String { rawValue }

    var title: String { t("mac.cat.\(rawValue).title") }

    var subtitle: String { t("mac.cat.\(rawValue).subtitle") }

    var explain: String { t("mac.cat.\(rawValue).explain") }

    var icon: String {
        switch self {
        case .diskMap: return "chart.pie.fill"
        case .appData: return "tray.full.fill"
        case .caches: return "wind"
        case .logsTemp: return "clock.arrow.circlepath"
        case .systemAreas: return "gearshape.2.fill"
        case .aiTools: return "brain.head.profile"
        case .devCaches: return "hammer.fill"
        case .buildDeps: return "shippingbox.fill"
        case .gitRepos: return "arrow.triangle.branch"
        case .duplicates: return "doc.on.doc.fill"
        case .bigFiles: return "externaldrive.fill"
        case .squeeze: return "arrow.down.right.and.arrow.up.left"
        case .installers: return "opticaldisc"
        case .oldDownloads: return "arrow.down.circle.fill"
        case .apps: return "moon.zzz.fill"
        case .leftovers: return "puzzlepiece.fill"
        case .appleExtras: return "iphone"
        }
    }

    var color: Color {
        switch self {
        case .diskMap: return Theme.lemon
        case .appData: return Theme.coral
        case .caches: return Theme.sky
        case .logsTemp: return Theme.lilac
        case .systemAreas: return Theme.sky
        case .aiTools: return Theme.pink
        case .devCaches: return Theme.orange
        case .buildDeps: return Theme.mint
        case .gitRepos: return Theme.coral
        case .duplicates: return Theme.lilac
        case .bigFiles: return Theme.pink
        case .squeeze: return Theme.lilac
        case .installers: return Theme.sky
        case .oldDownloads: return Theme.mint
        case .apps: return Theme.lilac
        case .leftovers: return Theme.orange
        case .appleExtras: return Theme.sky
        }
    }

    var risk: Risk {
        switch self {
        case .diskMap, .appData: return .careful
        case .caches, .logsTemp, .devCaches, .buildDeps, .installers: return .safe
        case .systemAreas, .squeeze: return .review
        case .aiTools, .gitRepos, .duplicates, .oldDownloads, .leftovers: return .review
        case .bigFiles, .apps, .appleExtras: return .careful
        }
    }

    var activity: MeerkatActivity {
        switch self {
        case .diskMap: return .digging
        case .caches, .leftovers, .appData: return .sniffing
        case .logsTemp: return .reading
        case .systemAreas: return .sweeping
        case .aiTools, .devCaches: return .hacking
        case .buildDeps, .bigFiles: return .digging
        case .gitRepos: return .reading
        case .duplicates: return .detective
        case .installers, .oldDownloads, .appleExtras, .squeeze: return .lookout
        case .apps: return .sleepy
        }
    }

    var scanTitle: String { t("mac.cat.\(rawValue).scan") }

    var needsIndex: Bool {
        switch self {
        case .buildDeps, .gitRepos, .duplicates, .bigFiles, .installers, .squeeze: return true
        default: return false
        }
    }

    var defaultSort: SortMode {
        switch self {
        case .apps, .oldDownloads: return .date
        default: return .size
        }
    }
}

struct BusyState {
    var activity: MeerkatActivity
    var title: String
    var detail: String = ""
    var progress: Double? = 0
    var foundCount: Int = 0
    var foundBytes: Int64 = 0
    var step: Int = 0
    var steps: Int = 1
}

struct Celebration: Identifiable {
    enum Kind { case trashed, emptied, info, squeezed }
    let id = UUID()
    var kind: Kind
    var bytes: Int64
    var failed: Int = 0
    var message: String = ""
}
