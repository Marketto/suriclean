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
