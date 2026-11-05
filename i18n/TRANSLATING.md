# Brief per chi traduce SuriClean

Sorgente: `i18n/it.json` (oggetto JSON piatto chiave → testo italiano, 1309 chiavi).
Output: `i18n/<codice>.json`, stesse chiavi identiche, valori tradotti.

SuriClean è un'app gratuita per liberare spazio su disco (Mac, Windows, Ubuntu, Android) con la mascotte
Suri, una suricata kawaii con gli occhioni. Il tono è giocoso, tenero, stile pubblicità giapponese:
esclamazioni, emoji, piccoli versi buffi. Adattalo in modo naturale per chi parla la lingua di arrivo
(in giapponese/cinese/coreano il kawaii è naturale; altrove resta allegro ma comprensibile).
Le spiegazioni di sicurezza (cosa viene cancellato, cosa è irreversibile, password, permessi) devono
restare chiarissime e precise: lì la chiarezza vince sul tono.

Regole:
- Non cambiare, aggiungere o togliere chiavi. Ogni valore deve essere tradotto (niente italiano rimasto,
  tranne ciò che segue).
- Segnaposto `{0}`, `{1}`… identici (stesso numero e stessi indici); puoi spostarli nella frase.
- Nei valori delle chiavi che finiscono in `_html` mantieni i tag HTML esattamente.
- Chiavi `….one` / `….other`: forma singolare (n = 1) e forma generale.
- Non tradurre: SuriClean, Suri, Suri-chan, nomi di prodotti/app (Claude, Codex, Cursor, VS Code, WhatsApp,
  Telegram, Shizuku, Time Machine, Finder, Spotlight, GarageBand, Xcode, npm, Homebrew, git, Docker…),
  percorsi di file, comandi da terminale, estensioni (.dmg, .apk…), unità (KB, MB, GB).
- Questi nomi di file sul disco restano in italiano, alla lettera: «SuriClean - repo rimossi.txt»,
  «SuriClean - backup git», «da leggere - come recuperare.txt».
- Le parole giapponesi decorative già presenti (es. ドドーン, スリちゃん, kira-kira, pika-pika, Yatta, Sugoi,
  Ganbarō, Arigatō, nyam) possono restare o essere adattate con l'equivalente buffo nella lingua.
- I nomi delle impostazioni di sistema (es. «Accesso completo al disco», «Accesso a tutti i file»,
  «Debug wireless», «Archiviazione › Cancella dati») vanno resi con il nome UFFICIALE che macOS/Android/Windows
  usa in quella lingua, se lo conosci con certezza.
- Usa l'ortografia standard; per il serbo l'alfabeto cirillico; zh-Hans = cinese semplificato,
  zh-Hant = tradizionale (Taiwan); nb = norvegese bokmål.

Procedura consigliata: carica `it.json` con Python, traduci a blocchi (es. per prefisso `mac.`, `and.`,
`web.`, `site.`), scrivi blocchi parziali e uniscili in `i18n/<codice>.json` (UTF-8, `ensure_ascii=False`,
indent 1, chiavi ordinate). Poi esegui `python3 i18n/merge.py` e correggi finché la riga della tua lingua
non riporta più chiavi mancanti o segnaposto sbagliati. Non modificare altri file e non fare commit.

## Aggiornamento: solo le chiavi nuove

Quando in `it.json` compaiono chiavi nuove, si traducono SOLO quelle che mancano in `i18n/<codice>.json`
(confronta le chiavi; `python3 i18n/merge.py` le elenca), lasciando intatte le traduzioni già presenti.
Termini di Schiaccia: «Schiaccia» è il nome dell'app (non si traduce); i livelli Carezza / Stretta / Martellata
vanno resi con parole tenere e buffe equivalenti (carezza leggera, stretta decisa, martellata energica).

## Testi legali (`legal.*`)

Termini d'uso, informativa privacy e consenso: qui la precisione vince sul tono kawaii.
- Rendi esattamente lo stesso significato giuridico: non aggiungere, togliere o attenuare obblighi, garanzie,
  esclusioni di responsabilità o manleve. Usa il lessico giuridico standard della lingua (come nelle licenze e nelle
  informative ufficiali), con frasi chiare e il «tu» informale già usato nell'app.
- «così com'è» («as is»): traduci «così com'è» e lascia «as is» in inglese tra parentesi.
- Lascia invariati: Marco Ricupero, SuriClean, Suri, Schiaccia, Shizuku, GitHub, GitHub Pages, MIT, URL e indirizzi
  (github.com/…, api.github.com), i nomi dei permessi già tradotti altrove nel file (riusa gli stessi termini).
- «Garante per la protezione dei dati personali»: è l'autorità italiana; lascia il nome italiano e, se serve,
  spiega tra parentesi che è l'autorità italiana; non sostituirlo con l'autorità del tuo paese.
- Mantieni i paragrafi (righe vuote, `\n\n`) e gli elenchi (righe che iniziano con «• ») nella stessa posizione.
