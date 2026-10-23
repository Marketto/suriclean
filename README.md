# 🐾 SuriClean

La suricata spazzina per il tuo Mac. App nativa SwiftUI per macOS 12 Monterey (l'ultima versione disponibile sul MacBook Air 2015).

## Download

🌸 **Sito:** https://marketto.github.io/suriclean/ · 📦 **[Ultima versione](../../releases/latest)**

| Sistema | File |
|---|---|
| macOS 12+ (Intel e Apple Silicon) | `SuriClean.dmg` |
| Windows 10/11 | `SuriClean-Windows-Setup.exe` |
| Ubuntu 22.04+ | `SuriClean-Linux.deb` oppure `SuriClean-Linux.AppImage` |

L'app controlla da sola se è uscita una versione nuova e si aggiorna (si può spegnere con l'interruttore «auto» nella barra laterale).

La versione Mac è nativa (SwiftUI). Quella per Windows e Ubuntu è fatta con [Tauri](https://tauri.app) (Rust + interfaccia web) e ha le stesse zone principali, Suri e la musica; le zone «App dormienti», «Avanzi di app» e «Backup iPhone» esistono solo su Mac.

## Installazione facile su Mac (DMG)

1. Scarica **SuriClean.dmg** dalla pagina [Releases](../../releases/latest).
2. Aprilo e trascina Suri nella cartella **Applicazioni**.
3. La prima volta fai **tasto destro sull'app › Apri › Apri**: l'app non è firmata da uno sviluppatore Apple, quindi macOS lo chiede una volta sola.
4. Concedi l'Accesso completo al disco (vedi il punto 5 più sotto).

Funziona su macOS 12 Monterey o successivi, sia su Mac Intel sia su Apple Silicon.

## Compilare da sé (5 minuti)

1. **Strumenti di Apple.** Se non hai Xcode, apri il Terminale e lancia `xcode-select --install`, poi premi «Installa».
   Pesano circa 1-2 GB. Se il disco è proprio pieno, prima svuota il Cestino o sposta qualcosa su un disco esterno.
2. **Compila.** Decomprimi lo zip, poi nel Terminale:
   ```bash
   cd ~/Downloads/SuriClean
   ./build.sh
   ```
3. **Installa e apri.**
   ```bash
   mv SuriClean.app /Applications/
   open /Applications/SuriClean.app
   ```
4. **Recupera lo spazio della compilazione** con `rm -rf .build` (sono circa 100-200 MB).
5. **Accesso completo al disco (consigliato).** Vai in Impostazioni di Sistema › Sicurezza e privacy › Privacy › Accesso completo al disco, aggiungi SuriClean e riapri l'app.
   Senza questo permesso Suri non vede i backup dell'iPhone, gli allegati di Mail e di Messaggi e alcune cache.
   Ogni volta che ricompili l'app, il permesso va ridato.

## Cosa trova

| Zona | Cosa c'è dentro | Preselezionato |
|---|---|---|
| Cache delle app | `~/Library/Caches`, cache di app Electron, browser e app sandbox | sì |
| Log e temporanei | Log, report dei crash, stati delle finestre, `$TMPDIR` più vecchio di 3 giorni | sì |
| Claude, Codex & AI | `~/.claude` (sessioni, file-history, snapshot…), `~/.codex`, Claude Desktop, Cursor, VS Code, Windsurf, Hugging Face, Ollama, LM Studio | solo cache e sessioni con più di 30 giorni |
| Cache da sviluppatore | Xcode DerivedData e DeviceSupport, npm, Yarn, pnpm, Bun, Gradle, Maven, Cargo, Go, CocoaPods, uv, Docker | cache sì, toolchain, archivi e VM no |
| Dipendenze ricreabili | `node_modules`, venv, `target`, `.build`, `Pods`, `.next`… | progetti fermi da più di 60 giorni |
| Repo Git dimenticati | Repo con remote, nessuna modifica locale, nessun commit non pushato, nessuno stash | al sicuro e fermi da più di 6 mesi |
| File gemelli | Duplicati da 1 MB in su, confermati con SHA-256 | tutte le copie tranne l'originale 💎 |
| File giganti | File da 100 MB in su, librerie Foto e Musica, macchine virtuali | no |
| Installer e .dmg | `.dmg`, `.pkg`, `.xip`, `.iso`, app lasciate nei Download | quelli in Download e Scrivania |
| Download dimenticati | Elementi nei Download da più di 90 giorni | no |
| App dormienti | App di terze parti con la data dell'ultimo uso; vengono rimosse insieme ai loro dati in Libreria | no |
| Avanzi di app rimosse | Cartelle in Libreria di app che non sono più installate | solo quelle in Caches |
| Backup iPhone & co. | Backup locali, aggiornamenti iOS, allegati di Mail e Messaggi, podcast | aggiornamenti e allegati di Mail |

Nella tana trovi anche:
- il **Cestino**, con il pulsante per svuotarlo;
- le **istantanee locali di Time Machine**, che puoi assottigliare;
- lo spazio **purgeable**;
- i **livelli di Suri**, che crescono con i GB che liberi.

## Sicurezza

- Suri non cancella mai niente direttamente: sposta tutto nel **Cestino**, quindi puoi ripensarci. Lo spazio torna libero davvero solo quando svuoti il Cestino.
- Per ogni repo git rimosso, il comando `git clone` per riaverlo viene salvato in `~/Documenti/SuriClean - repo rimossi.txt`. Puoi anche copiarlo dal pulsante 📋.
- Le cache si ricreano da sole, ma è meglio chiudere le app prima di pulirle.
- Le app installate dall'App Store o di proprietà dell'amministratore potrebbero rifiutarsi di essere spostate. In quel caso trascinale nel Cestino dal Finder.

## Musica e animazioni

La musica chiptune è sintetizzata in tempo reale (onde quadre, triangolo e rumore), senza file audio. Ogni azione ha il suo brano:
- una passeggiata tranquilla nella tana;
- uno scavo incalzante durante la scansione, che accelera mentre avanza;
- un tema da detective furtivo per i duplicati;
- uno sprint durante la pulizia;
- una fanfara alla fine.

Puoi silenziare la musica con ⌘M. ⌘R scansiona tutto.

Durante le scansioni Suri fa cose diverse:
- scava con la paletta;
- indaga con lente e cappello;
- legge il diario dei repo;
- smanetta al portatile tra le cache AI;
- dorme con la cuffietta cercando le app dormienti;
- fa la sentinella sulla collinetta;
- annusa le briciole;
- spazza con la scopa;
- festeggia con il cappellino da festa.
