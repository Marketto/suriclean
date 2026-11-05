/* Legal notes for the desktop app (legal/README.md): one-time consent to the terms of use and privacy policy,
   and the «Note legali» window with Terms, Privacy and Licenses. Texts are the shared `legal.*` keys in i18n/;
   documents and license texts are bundled in ui/legal/ (copied at build time), so everything works offline.
   Exposes window.Legal: ensure() → Promise (resolves once accepted), open(tab), accepted. */
(function () {
  const T = window.__TAURI__;
  const invoke = (cmd, args) => T.core.invoke(cmd, args);
  const t = (k, ...a) => window.I18n.t(k, ...a);
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const LIC_FILES = { "MIT": "MIT.txt", "Apache-2.0": "Apache-2.0.txt", "MPL-2.0": "MPL-2.0.txt", "OFL-1.1": "OFL-1.1.txt" };
  const L = { accepted: false, version: "", parts: null, crates: null };

  const text = async path => { try { const r = await fetch(path); return r.ok ? await r.text() : ""; } catch (e) { return ""; } };
  const json = async (path, dflt) => { try { const r = await fetch(path); return r.ok ? await r.json() : dflt; } catch (e) { return dflt; } };

  async function loadVersion() {
    if (!L.version) L.version = ((await text("legal/VERSION")) || "1").trim();
    return L.version;
  }

  /* the Rust file is the source of truth; localStorage is the fallback (and a mirror) */
  async function acceptedVersion() {
    let v = "";
    try { v = (await invoke("legal_accepted")) || ""; } catch (e) {}
    if (!v) { try { v = localStorage.getItem("suri.legal.accepted") || ""; } catch (e) {} }
    return v;
  }
  async function remember(v) {
    try { await invoke("legal_accept", { version: v }); } catch (e) {}
    try { localStorage.setItem("suri.legal.accepted", v); localStorage.setItem("suri.legal.acceptedAt", new Date().toISOString()); } catch (e) {}
  }

  // ───────── formatting of the shared texts ─────────
  /* paragraphs separated by an empty line; lines starting with «• » become a list */
  function body(s) {
    return String(s || "").split(/\n\s*\n/).map(par => {
      const lines = par.split("\n");
      const bullets = lines.filter(l => l.startsWith("• "));
      if (!bullets.length) return `<p>${esc(par).replace(/\n/g, "<br>")}</p>`;
      const head = lines.filter(l => !l.startsWith("• ")).join(" ");
      return (head ? `<p>${esc(head)}</p>` : "") + `<ul>${bullets.map(b => `<li>${esc(b.slice(2))}</li>`).join("")}</ul>`;
    }).join("");
  }
  function doc(kind) {
    let out = `<h2>${esc(t(`legal.${kind}.title`))}</h2><p class="lg-upd">${esc(t("legal.updated", L.version))}</p>`;
    for (let i = 1; i < 40; i++) {
      const k = `legal.${kind}.s${i}.title`;
      if (t(k) === k) break;
      out += `<h4>${esc(t(k))}</h4>${body(t(`legal.${kind}.s${i}.body`))}`;
    }
    return out;
  }
  function licButtons(spdx) {
    return String(spdx || "").split(/\s+(?:OR|AND|\/)\s+|\s*\/\s*/).map(id => id.trim()).filter(Boolean).map(id =>
      LIC_FILES[id] ? `<button class="lg-lic" data-lic="${esc(id)}">${esc(id)}</button>` : `<span class="lg-lic plain">${esc(id)}</span>`).join(" ");
  }
  async function licenses() {
    if (!L.parts) L.parts = (await json("legal/third-party.json", [])).filter(e => (e.platforms || []).includes("desktop"));
    if (!L.crates) L.crates = await json("legal/rust-crates.json", []);
    const rows = L.parts.filter(e => !e.list).map(e => `<li><a href="#" data-url="${esc(e.url)}">${esc(e.name)}</a>
      <span class="lg-by">${esc(e.sameAuthor ? t("legal.lic.same_author") : t("legal.lic.by", e.by))}</span> ${licButtons(e.license)}</li>`).join("");
    const crates = L.crates.map(c => `<tr><td><a href="#" data-url="${esc(c.url)}">${esc(c.name)}</a></td><td>${esc(c.version)}</td><td>${licButtons(c.license)}</td></tr>`).join("");
    return `<h2>${esc(t("legal.lic.title"))}</h2><p>${esc(t("legal.lic.intro"))}</p>
      <ul class="lg-parts"><li><b>${esc(t("legal.lic.app"))}</b> <button class="lg-lic" data-lic="SURI">MIT</button>
        <a href="#" data-url="https://github.com/Marketto/suriclean">${esc(t("legal.lic.source"))}</a></li>${rows}</ul>
      ${L.crates.length ? `<details class="lg-crates"><summary>${esc(t("legal.lic.rust", L.crates.length))}</summary>
        <table><tbody>${crates}</tbody></table></details>` : ""}`;
  }

  // ───────── the «Note legali» window ─────────
  async function open(tab) {
    await loadVersion();
    document.querySelector("#legal-notes")?.remove();
    const ov = document.createElement("div"); ov.className = "ov legal-ov"; ov.id = "legal-notes";
    const tabs = [["terms", "legal.link.terms"], ["privacy", "legal.link.privacy"], ["licenses", "legal.link.licenses"]];
    ov.innerHTML = `<div class="card panel legal-panel" role="dialog" aria-modal="true" aria-label="${esc(t("legal.link.title"))}">
      <div class="lg-tabs">${tabs.map(([k, l]) => `<button data-lgtab="${k}">${esc(t(l))}</button>`).join("")}</div>
      <div class="lg-body" id="lg-body"></div>
      <div class="lg-foot"><button class="btn" style="--c:#A88FFA" data-lgclose>${esc(t("legal.close"))}</button></div></div>`;
    document.body.appendChild(ov);
    const show = async k => {
      ov.querySelectorAll("[data-lgtab]").forEach(b => b.classList.toggle("on", b.dataset.lgtab === k));
      const el = ov.querySelector("#lg-body");
      el.innerHTML = k === "licenses" ? await licenses() : doc(k);
      el.scrollTop = 0;
    };
    ov.addEventListener("click", async e => {
      const tb = e.target.closest("[data-lgtab]"); if (tb) return show(tb.dataset.lgtab);
      const a = e.target.closest("[data-url]"); if (a) { e.preventDefault(); try { await invoke("open_url", { url: a.dataset.url }); } catch (x) {} return; }
      const lb = e.target.closest("[data-lic]");
      if (lb) {
        const id = lb.dataset.lic;
        const txt = id === "SURI" ? await text("legal/LICENSE") : await text(`legal/licenses/${LIC_FILES[id]}`);
        const el = ov.querySelector("#lg-body");
        el.innerHTML = `<button class="lg-back" data-lgtab="licenses">‹ ${esc(t("legal.lic.title"))}</button>
          <h4>${esc(t("legal.lic.text"))} · ${esc(id === "SURI" ? "MIT · SuriClean" : id)}</h4><pre class="lg-pre" dir="ltr">${esc(txt)}</pre>`;
        el.scrollTop = 0;
        return;
      }
      if (e.target.closest("[data-lgclose]")) ov.remove();
    });
    await show(tab || "terms");
  }

  // ───────── one-time consent ─────────
  async function ensure() {
    const v = await loadVersion();
    const prev = await acceptedVersion();
    if (prev === v) { L.accepted = true; return; }
    return new Promise(resolve => {
      const ov = document.createElement("div"); ov.className = "ov legal-ov consent"; ov.id = "legal-consent";
      ov.innerHTML = `<div class="card panel legal-panel consent-panel" role="dialog" aria-modal="true" aria-labelledby="lg-ct">
        <div class="suri-ov" id="suri-legal" style="width:110px;height:130px"></div>
        <h3 id="lg-ct">${esc(t("legal.consent.title"))}</h3>
        ${prev ? `<p class="lg-upd">${esc(t("legal.consent.updated"))}</p>` : ""}
        <div class="lg-consent-text"><p>${esc(t("legal.consent.intro"))}</p>
          <ul>${["p1", "p2", "p3", "p4"].map(k => `<li>${esc(t(`legal.consent.${k}`))}</li>`).join("")}</ul></div>
        <div class="lg-links"><a href="#" data-open-legal="terms">${esc(t("legal.link.terms"))}</a> ·
          <a href="#" data-open-legal="privacy">${esc(t("legal.link.privacy"))}</a> ·
          <a href="#" data-open-legal="licenses">${esc(t("legal.link.licenses"))}</a></div>
        <label class="lg-check"><input type="checkbox" id="lg-ok"> <span>${esc(t("legal.consent.check"))}</span></label>
        <div class="lg-foot"><button class="btn" style="--c:#A88FFA" data-lgquit>${esc(t("legal.consent.decline"))}</button>
          <button class="btn big" style="--c:#61D6AD" data-lgaccept disabled>${esc(t("legal.consent.accept"))}</button></div></div>`;
      document.body.appendChild(ov);
      try { window.Suri && Suri.mount(ov.querySelector("#suri-legal"), "wave"); } catch (e) {}
      const ok = ov.querySelector("#lg-ok"), acc = ov.querySelector("[data-lgaccept]");
      ok.addEventListener("change", () => { acc.disabled = !ok.checked; });
      ov.addEventListener("click", async e => {
        const l = e.target.closest("[data-open-legal]"); if (l) { e.preventDefault(); return open(l.dataset.openLegal); }
        if (e.target.closest("[data-lgquit]")) { try { await invoke("quit_app"); } catch (x) { window.close(); } return; }
        if (e.target.closest("[data-lgaccept]") && ok.checked) {
          await remember(v);
          L.accepted = true; ov.remove(); resolve();
        }
      });
      // nothing behind the window can be used until the terms are accepted
      ov.addEventListener("keydown", e => { if (e.key === "Escape") e.preventDefault(); });
    });
  }

  window.Legal = { ensure, open, get accepted() { return L.accepted; } };
})();
