# SuriClean × Schiaccia

SuriClean propone di alleggerire PDF, foto JPG e video con il motore di **Schiaccia**
([pdf-tiny-tools](https://github.com/Marketto/pdf-tiny-tools)). Il motore resta in un solo posto, nel repo di
Schiaccia; SuriClean ne include una copia a ogni build e lo usa offline.

## Il modulo `motore.js` (Schiaccia ≥ 4.1.0, R-APP-20)

Script classico, senza build, caricato dopo `config.js`; lo usa anche la pagina di Schiaccia.

```js
window.Motore = {
  version,                         // "4.1.0"
  setBase(url),                    // cartella di engine.js e vendor/ (predefinita: quella di motore.js)
  levels: ["soft", "mid", "hard"], // Carezza, Stretta, Martellata (CONFIG.levels)
  kindOf(nameOrFile),              // "pdf" | "jpg" | "video" | null
  canVideo(): Promise<boolean>,    // il browser sa codificare video?
  squeeze(file, { level, onPct, signal, recall, remember }): Promise<{
    status,   // "done" (più leggero) | "same" (non conviene) | "err"
    blob,     // solo con "done"
    name,     // nome del risultato (WebM/MKV → .mp4)
    note,     // noGain, noGainV, noImages, locked, unreadable, hdr, tooBig, noVideo, noCodec, aborted, doneBefore
    plan,     // solo video completati
    release   // da chiamare dopo aver salvato il risultato (cancella i temporanei dei video grandi)
  }>
};
```

`file` è un `File` (serve il nome). `recall`/`remember` (facoltativi) sono la memoria delle analisi video.
Nessuna chiamata di rete, a parte il caricamento dei propri file dalla base.

## Come lo usa SuriClean

- **Zona «Da schiacciare»**: PDF, JPG e video abbastanza grandi trovati nella scansione. Si sceglie il tipo
  (PDF, foto, video), il livello e i file; «Schiaccia!» li alleggerisce uno dopo l'altro.
- **Originali**: il file leggero prende il posto dell'originale, che va nel Cestino (recuperabile).
- **Animazione «Il corriere»** (scelta A): Suri corre con il file (icona PDF/JPG/video), lo lancia sotto la pressa
  di Schiaccia (`schiaccia/press.svg`, disegnata dalla fonte unica della mascotte), la testa della pressa scende e
  il file appiattito vola via con il risparmio («−62% ✨»); in alto file n di N e totale risparmiato; «Annulla».
- **Dove gira il motore**
  - Windows / Ubuntu: nella webview di Tauri. Se la webview non sa codificare video (WebKitGTK), i video
    non vengono proposti.
  - Android: in una WebView interna, con i file letti e scritti tramite l'app.
  - Mac: PDF e foto in una WKWebView interna; i video con l'encoder HEVC/H.264 di macOS
    (Safari 15 di Monterey non sa codificare video), con gli stessi livelli.
- **Build**: `scripts/fetch-schiaccia.sh` (in CI per ogni piattaforma, e in locale) crea `./schiaccia/` con
  `motore.js`, `engine.js`, `config.js`, `VERSION`, `vendor/pdf-lib.min.js`, `vendor/mediabunny.min.mjs` (+ licenza)
  e `press.svg`; ogni piattaforma lo mette nel suo pacchetto. La cartella non è nel repo (`.gitignore`).
