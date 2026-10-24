package com.suriclean.app

import androidx.compose.ui.graphics.Color

enum class Risk(val label: String, val color: Color) {
    SAFE("Sicuro", Kawaii.mint),
    REVIEW("Da controllare", Kawaii.orange),
    CAREFUL("Con cautela", Kawaii.coral),
}

enum class Act { IDLE, WAVE, DIGGING, DETECTIVE, SWEEPING, READING, SLEEPY, SNIFFING, LOOKOUT, CELEBRATING }

enum class Category(
    val title: String,
    val subtitle: String,
    val explain: String,
    val emoji: String,
    val color: Color,
    val risk: Risk,
    val act: Act,
    val scanTitle: String,
    val viewOnly: Boolean = false,
) {
    MAP("Mappa della memoria", "Dove sono finiti tutti i GB? ☆",
        "Cartelle e file della memoria del telefono, dalla più grande (da 50 MB in su). Qui non si cancella niente: guarda e scopri i bestioni.",
        "🗺️", Kawaii.lemon, Risk.CAREFUL, Act.DIGGING, "Misuro tutta la tana, cm per cm! 📏", viewOnly = true),
    CHATS("WhatsApp & Telegram", "Video, vocali e foto ricevuti 📱",
        "Le cartelle dei media delle chat: video, foto, vocali, documenti, stati. Contengono ricordi veri: niente è preselezionato, tranne gli stati di WhatsApp già scaduti.",
        "💬", Kawaii.mint, Risk.REVIEW, Act.SNIFFING, "Kun-kun! Annuso le chat~ 💬"),
    DUPLICATES("File gemelli", "Gemellini identici, byte per byte ♡♡",
        "File da 1 MB in su confrontati con impronta SHA-256. In ogni gruppo tengo la copia «originale» (💎) e preseleziono le altre. Almeno una copia resta sempre.",
        "👯", Kawaii.lilac, Risk.REVIEW, Act.DETECTIVE, "Detective Suri in azione! 🔍"),
    BIG("File giganti", "I mostroni più ciccioni della tana!",
        "I file da 100 MB in su. Niente è preselezionato: decidi tu.",
        "🦖", Kawaii.pink, Risk.CAREFUL, Act.DIGGING, "Caccia ai mostri giganti! ドドーン"),
    DOWNLOADS("Download dimenticati", "Roba nei Download da più di 3 mesi",
        "Tutto ciò che sta nella cartella Download da più di 90 giorni. Nulla è preselezionato.",
        "📥", Kawaii.sky, Risk.REVIEW, Act.LOOKOUT, "Pattuglia dei Download, kira-kira ✧"),
    APKS("Installer APK", "Pacchetti di app già usati",
        "File .apk e .xapk rimasti in memoria. Preseleziono quelli nei Download: l'app, se l'hai installata, resta.",
        "📦", Kawaii.orange, Risk.SAFE, Act.LOOKOUT, "Sentinella Suri, occhi aperti! 👀"),
    JUNK("Spazzatura", "Miniature, cartelle vuote, log e cestini dimenticati",
        "Miniature delle foto che Android ricrea da solo, cartelle vuote, file di log e file temporanei. Tutto si può togliere senza pensieri.",
        "🧹", Kawaii.coral, Risk.SAFE, Act.SWEEPING, "Saa~ caccia alla polvere! 🧹"),
    APPS("App dormienti", "Fanno la nanna da secoli… zzz",
        "Le app installate con il loro peso e l'ultima volta che le hai aperte. Il pulsante apre la disinstallazione di Android, che chiede conferma app per app.",
        "😴", Kawaii.lilac, Risk.CAREFUL, Act.SLEEPY, "Shh~ cerco le app che fanno la nanna 💤"),
}

data class Item(
    val id: Long,
    val path: String,
    val name: String,
    val detail: String,
    val size: Long,
    val date: Long?,            // millis
    val risk: Risk,
    val recommended: Boolean,
    val badges: List<String> = emptyList(),
    val group: Int? = null,
    val groupLabel: String? = null,
    val packageName: String? = null,   // for apps
    val isDir: Boolean = false,
)

data class Busy(
    val act: Act,
    val title: String,
    val detail: String = "",
    val progress: Float? = 0f,
    val found: Int = 0,
    val foundBytes: Long = 0,
    val step: Int = 0,
    val steps: Int = 1,
)

data class Celebration(val title: String, val subtitle: String, val message: String = "", val offerEmptyTrash: Boolean = false)

data class AppUpdate(val version: String, val url: String)
