import SwiftUI

enum Risk: Int {
    case safe, review, careful

    var label: String {
        switch self {
        case .safe: return "Sicuro"
        case .review: return "Da controllare"
        case .careful: return "Con cautela"
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
}

struct CleanItem: Identifiable, Hashable {
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
}

extension Array where Element == CleanItem {
    var totalSize: Int64 { reduce(Int64(0)) { $0 + $1.size } }
}

enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case diskMap, caches, logsTemp, aiTools, devCaches, buildDeps, gitRepos, duplicates, appData
    case bigFiles, installers, oldDownloads, apps, leftovers, appleExtras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diskMap: return "Mappa del disco"
        case .appData: return "Dati delle app"
        case .caches: return "Cache delle app"
        case .logsTemp: return "Log e temporanei"
        case .aiTools: return "Claude, Codex & AI"
        case .devCaches: return "Cache da sviluppatore"
        case .buildDeps: return "Dipendenze ricreabili"
        case .gitRepos: return "Repo Git dimenticati"
        case .duplicates: return "File gemelli"
        case .bigFiles: return "File giganti"
        case .installers: return "Installer e .dmg"
        case .oldDownloads: return "Download dimenticati"
        case .apps: return "App dormienti"
        case .leftovers: return "Avanzi di app rimosse"
        case .appleExtras: return "Backup iPhone & co."
        }
    }

    var subtitle: String {
        switch self {
        case .diskMap: return "Dove sono finiti tutti i GB? Scopriamolo ☆"
        case .appData: return "Le app più golose di spazio, nyam~"
        case .caches: return "Briciole magiche che ricrescono da sole ✧"
        case .logsTemp: return "Diari di bordo e roba usa-e-getta"
        case .aiTools: return "Le briciole dei tuoi amici robot 🤖"
        case .devCaches: return "npm, Xcode, Gradle, Cargo, Go…"
        case .buildDeps: return "node_modules, venv, target… di progetti fermi"
        case .gitRepos: return "Progetti fermi che puoi riclonare"
        case .duplicates: return "Gemellini identici, byte per byte ♡♡"
        case .bigFiles: return "I mostroni più ciccioni della tana!"
        case .installers: return "Immagini disco e pacchetti già usati"
        case .oldDownloads: return "Roba nei Download da più di 3 mesi"
        case .apps: return "Fanno la nanna da secoli… zzz"
        case .leftovers: return "Dati di app che non esistono più"
        case .appleExtras: return "Backup, aggiornamenti iOS, allegati"
        }
    }

    var explain: String {
        switch self {
        case .diskMap:
            return "Tutto quello che occupa spazio nella tua cartella Inizio e in Applicazioni, cartella per cartella (da 300 MB in su). Qui non si cancella niente: guarda, scopri i bestioni e aprili nel Finder. Il resto del disco usato è macOS stesso, la memoria virtuale e gli altri utenti."
        case .appData:
            return "Le cartelle di dati più grosse delle app: WhatsApp, Telegram, Steam, Spotify, Adobe, Mail… Contengono dati veri (chat, giochi, musica offline): niente è preselezionato. Spesso conviene svuotarle dall'app stessa."
        case .caches:
            return "Le cache servono solo a velocizzare: se le togli, le app le ricreano quando servono. Meglio chiudere le app prima di pulire."
        case .logsTemp:
            return "Log, report di crash, stati delle finestre e file temporanei vecchi di qualche giorno. Nessuno ne sentirà la mancanza."
        case .aiTools:
            return "Cronologie di sessione di Claude Code e Codex, cache di Claude Desktop, Cursor e VS Code, modelli scaricati (Hugging Face, Ollama, LM Studio). Le sessioni recenti non sono preselezionate."
        case .devCaches:
            return "Pacchetti scaricati da npm, Yarn, pnpm, Gradle, Maven, Cargo, Go e i DerivedData di Xcode. Tutto si riscarica al prossimo build."
        case .buildDeps:
            return "Cartelle che si rigenerano con un comando (npm install, pip install, cargo build…). Preseleziono quelle di progetti fermi da più di 60 giorni."
        case .gitRepos:
            return "Per ogni repo controllo remote, modifiche non salvate, commit non pushati e stash. Preseleziono solo quelli al sicuro sul remote e fermi da 6+ mesi. Il comando git clone di ogni repo rimosso viene salvato in Documenti."
        case .duplicates:
            return "File da 1 MB in su confrontati con impronta SHA-256. In ogni gruppo tengo la copia «originale» (💎) e preseleziono le altre. Nota: i cloni APFS sembrano doppi ma non occupano spazio due volte."
        case .bigFiles:
            return "I file da 100 MB in su e le librerie (Foto, Musica, macchine virtuali). Niente è preselezionato: decidi tu."
        case .installers:
            return "File .dmg, .pkg, .xip, .iso e app lasciate nei Download. Preseleziono quelli in Download e Scrivania."
        case .oldDownloads:
            return "Tutto ciò che sta nei Download da più di 90 giorni. Nulla è preselezionato."
        case .apps:
            return "App di terze parti con la data di ultimo utilizzo (da Spotlight). Rimuovendo un'app sposto nel Cestino anche le sue preferenze, cache e dati di supporto."
        case .leftovers:
            return "Cartelle in Libreria che appartengono ad app non più installate. Ricontrolla prima di eliminare: alcune potrebbero servire ad app su dischi esterni."
        case .appleExtras:
            return "Backup locali di iPhone/iPad, aggiornamenti iOS scaricati da Finder/iTunes, allegati di Mail già aperti. I backup non sono mai preselezionati."
        }
    }

    var icon: String {
        switch self {
        case .diskMap: return "chart.pie.fill"
        case .appData: return "tray.full.fill"
        case .caches: return "wind"
        case .logsTemp: return "clock.arrow.circlepath"
        case .aiTools: return "brain.head.profile"
        case .devCaches: return "hammer.fill"
        case .buildDeps: return "shippingbox.fill"
        case .gitRepos: return "arrow.triangle.branch"
        case .duplicates: return "doc.on.doc.fill"
        case .bigFiles: return "externaldrive.fill"
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
        case .aiTools: return Theme.pink
        case .devCaches: return Theme.orange
        case .buildDeps: return Theme.mint
        case .gitRepos: return Theme.coral
        case .duplicates: return Theme.lilac
        case .bigFiles: return Theme.pink
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
        case .aiTools, .gitRepos, .duplicates, .oldDownloads, .leftovers: return .review
        case .bigFiles, .apps, .appleExtras: return .careful
        }
    }

    var activity: MeerkatActivity {
        switch self {
        case .diskMap: return .digging
        case .caches, .leftovers, .appData: return .sniffing
        case .logsTemp: return .reading
        case .aiTools, .devCaches: return .hacking
        case .buildDeps, .bigFiles: return .digging
        case .gitRepos: return .reading
        case .duplicates: return .detective
        case .installers, .oldDownloads, .appleExtras: return .lookout
        case .apps: return .sleepy
        }
    }

    var scanTitle: String {
        switch self {
        case .diskMap: return "Misuro tutta la tana, cm per cm! 📏"
        case .appData: return "Chi è l'app più golosa? Nyam~ 🍰"
        case .caches: return "Snif snif! Caccia alle cache~ ☆"
        case .logsTemp: return "Sfoglio i log, piku-piku! 📜"
        case .aiTools: return "Bip-bup! Missione robot AI ☆"
        case .devCaches: return "Tic-tac! Hacker mode ON 💻"
        case .buildDeps: return "Scava-scava nei node_modules! ⛏️"
        case .gitRepos: return "Leggo i diari segreti dei repo ♡"
        case .duplicates: return "Detective Suri in azione! 🔍"
        case .bigFiles: return "Caccia ai mostri giganti! ドドーン"
        case .installers: return "Sentinella Suri, occhi aperti! 👀"
        case .oldDownloads: return "Pattuglia dei Download, kira-kira ✧"
        case .apps: return "Shh~ cerco le app che fanno la nanna 💤"
        case .leftovers: return "Fiuto le briciole delle app perdute~"
        case .appleExtras: return "Controllo i tesori dell'iPhone ☆"
        }
    }

    var needsIndex: Bool {
        switch self {
        case .buildDeps, .gitRepos, .duplicates, .bigFiles, .installers: return true
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
    enum Kind { case trashed, emptied, info }
    let id = UUID()
    var kind: Kind
    var bytes: Int64
    var failed: Int = 0
    var message: String = ""
}
