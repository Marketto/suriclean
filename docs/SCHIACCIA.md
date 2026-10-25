# SuriClean × Schiaccia

SuriClean propone di alleggerire PDF, foto JPG e video con il motore di **Schiaccia**
([pdf-tiny-tools](https://github.com/Marketto/pdf-tiny-tools)). Il motore resta in un solo posto, nel repo di
Schiaccia; SuriClean ne include una copia a ogni build e lo usa offline.

## Il modulo `motore.js` (repo pdf-tiny-tools)

Script classico, senza build né dipendenze, caricato dopo `config.js`. Lo usa anche la pagina di Schiaccia,
così il motore è uno solo.

```js
window.Motore = {
  version,                       // la VERSION di Schiaccia
  setBase(url),                  // cartella da cui caricare engine.js e vendor/ (predefinita "./")
  levels: ["soft", "mid", "hard"], // Carezza, Stretta, Martellata (CONFIG.levels)
  kindOf(nameOrFile),            // "pdf" | "jpg" | "video" | null
  canVideo(): Promise<boolean>,  // il browser sa codificare video?
  squeeze(file, { level, onPct, signal }): Promise<{
    status: "done" | "same" | "err",   // done = più leggero; same = non conviene; err = illeggibile
    blob,                              // solo con status "done": il file leggero (stesso tipo; WebM/MKV → MP4)
    name,                              // nome del risultato (cambia solo per WebM/MKV → .mp4)
    note                               // motivo di same/err: noGain, noImages, locked, unreadable, hdr, tooBig, noVideo
  }>
};
```

- `file` è un `File` (serve il nome per capire il tipo).
- `onPct(0…100)` dà l'avanzamento; `signal` (AbortSignal) ferma il lavoro.
- Stesse regole di Schiaccia: soglie di guadagno, livelli, metadati delle foto, misura della qualità dei video.
- I file non lasciano mai il dispositivo; nessuna chiamata di rete.

## Come lo usa SuriClean

- **Zona «Da schiacciare»**: PDF, JPG e video abbastanza grandi trovati nella scansione. Si sceglie il tipo
  (PDF, foto, video), il livello e i file; «Schiaccia!» li alleggerisce uno dopo l'altro.
- **Originali**: il file leggero prende il posto dell'originale, che va nel Cestino (recuperabile).
- **Animazione**: Suri porta i file alla pressa, la mascotte di Schiaccia li schiaccia.
- **Dove gira il motore**
  - Windows / Ubuntu: nella webview di Tauri. Se la webview non sa codificare video (WebKitGTK), i video
    non vengono proposti.
  - Android: in una WebView interna, con i file letti e scritti tramite l'app.
  - Mac: PDF e foto in una WKWebView interna; i video con l'encoder HEVC/H.264 di macOS
    (Safari 15 di Monterey non sa codificare video), con gli stessi livelli.
- **Build**: la CI clona pdf-tiny-tools e copia `motore.js`, `engine.js`, `config.js`, `vendor/pdf-lib.min.js`
  e `vendor/mediabunny.min.mjs` (con licenza) nel pacchetto di ogni piattaforma.
