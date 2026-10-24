# Traduzioni di SuriClean

Un file JSON piatto per lingua (`it.json`, `en.json`, `ja.json`…), condiviso da tutte le piattaforme.
Le chiavi hanno un prefisso per piattaforma: `mac.` (SwiftUI), `and.` (Android), `web.` (Windows/Ubuntu, Tauri), `site.` (pagina web).

- `it.json` è la fonte: si scrive prima lì, poi si traduce.
- `src/<piattaforma>.it.json` sono i pezzi da cui nasce `it.json` (`python3 i18n/merge.py`).
- Segnaposto posizionali `{0}`, `{1}`… da lasciare identici in ogni lingua.
- Plurali: chiavi `….one` / `….other` (si usa `.one` quando il numero è 1).
- Lingua scelta: quella del sistema (miglior corrispondenza con `languages.json`), cambiabile da un menu.
  Se manca una chiave si usa l'inglese, poi l'italiano.
- `rtl: true` (arabo, ebraico) gira l'interfaccia da destra a sinistra.
- Lo stile è kawaii come in italiano, adattato a ogni lingua; i nomi propri (Suri, SuriClean, Shizuku, Claude…) non si traducono.
