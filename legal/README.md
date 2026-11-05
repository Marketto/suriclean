# Note legali in SuriClean

Fonte unica dei testi: chiavi `legal.*` in `i18n/` (italiano in `i18n/src/legal.it.json`), uguali per tutte le app e
per il sito. `scripts/legal-docs.py` ne ricava `TERMS.md`, `PRIVACY.md`, `THIRD-PARTY.md`.

- `VERSION`: data dei documenti in vigore (es. `2026-11-04`). Quando cambia, ogni app chiede di nuovo l'accettazione.
- `third-party.json`: componenti inclusi (`name`, `by`, `copyright?`, `license`, `url`, `platforms`, `sameAuthor?`,
  `list?`); ogni app mostra solo quelli della sua piattaforma (`mac`, `desktop`, `android`, `site`).
- `licenses/`: testi completi originali (MIT, Apache-2.0, MPL-2.0, OFL-1.1), mostrati come sono (in inglese).
- `rust-crates.json` (generato in CI da `scripts/rust-licenses.py`, non nel repo): tutte le crate Rust dell'app desktop.

## Cosa fa ogni app

1. **Accettazione al primo avvio** (e quando `VERSION` cambia): finestra modale non chiudibile con `legal.consent.*`
   (titolo, intro, punti p1–p4), link «Termini d'uso» e «Privacy» che aprono i testi completi, casella
   `legal.consent.check` obbligatoria, pulsanti «Accetto» (attivo solo con la casella) ed «Esci» (chiude l'app).
   Salva sul dispositivo la `VERSION` accettata e la data. Se l'accettazione era di una versione precedente, mostra in
   più `legal.consent.updated`. Niente scansioni né operazioni finché non si accetta (gli helper senza interfaccia,
   come la modalità root del Mac, non chiedono nulla).
2. **Note legali sempre raggiungibili**: un piccolo link «Note legali» (`legal.link.title`) in fondo alla barra
   laterale / alla tana, che apre una vista con tre schede: Termini d'uso, Privacy, Licenze.
   - Termini e Privacy: titolo, «Ultimo aggiornamento: VERSION», sezioni `legal.<terms|privacy>.s1…sN`
     (`.title`, `.body`; paragrafi separati da riga vuota, righe che iniziano con «• » come elenco).
   - Licenze: `legal.lic.intro`, riga SuriClean (`legal.lic.app` + testo MIT da `LICENSE`), poi i componenti della
     piattaforma da `third-party.json` (nome, «di …», licenza, link al sorgente) e, per il desktop, l'elenco di
     `rust-crates.json`; toccando una licenza si apre il suo testo completo da `licenses/`.
3. **Pacchetto**: ogni app include `legal/VERSION`, `legal/third-party.json`, `legal/licenses/*`, il `LICENSE` del
   repo e (desktop) `rust-crates.json`. Tutto offline.
