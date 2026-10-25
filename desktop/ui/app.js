/* SuriClean desktop UI (Windows / Linux). Talks to the Rust backend through Tauri. */
(function () {
  const T = window.__TAURI__;
  const invoke = (cmd, args) => T.core.invoke(cmd, args);
  const $ = sel => document.querySelector(sel);
  const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // ───────── categories ─────────
  const C = {
    pink: "#FF80A8", coral: "#FF786E", orange: "#FFA85C", lemon: "#FFD14D", mint: "#61D6AD", sky: "#6CB2FF", lilac: "#A88FFA",
  };
  const CATS = [
    { id: "diskMap", icon: "🗺️", color: C.lemon, risk: "careful", act: "digging", view: true },
    { id: "caches", icon: "🌬️", color: C.sky, risk: "safe", act: "sniffing" },
    { id: "logsTemp", icon: "🧾", color: C.lilac, risk: "safe", act: "reading" },
    { id: "systemAreas", icon: "⚙️", color: C.sky, risk: "review", act: "sweeping" },
    { id: "aiTools", icon: "🤖", color: C.pink, risk: "review", act: "hacking" },
    { id: "devCaches", icon: "🔨", color: C.orange, risk: "safe", act: "hacking" },
    { id: "buildDeps", icon: "📦", color: C.mint, risk: "safe", act: "digging" },
    { id: "gitRepos", icon: "🌿", color: C.coral, risk: "review", act: "reading" },
    { id: "duplicates", icon: "👯", color: C.lilac, risk: "review", act: "detective" },
    { id: "bigFiles", icon: "🦖", color: C.pink, risk: "careful", act: "digging" },
    { id: "installers", icon: "💿", color: C.sky, risk: "safe", act: "lookout" },
    { id: "oldDownloads", icon: "📥", color: C.mint, risk: "review", act: "lookout" },
  ];
  const CAT = Object.fromEntries(CATS.map(c => [c.id, c]));
  const RISK = {};
  const QUIP_COUNTS = {"digging": 4, "detective": 4, "sweeping": 4, "reading": 4, "hacking": 4, "sniffing": 4, "lookout": 3, "sleepy": 1, "celebrating": 1, "idle": 1, "wave": 1};
  const QUIPS = {};
  // ───────── translations ─────────
  const t = (k, ...a) => I18n.t(k, ...a);
  const tp = (k, n, ...a) => I18n.tp(k, n, ...a);
  const nItems = n => tp("web.items", n, n);
  /** Rust messages (and byte counts) → text in the current language. */
  const msg = s => I18n.msg(s, { bytes });
  function localizeItem(it) {
    it._raw ||= { name: it.name, detail: it.detail, badges: it.badges, groupLabel: it.groupLabel };
    it.name = msg(it._raw.name); it.detail = msg(it._raw.detail);
    it.badges = (it._raw.badges || []).map(msg); it.groupLabel = it._raw.groupLabel == null ? null : msg(it._raw.groupLabel);
    return it;
  }
  function localize() {
    CATS.forEach(c => ["title", "sub", "scan", "explain"].forEach(f => c[f] = t(`web.cat.${c.id}.${f}`)));
    ["safe", "review", "careful"].forEach(r => RISK[r] = t(`web.risk.${r}`));
    Object.entries(QUIP_COUNTS).forEach(([act, n]) => QUIPS[act] = Array.from({ length: n }, (_, i) => t(`web.quip.${act}.${i}`)));
    Object.values(S.results || {}).forEach(list => list.forEach(localizeItem));
  }

  const EXT_ICON = { mp4: "🎬", mkv: "🎬", mov: "🎬", avi: "🎬", zip: "📦", rar: "📦", "7z": "📦", gz: "📦", iso: "💿", exe: "⚙️", msi: "⚙️", deb: "📦", rpm: "📦", appimage: "📲", pdf: "📄", jpg: "🖼️", png: "🖼️", mp3: "🎵", wav: "🎵", flac: "🎵" };

  // ───────── state ─────────
  const S = {
    platform: "linux", disk: { total: 0, free: 0 }, results: {}, sel: new Set(), view: null,
    tree: localStorage.getItem("suri.tree") === "1", sort: "size", query: "", expanded: new Set(),
    busy: null, trash: 0, muted: localStorage.getItem("suri.muted") === "1",
    freed: Number(localStorage.getItem("suri.freed") || 0), stepBase: 0, steps: 1,
  };

  // ───────── format ─────────
  function bytes(b) {
    b = Math.max(0, b || 0);
    const u = ["byte", "KB", "MB", "GB", "TB"]; let i = 0;
    while (b >= 1000 && i < 4) { b /= 1000; i++; }
    return i === 0 ? t("web.fmt.bytes", b) : `${I18n.num(b, 1)} ${u[i]}`;
  }
  const items = id => S.results[id] || [];
  const total = list => list.reduce((a, b) => a + b.size, 0);
  const displayTotal = id => id === "diskMap" ? Math.max(0, ...items(id).map(i => i.size)) : total(items(id));
  const foundTotal = () => CATS.filter(c => !c.view).reduce((a, c) => a + total(items(c.id)), 0);
  const recTotal = () => CATS.filter(c => !c.view).reduce((a, c) => a + total(items(c.id).filter(i => i.recommended)), 0);
  const sfx = k => Chiptune.sfx(k);

  function toast(msg) {
    const t = $("#toast");
    t.textContent = msg; t.className = "toast card";
    clearTimeout(toast._t); toast._t = setTimeout(() => t.className = "toast card hidden", 3500);
  }

  // ───────── background ─────────
  function background() {
    const bg = $(".bg"), cols = [C.pink, C.sky, C.lemon, C.lilac, C.mint];
    for (let i = 0; i < 16; i++) {
      const s = document.createElement("span"), r = 12 + (i % 4) * 10;
      s.style.left = `${(Math.sin(i * 12.9898) * .5 + .5) * 100}%`;
      s.style.animationDuration = `${40 + (i % 5) * 12}s`; s.style.animationDelay = `${-i * 7}s`;
      if (i % 3 === 0) { s.className = "star"; s.textContent = "✦"; s.style.color = cols[i % 5]; }
      else { s.style.width = s.style.height = `${r}px`; s.style.background = cols[i % 5]; }
      bg.appendChild(s);
    }
  }

  // ───────── sidebar ─────────
  function level() {
    const gb = S.freed / 1e9;
    const steps = [[1, t("web.level.1"), "🐣"], [5, t("web.level.2"), "🌱"], [20, t("web.level.3"), "👀"], [50, t("web.level.4"), "👑"]];
    let prev = 0;
    for (const [lim, name, e] of steps) { if (gb < lim) return { t: name, e, p: (gb - prev) / (lim - prev), next: t("web.level.next", lim) }; prev = lim; }
    return { t: t("web.level.5"), e: "🌟", p: 1, next: t("web.level.max") };
  }

  function renderSidebar() {
    const lv = level();
    const row = (id, icon, title, color, badge) =>
      `<button class="side-row ${S.view === id ? "sel" : ""}" style="--c:${color}" data-open="${id ?? ""}">
        <span class="ic">${icon}</span><span class="lbl">${esc(title)}</span>${badge ? `<span class="badge">${badge}</span>` : ""}</button>`;
    $("#sidebar").innerHTML = `
      <div class="brand"><div class="suri-mini" id="suri-side"></div><div><h1>SuriClean</h1><small>${esc(t("web.brand.sub"))}</small></div></div>
      ${row(null, "🏡", t("web.side.home"), C.lemon)}
      <div class="section-label">${esc(t("web.side.zones"))}</div>
      <div class="side-list">${CATS.map(c => row(c.id, c.icon, c.title, c.color, S.results[c.id] ? bytes(displayTotal(c.id)) : "")).join("")}</div>
      <div class="card level" style="--c:${C.mint}"><div class="t">${lv.e} ${lv.t}</div><div class="s">${esc(t("web.side.freed", bytes(S.freed)))}</div>
        <div class="progress" style="width:100%;height:9px;margin:6px 0"><i style="width:${Math.max(4, lv.p * 100)}%"></i></div><div class="s">${lv.next}</div></div>
      ${updatePill()}
      <div class="music-row"><button class="music-toggle" data-act="mute" title="${esc(t(S.muted ? "web.music.paused" : "web.music.on"))}">${S.muted ? "🔇" : "🎵"}</button>
      <span class="sp"></span>${langPicker()}</div>`;
    Suri.setActivity($("#suri-side"), S.busy ? S.busy.act : "idle");
  }

  // ───────── language ─────────
  function langPicker() {
    const cur = I18n.languages.find(l => l.code === I18n.lang);
    const opts = [`<option value="" ${I18n.chosen ? "" : "selected"}>${esc(t("web.lang.auto"))}</option>`]
      .concat(I18n.languages.map(l => `<option value="${l.code}" ${I18n.chosen === l.code ? "selected" : ""}>${esc(l.name)}</option>`));
    return `<label class="lang-row" title="${esc(t("web.lang.title"))}">🌐 <span>${esc(cur ? cur.name : I18n.lang)}</span>
      <select data-lang>${opts.join("")}</select></label>`;
  }

  async function changeLang(code) {
    await I18n.setLang(code || null);
    localize();
    sfx("coin");
    render();
  }

  // ───────── updates ─────────
  const ASSET = { windows: "SuriClean-Windows-Setup.exe", appimage: "SuriClean-Linux.AppImage", deb: "SuriClean-Linux.deb" };
  S.update = null; S.version = "0"; S.kind = "deb";
  S.autoUpdate = localStorage.getItem("suri.autoUpdate") !== "0";

  function newer(a, b) {
    const p = s => String(s).replace(/^v/i, "").split(".").map(x => parseInt(x, 10) || 0);
    const x = p(a), y = p(b);
    for (let i = 0; i < Math.max(x.length, y.length); i++) { const l = x[i] || 0, r = y[i] || 0; if (l !== r) return l > r; }
    return false;
  }

  async function checkUpdate(manual) {
    try {
      const r = await fetch("https://api.github.com/repos/Marketto/suriclean/releases/latest", { headers: { Accept: "application/vnd.github+json" }, cache: "no-store" });
      if (!r.ok) throw new Error(r.status);
      const j = await r.json();
      const v = (j.tag_name || "").replace(/^v/i, "");
      const asset = (j.assets || []).find(a => a.name === ASSET[S.kind]);
      if (newer(v, S.version) && asset) {
        S.update = { version: v, url: asset.browser_download_url };
        renderSidebar();
        if (S.autoUpdate && S.kind !== "deb" && !S.busy && !Object.keys(S.results).length) return installUpdate();
        toast(t("web.upd.available", v));
      } else if (manual) toast(t("web.upd.latest", S.version));
    } catch (e) { if (manual) toast(t("web.upd.offline")); }
  }

  async function installUpdate() {
    if (!S.update || S.busy) return;
    S.steps = 1;
    S.busy = { act: "digging", title: t("web.upd.downloading", S.update.version), detail: t(S.kind === "deb" ? "web.upd.deb_next" : "web.upd.restart"), progress: null, step: 0, found: 0 };
    Chiptune.setMood("cleaning"); showBusy();
    try {
      await invoke("install_update", { url: S.update.url, kind: S.kind });
      if (S.kind === "deb") { S.busy = null; showBusy(); toast(t("web.upd.deb_saved")); }
    } catch (e) { S.busy = null; showBusy(); toast(t("web.upd.failed", msg(String(e)))); }
  }

  function updatePill() {
    if (S.update) return `<button class="btn" style="--c:${C.pink};text-align:left" data-act="update">${esc(t("web.upd.pill", S.update.version))}</button>`;
    return `<div style="display:flex;align-items:center;gap:6px;padding:0 8px"><button class="music-toggle" style="padding:0;opacity:.5;font-size:10.5px" data-act="checkUpdate">${esc(t("web.upd.check", S.version))}</button>
      <label style="margin-left:auto;font-size:10px;font-weight:800;opacity:.6"><input type="checkbox" data-act="autoUpdate" ${S.autoUpdate ? "checked" : ""}> ${esc(t("web.upd.auto"))}</label></div>`;
  }

  // ───────── dashboard ─────────
  function greeting() {
    const pct = S.disk.total ? Math.round((1 - S.disk.free / S.disk.total) * 100) : 0;
    if (!Object.keys(S.results).length) {
      if (pct >= 90) return t("web.greet.full", pct);
      if (pct >= 70) return t("web.greet.mid", pct);
      return t("web.greet.ok", pct);
    }
    return t("web.greet.found", bytes(foundTotal()), bytes(recTotal()));
  }

  function typewrite(el, text) {
    clearInterval(typewrite._t);
    let i = 0; el.textContent = "";
    typewrite._t = setInterval(() => { i++; el.textContent = text.slice(0, i); if (i >= text.length) clearInterval(typewrite._t); }, 18);
  }

  function gauge() {
    const used = S.disk.total ? (S.disk.total - S.disk.free) / S.disk.total : 0;
    const rec = Math.min(recTotal() / (S.disk.total || 1), used);
    const R = 70, L = 2 * Math.PI * R;
    return `<div class="card gauge"><svg viewBox="0 0 168 168">
      <defs><linearGradient id="gg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFCCAD"/><stop offset="1" stop-color="#FF80A8"/></linearGradient></defs>
      <circle cx="84" cy="84" r="${R}" fill="none" stroke="rgba(97,214,173,.22)" stroke-width="26"/>
      <circle cx="84" cy="84" r="${R}" fill="none" stroke="url(#gg)" stroke-width="26" stroke-linecap="round" transform="rotate(-90 84 84)" stroke-dasharray="${L}" stroke-dashoffset="${L}" style="transition:stroke-dashoffset 1.3s cubic-bezier(.3,1.2,.5,1)" data-to="${L * (1 - used)}"/>
      <circle cx="84" cy="84" r="${R}" fill="none" stroke="#61D6AD" stroke-width="12" stroke-linecap="round" transform="rotate(${-90 + 360 * (used - rec)} 84 84)" stroke-dasharray="${L * rec} ${L}"/>
      <text x="84" y="88" text-anchor="middle" font-size="34" font-weight="900" fill="#54382B">${Math.round(used * 100)}%</text>
      <text x="84" y="110" text-anchor="middle" font-size="13" font-weight="800" fill="rgba(84,56,43,.5)">${esc(t("web.gauge.full"))}</text></svg>
      <div class="legend"><div><i style="background:#FF80A8"></i>${esc(t("web.gauge.used"))}<b>${bytes(S.disk.total - S.disk.free)}</b></div>
      <div><i style="background:rgba(97,214,173,.4)"></i>${esc(t("web.gauge.free"))}<b>${bytes(S.disk.free)}</b></div>
      <div><i style="background:#61D6AD"></i>${esc(t("web.gauge.rec"))}<b>${recTotal() ? bytes(recTotal()) : "—"}</b></div>
      <div><i style="background:#FFD14D"></i>${esc(t("web.gauge.found"))}<b>${foundTotal() ? bytes(foundTotal()) : "—"}</b></div></div></div>`;
  }

  function renderDashboard() {
    const trashName = t("web.tips.trash");
    $("#main").innerHTML = `<div class="scroll">
      <div class="hero"><div class="suri-hero" id="suri-hero"></div>
        <div style="flex:1"><div class="bubble" id="bubble"></div>
          <div class="hero-actions"><button class="btn big" data-act="scanAll" ${S.busy ? "disabled" : ""}>${esc(t("web.dash.scan"))}</button>
          ${recTotal() ? `<div><div class="big-number">${bytes(recTotal())}</div><div class="small-note">${esc(t("web.dash.rec_note"))}</div></div>` : ""}</div></div></div>
      <div class="row2">${gauge()}
        <div class="card tips"><h3>${esc(t("web.tips.title"))}</h3>
          <div class="tip" style="--c:${C.coral}"><div class="ic">🗑️</div><div class="txt"><b>${esc(trashName)}</b><span>${esc(t("web.tips.trash_note"))}</span></div><div class="val">${bytes(S.trash)}</div>${S.trash ? `<button class="btn" style="--c:${C.coral}" data-act="askEmpty">${esc(t("web.tips.empty"))}</button>` : ""}</div>
          <div class="tip" style="--c:${C.mint}"><div class="ic">🔄</div><div class="txt"><b>${esc(t("web.tips.refresh"))}</b><span>${esc(t("web.tips.refresh_note"))}</span></div><button class="btn" style="--c:${C.mint}" data-act="refresh">${esc(t("web.tips.refresh_btn"))}</button></div>
          ${S.adminDone ? "" : `<div class="tip" style="--c:${C.orange}"><div class="ic">🔑</div><div class="txt"><b>${esc(t("web.tips.admin"))}</b><span>${esc(t("web.tips.admin_note"))}</span></div><button class="btn" style="--c:${C.orange}" data-act="admin">${esc(t("web.tips.admin_btn"))}</button></div>`}
          ${S.platform === "windows" ? `<div class="tip" style="--c:${C.sky}"><div class="ic">🪟</div><div class="txt"><b>${esc(t("web.tips.cleanmgr"))}</b><span>${esc(t("web.tips.cleanmgr_note"))}</span></div><button class="btn" style="--c:${C.sky}" data-act="cleanmgr">${esc(t("web.tips.open"))}</button></div>` :
          `<div class="tip" style="--c:${C.sky}"><div class="ic">🐧</div><div class="txt"><b>${esc(t("web.tips.pkgs"))}</b><span>${esc(t("web.tips.pkgs_note", "\u0000", "\u0001")).replace("\u0000", "<code>sudo apt autoremove && sudo apt clean</code>").replace("\u0001", "<code>flatpak uninstall --unused</code>")}</span></div></div>`}
        </div></div>
      <h2 class="zones">${esc(t("web.dash.zones"))}<small>${esc(t("web.dash.zones_hint"))}</small></h2>
      <div class="grid">${CATS.map(c => {
        const r = S.results[c.id];
        return `<div class="card zone" style="--c:${c.color}" data-open="${c.id}">
          <div class="top"><div class="blob">${c.icon}</div><span class="pill risk-${c.risk}">${RISK[c.risk]}</span></div>
          <h4>${esc(c.title)}</h4><p>${esc(c.sub)}</p>
          <div class="found">${r ? `${bytes(displayTotal(c.id))} <small>${r.length ? `· ${esc(nItems(r.length))}` : esc(t("web.dash.clean_zone"))}</small>` : `<small style="font-size:12.5px">${esc(t("web.dash.unexplored"))}</small>`}</div></div>`;
      }).join("")}</div></div>`;
    Suri.setActivity($("#suri-hero"), "idle");
    typewrite($("#bubble"), greeting());
    requestAnimationFrame(() => document.querySelectorAll("[data-to]").forEach(c => c.setAttribute("stroke-dashoffset", c.dataset.to)));
  }

  // ───────── detail ─────────
  function sorted(list) {
    let l = list.slice();
    if (S.query) { const q = S.query.toLowerCase(); l = l.filter(i => i.name.toLowerCase().includes(q) || i.detail.toLowerCase().includes(q)); }
    if (S.sort === "size") l.sort((a, b) => b.size - a.size);
    else if (S.sort === "date") l.sort((a, b) => (a.date ?? 0) - (b.date ?? 0));
    else l.sort((a, b) => a.name.localeCompare(b.name, I18n.lang));
    return l;
  }

  function fileIcon(it) {
    const ext = (it.path.split(".").pop() || "").toLowerCase();
    if (it.path.split(/[\\/]/).pop().includes(".") && EXT_ICON[ext]) return EXT_ICON[ext];
    return it.size && !/\.[a-z0-9]{1,5}$/i.test(it.path) ? "📁" : "📄";
  }

  function itemRow(it, max, color, selectable = true) {
    const sel = S.sel.has(it.id);
    return `<div class="item ${sel ? "sel" : ""}" style="--c:${color}" data-item="${it.id}">
      ${selectable ? `<div class="chk">${sel ? "🐾" : ""}</div>` : ""}
      <div class="ficon">${fileIcon(it)}</div>
      <div class="info"><div class="name">${esc(it.name)}${it.risk === "careful" && selectable ? `<span class="pill risk-careful">${esc(RISK.careful)}</span>` : ""}${it.badges.map(b => `<span class="pill">${esc(b)}</span>`).join("")}</div>
      <div class="det" title="${esc(it.detail)}">${esc(it.detail)}</div></div>
      <div class="sz"><b>${it.size || !it.cmd ? bytes(it.size) : "?"}</b><div class="bar"><i style="--w:${Math.max(3, it.size / max * 100)}%"></i></div></div>
      ${it.copyText ? `<button class="rbtn" data-copy="${it.id}" title="${esc(it.copyText)}">📋</button>` : ""}
      <button class="rbtn" data-reveal="${esc(it.path)}" title="${esc(t("web.item.reveal"))}">🔍</button></div>`;
  }

  // tree
  function buildTree(list) {
    const sep = S.platform === "windows" ? "\\" : "/";
    const root = { id: "", name: "", kids: new Map(), item: null };
    for (const it of list) {
      const parts = it.path.split(/[\\/]/).filter(Boolean);
      let node = root, path = S.platform === "windows" ? "" : "";
      parts.forEach((p, i) => {
        path = i === 0 ? (S.platform === "windows" ? p : "/" + p) : path + sep + p;
        if (!node.kids.has(p)) node.kids.set(p, { id: path, name: p, kids: new Map(), item: null });
        node = node.kids.get(p);
      });
      node.item = it;
    }
    const finish = n => {
      n.children = [...n.kids.values()];
      let sum = 0, ids = [], newest = n.item?.date ?? 0;
      n.children.forEach(c => { finish(c); sum += c.size; ids.push(...c.ids); newest = Math.max(newest, c.newest); });
      if (n.item) ids.push(n.item.id);
      n.ids = ids; n.size = n.item ? Math.max(n.item.size, sum) : sum; n.newest = newest;
      const by = { size: (a, b) => b.size - a.size, date: (a, b) => a.newest - b.newest, name: (a, b) => a.name.localeCompare(b.name, I18n.lang) }[S.sort];
      n.children.sort(by);
    };
    finish(root);
    const compress = n => {
      let cur = n;
      while (!cur.item && cur.children.length === 1) { const only = cur.children[0]; only.name = cur.name + sep + only.name; cur = only; }
      cur.children = cur.children.map(compress);
      return cur;
    };
    return root.children.map(compress);
  }

  function treeHTML(list, color, selectable) {
    const roots = buildTree(list);
    const max = Math.max(1, ...roots.map(r => r.size));
    if (!S.expanded.size) roots.forEach(r => { if (r.children.length) { S.expanded.add(r.id); r.children.slice(0, 8).forEach(c => c.children.length && S.expanded.add(c.id)); } });
    const rows = [];
    const walk = (nodes, depth) => nodes.forEach(n => {
      const nsel = n.ids.filter(id => S.sel.has(id)).length, all = nsel === n.ids.length && nsel > 0, part = nsel > 0 && !all;
      const open = S.expanded.has(n.id);
      rows.push(`<div class="item node ${n.item ? "" : "folder"} ${all ? "sel" : ""}" style="--c:${color};margin-left:${depth * 20}px" data-node="${esc(n.id)}">
        ${n.children.length ? `<button class="caret ${open ? "open" : ""}" data-caret="${esc(n.id)}">›</button>` : `<span class="caret"></span>`}
        ${selectable ? `<div class="chk ${all ? "on" : part ? "part" : ""}">${all ? "🐾" : part ? "–" : ""}</div>` : ""}
        <div class="ficon">${n.item && !n.children.length ? fileIcon(n.item) : "📁"}</div>
        <div class="info"><div class="name">${esc(n.item && !n.children.length ? n.item.name : n.name)}
          ${n.item ? n.item.badges.map(b => `<span class="pill">${esc(b)}</span>`).join("") : `<span class="pill">${esc(nItems(n.ids.length))}</span>`}</div></div>
        <div class="sz"><b>${bytes(n.size)}</b><div class="bar"><i style="--w:${Math.max(3, n.size / max * 100)}%"></i></div></div>
        <button class="rbtn" data-open-folder="${esc(n.id)}" title="${esc(t("web.item.open_folder"))}">${n.children.length || !n.item ? "📁" : "🔍"}</button></div>`);
      if (open) walk(n.children, depth + 1);
      S._nodes[n.id] = n;
    });
    S._nodes = {};
    walk(roots, 0);
    return `<div class="tree-tools"><button class="btn" style="--c:${C.sky}" data-act="expandAll">${esc(t("web.tree.expand"))}</button><button class="btn" style="--c:${C.lilac}" data-act="collapseAll">${esc(t("web.tree.collapse"))}</button></div>` + rows.join("");
  }

  function listHTML(cat) {
    const l = sorted(items(cat.id));
    if (!S.results[cat.id]) return `<div class="empty"><div class="suri-empty" data-suri="${cat.act}"></div><h3>${esc(t("web.list.unknown"))}</h3><button class="btn big" style="--c:${cat.color}" data-act="rescan">${esc(t("web.list.explore"))}</button></div>`;
    if (!l.length) return `<div class="empty"><div class="suri-empty" data-suri="celebrating"></div><h3>${esc(t("web.list.empty"))}</h3></div>`;
    const selectable = !cat.view;
    if (S.tree || cat.view) return treeHTML(l, cat.color, selectable);
    const max = Math.max(1, ...l.map(i => i.size));
    if (cat.id === "duplicates") {
      const groups = {};
      l.forEach(i => (groups[i.group ?? -1] ||= []).push(i));
      return Object.values(groups).sort((a, b) => total(b) - total(a)).map(g =>
        `<div class="group" style="--c:${cat.color}"><h5>👯 ${esc(g[0].groupLabel || "")}</h5>${g.sort((a, b) => a.recommended - b.recommended).map(i => itemRow(i, max, cat.color)).join("")}</div>`).join("");
    }
    return l.map(i => itemRow(i, max, cat.color)).join("");
  }

  function footerHTML(cat) {
    if (cat.view) return `<div class="footer" style="--c:${cat.color}"><span class="hint">${esc(t("web.footer.map_hint"))}</span><span class="sp"></span><b>${esc(t("web.footer.used", bytes(S.disk.total - S.disk.free)))}</b></div>`;
    const sel = items(cat.id).filter(i => S.sel.has(i.id));
    return `<div class="footer" style="--c:${cat.color}"><div class="selinfo"><small>${esc(t("web.footer.selected", sel.length))}</small><b>${bytes(total(sel))}</b></div><span class="sp"></span>
      <button class="btn" style="--c:${C.mint}" data-act="selRec">${esc(t("web.footer.rec"))}</button>
      <button class="btn" style="--c:${C.lilac}" data-act="selAll">${esc(t("web.footer.all"))}</button>
      <button class="btn" style="--c:${C.lilac}" data-act="selNone">${esc(t("web.footer.none"))}</button>
      <button class="btn big" style="--c:${C.coral}" data-act="askClean" ${sel.length && !S.busy ? "" : "disabled"}>${esc(t("web.footer.clean"))}</button></div>`;
  }

  function renderDetail() {
    const cat = CAT[S.view];
    const seg = (key, opts) => `<div class="seg">${opts.map(([v, l]) => `<button class="${S[key] === v ? "on" : ""}" data-seg="${key}" data-val="${v}">${l}</button>`).join("")}</div>`;
    $("#main").innerHTML = `<div class="detail-head" style="--c:${cat.color}">
      <div class="dh-top"><div class="blob">${cat.icon}</div><div><h2>${esc(cat.title)} <span class="pill risk-${cat.risk}">${RISK[cat.risk]}</span></h2><p>${esc(cat.explain)}</p></div><div class="suri-head" id="suri-head"></div></div>
      <div class="controls">
        ${cat.view ? "" : seg("tree", [[false, esc(t("web.detail.list"))], [true, esc(t("web.detail.tree"))]])}
        ${seg("sort", [["size", esc(t("web.sort.size"))], ["date", esc(t("web.sort.date"))], ["name", esc(t("web.sort.name"))]])}
        <label class="search">🔍<input id="q" placeholder="${esc(t("web.detail.search"))}" value="${esc(S.query)}"></label>
        <span class="count" id="count"></span>
        <button class="btn" style="--c:${C.sky}" data-act="rescan" ${S.busy ? "disabled" : ""}>${esc(t("web.detail.rescan"))}</button>
        ${["diskMap", "systemAreas"].includes(cat.id) ? `<button class="btn" style="--c:${C.orange}" data-act="admin" ${S.busy ? "disabled" : ""}>${esc(t("web.detail.admin"))}</button>` : ""}
      </div></div>
      <div class="list" id="list"></div><div id="footer"></div>`;
    Suri.setActivity($("#suri-head"), cat.act);
    $("#q").addEventListener("input", e => { S.query = e.target.value; renderList(); });
    renderList();
  }

  function renderList() {
    const cat = CAT[S.view]; if (!cat) return;
    const list = $("#list"), top = list.scrollTop;
    list.innerHTML = listHTML(cat);
    list.scrollTop = top;
    list.querySelectorAll("[data-suri]").forEach(el => Suri.setActivity(el, el.dataset.suri));
    $("#footer").innerHTML = footerHTML(cat);
    $("#count").textContent = S.results[cat.id] ? `${nItems(items(cat.id).length)} · ${bytes(displayTotal(cat.id))}` : "";
  }

  function render() {
    renderSidebar();
    if (S.view) renderDetail(); else renderDashboard();
  }

  // ───────── overlays ─────────
  function showBusy() {
    const b = S.busy;
    let ov = $("#busy");
    if (!b) { if (ov) ov.remove(); return; }
    if (!ov) {
      ov = document.createElement("div"); ov.id = "busy"; ov.className = "ov";
      ov.innerHTML = `<div class="card panel"><div class="suri-ov" id="suri-ov"></div><h3 id="b-title"></h3><div class="quip" id="b-quip"></div>
        <div class="progress" id="b-prog"><i></i></div><div class="pdetail" id="b-det"></div><div class="hint" id="b-found"></div><div class="hint" id="b-step"></div>
        <button class="btn" style="--c:${C.lilac}" data-act="cancel">${esc(t("web.cancel"))}</button></div>`;
      $("#overlay").appendChild(ov);
      clearInterval(showBusy._q);
      showBusy._q = setInterval(() => { const q = QUIPS[S.busy?.act] || ["…"]; $("#b-quip") && ($("#b-quip").textContent = q[Math.floor(Date.now() / 2600) % q.length]); }, 400);
    }
    Suri.setActivity($("#suri-ov"), b.act);
    $("#b-title").textContent = b.title;
    $("#b-det").textContent = b.detail || " ";
    const p = $("#b-prog");
    if (b.progress == null) p.classList.add("indet"); else { p.classList.remove("indet"); p.firstElementChild.style.width = `${Math.max(3, b.progress * 100)}%`; }
    $("#b-found").textContent = b.found ? t("web.busy.loot", bytes(b.foundBytes), nItems(b.found)) : "";
    $("#b-step").textContent = S.steps > 1 ? t("web.busy.step", b.step + 1, S.steps) : "";
  }

  function confetti(host) {
    const c = document.createElement("canvas"); c.className = "confetti"; host.appendChild(c);
    const ctx = c.getContext("2d"), cols = [C.pink, C.lemon, C.sky, C.mint, C.lilac, C.coral], t0 = performance.now();
    const draw = now => {
      if (!c.isConnected) return;
      c.width = innerWidth; c.height = innerHeight;
      const t = (now - t0) / 1000;
      for (let i = 0; i < 90; i++) {
        const tt = t - (i * 0.037) % 1.2; if (tt < 0) continue;
        const x = (Math.sin(i * 91.7) * .5 + .5) * c.width + Math.sin(tt * 3 + i) * 30;
        const y = (-20 + tt * (120 + (i * 13) % 90)) % (c.height + 40);
        ctx.save(); ctx.translate(x, y); ctx.rotate(tt * (2 + i % 3)); ctx.fillStyle = cols[i % 6];
        const w = 6 + i % 5, h = (10 + (i * 3) % 6) * Math.max(.15, Math.abs(Math.cos(tt * 4 + i)));
        ctx.fillRect(-w / 2, -h / 2, w, h); ctx.restore();
      }
      requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  function celebrate({ kind, bytes: b, message }) {
    Chiptune.setMood("victory");
    setTimeout(() => Chiptune.getMood() === "victory" && Chiptune.setMood("results"), 3800);
    const ov = document.createElement("div"); ov.className = "ov celebrate"; ov.id = "cele";
    const title = kind === "trashed" ? t(b > 0 ? "web.cele.yatta" : "web.cele.gomen") : t("web.cele.emptied");
    const sub = kind === "trashed" ? (b > 0 ? t("web.cele.trashed", bytes(b)) : t("web.cele.nothing")) : t("web.cele.recovered", bytes(b));
    ov.innerHTML = `<div class="card panel"><div class="suri-ov" id="suri-cele"></div><h3>${esc(title)}</h3><b style="font-size:17px">${esc(sub)}</b>
      ${message ? `<div class="hint">${esc(message)}</div>` : ""}
      ${kind === "trashed" && b > 0 ? `<div class="hint" style="color:#c2453c">${esc(t("web.cele.psst"))}</div>` : ""}
      <div style="display:flex;gap:12px;margin-top:6px">${kind === "trashed" && S.trash > 0 ? `<button class="btn big" style="--c:${C.coral}" data-act="askEmpty">${esc(t("web.cele.empty_btn"))}</button>` : ""}
      <button class="btn big" style="--c:${C.mint}" data-act="closeCele">${esc(t("web.cele.thanks"))}</button></div></div>`;
    $("#overlay").appendChild(ov);
    confetti(ov);
    Suri.setActivity($("#suri-cele"), "celebrating");
  }

  function choiceBox(title, text, choices) {
    const ov = document.createElement("div"); ov.className = "ov confirm";
    ov.innerHTML = `<div class="card panel"><div class="suri-ov" id="suri-conf" style="width:120px;height:142px"></div><h3>${esc(title)}</h3><div class="hint">${esc(text)}</div>
      <div style="display:flex;gap:12px;margin-top:8px;flex-wrap:wrap;justify-content:center"><button class="btn" style="--c:${C.lilac}" data-c="no">${esc(t("web.cancel"))}</button>
      ${choices.map(([l, c], i) => `<button class="btn big" style="--c:${c}" data-c="${i}">${esc(l)}</button>`).join("")}</div></div>`;
    $("#overlay").appendChild(ov);
    Suri.setActivity($("#suri-conf"), "wave");
    ov.addEventListener("click", e => {
      const c = e.target.closest("[data-c]")?.dataset.c;
      if (!c) return;
      ov.remove(); sfx("pop");
      if (c !== "no") choices[Number(c)][2]();
    });
  }

  /// One administrator prompt: SuriClean measures the whole disk and the protected system areas.
  async function adminScan() {
    if (S.busy) return;
    S.steps = 1;
    S.busy = { act: "lookout", title: t("web.admin.title"), detail: t("web.admin.detail"), progress: null, step: 0, found: 0, foundBytes: 0 };
    Chiptune.setMood("scanning"); sfx("whoosh"); showBusy();
    try {
      const res = await invoke("elevated_scan", { categories: ["diskMapFull", "systemAreas"] });
      if (res.diskMapFull) setResults("diskMap", res.diskMapFull);
      if (res.systemAreas) setResults("systemAreas", res.systemAreas);
      S.adminDone = true;
      S.busy = null; showBusy();
      Chiptune.setMood("results"); sfx("coin");
      toast(t("web.admin.done"));
    } catch (e) {
      S.busy = null; showBusy();
      Chiptune.setMood("menu"); sfx("error");
      toast(t("web.admin.failed", msg(String(e))));
    }
    await refreshDisk(); render();
  }

  function confirmBox(title, text, okLabel, onOk) {
    const ov = document.createElement("div"); ov.className = "ov confirm";
    ov.innerHTML = `<div class="card panel"><div class="suri-ov" id="suri-conf" style="width:120px;height:142px"></div><h3>${esc(title)}</h3><div class="hint">${esc(text)}</div>
      <div style="display:flex;gap:12px;margin-top:8px"><button class="btn" style="--c:${C.lilac}" data-c="no">${esc(t("web.cancel"))}</button><button class="btn big" style="--c:${C.coral}" data-c="ok">${esc(okLabel)}</button></div></div>`;
    $("#overlay").appendChild(ov);
    Suri.setActivity($("#suri-conf"), "sweeping");
    ov.addEventListener("click", e => {
      const c = e.target.closest("[data-c]")?.dataset.c;
      if (!c) return;
      ov.remove(); sfx("pop");
      if (c === "ok") onOk();
    });
  }

  // ───────── backend actions ─────────
  async function refreshDisk() {
    try { S.disk = await invoke("disk_info"); } catch (e) { console.error(e); }
    try { S.trash = await invoke("trash_size"); } catch (e) { console.error(e); }
  }

  function setResults(id, list) {
    (S.results[id] || []).forEach(i => S.sel.delete(i.id));
    list.forEach(localizeItem);
    S.results[id] = list;
    list.filter(i => i.recommended).forEach(i => S.sel.add(i.id));
  }

  async function runScan(ids) {
    if (S.busy || !ids.length) return;
    S.steps = ids.length;
    S.busy = { act: CAT[ids[0]].act, title: CAT[ids[0]].scan, detail: "", progress: 0, step: 0, found: 0, foundBytes: 0 };
    sfx("whoosh"); render(); showBusy();
    let cancelled = false;
    for (let i = 0; i < ids.length; i++) {
      const c = CAT[ids[i]];
      Chiptune.setMood(c.id === "duplicates" ? "detective" : "scanning");
      Chiptune.setIntensity(i / ids.length);
      Object.assign(S.busy, { act: c.act, title: c.scan, step: i, progress: ids.length > 1 ? i / ids.length : null });
      showBusy(); renderSidebar();
      try {
        const list = await invoke("scan_category", { category: c.id });
        if (S.busy?.cancelled) { cancelled = true; break; }
        setResults(c.id, list);
        S.busy.found += list.length; S.busy.foundBytes += c.view ? 0 : total(list);
        sfx("coin");
      } catch (e) { console.error(e); toast(t("web.scan.error", c.title, msg(String(e)))); }
      if (S.busy?.cancelled) { cancelled = true; break; }
    }
    S.busy = null; showBusy();
    Chiptune.setIntensity(0); Chiptune.setMood(cancelled ? "menu" : "results");
    await refreshDisk(); render();
    if (!cancelled && ids.length > 1) toast(t("web.scan.done", bytes(foundTotal())));
  }

  async function clean(catId) {
    let sel = items(catId).filter(i => S.sel.has(i.id));
    if (catId === "duplicates") {
      const groups = {};
      items(catId).forEach(i => (groups[i.group] ||= []).push(i));
      const safe = [];
      Object.values(groups).forEach(g => {
        const kept = g.filter(i => !S.sel.has(i.id));
        if (kept.length) safe.push(...g.filter(i => S.sel.has(i.id)));
        else { const spare = g.find(i => !i.recommended) || g[0]; safe.push(...g.filter(i => S.sel.has(i.id) && i.id !== spare.id)); }
      });
      if (safe.length < sel.length) toast(t("web.clean.kept_one"));
      sel = safe;
    }
    if (!sel.length) return;
    S.steps = 1;
    S.busy = { act: "sweeping", title: tp("web.clean.busy", sel.length, sel.length), detail: "", progress: 0, step: 0, found: 0, foundBytes: 0 };
    Chiptune.setMood("cleaning"); sfx("whoosh"); showBusy();
    let out;
    try {
      out = await invoke("trash_items", { items: sel.map(i => ({ id: i.id, path: i.path, name: i.name, size: i.size, extra: i.extra, copyText: i.copyText, admin: i.admin, cmd: i.cmd })) });
    } catch (e) { out = { removed: [], bytes: 0, failed: [msg(String(e))] }; }
    out.failed = (out.failed || []).map(msg);
    const removed = new Set(out.removed);
    Object.keys(S.results).forEach(k => S.results[k] = S.results[k].filter(i => !removed.has(i.id)));
    removed.forEach(id => S.sel.delete(id));
    await invoke("invalidate_index");
    await pruneMissing();
    S.freed += out.bytes; localStorage.setItem("suri.freed", S.freed);
    S.busy = null; showBusy();
    await refreshDisk(); render();
    let note = out.failed.length ? t("web.clean.failed", nItems(out.failed.length), `${out.failed.slice(0, 3).join(", ")}${out.failed.length > 3 ? "…" : ""}`) : "";
    if (out.repoLog) note += `${note ? " · " : ""}${t("web.clean.repo_log")}`;
    celebrate({ kind: catId === "systemAreas" && out.removed.length ? "emptied" : "trashed", bytes: out.bytes, message: note });
  }

  async function emptyTrash() {
    document.querySelector("#cele")?.remove();
    S.busy = { act: "sweeping", title: t("web.empty.title"), detail: "", progress: null, step: 0, found: 0 };
    S.steps = 1; Chiptune.setMood("cleaning"); sfx("whoosh"); showBusy();
    let freed = 0;
    try { freed = await invoke("empty_trash"); } catch (e) { toast(t("web.empty.failed", msg(String(e)))); }
    S.busy = null; showBusy();
    await refreshDisk(); render();
    celebrate({ kind: "emptied", bytes: freed });
  }

  async function pruneMissing() {
    const all = Object.values(S.results).flat();
    if (!all.length) return;
    try {
      const ex = await invoke("existing", { paths: all.map(i => i.path) });
      const gone = new Set(all.filter((_, k) => !ex[k]).map(i => i.id));
      if (!gone.size) return;
      Object.keys(S.results).forEach(k => S.results[k] = S.results[k].filter(i => !gone.has(i.id)));
      gone.forEach(id => S.sel.delete(id));
      await invoke("invalidate_index");
    } catch (e) { console.error(e); }
  }

  function open(id) {
    sfx("pop");
    S.view = id || null; S.query = ""; S.expanded = new Set();
    S.sort = id === "oldDownloads" ? "date" : "size";
    render();
    if (id && !S.results[id] && !S.busy) runScan([id]);
  }

  // ───────── events ─────────
  document.addEventListener("click", async e => {
    if (!Chiptune.running) { Chiptune.start(); Chiptune.setMuted(S.muted); }
    const tg = e.target;
    const openEl = tg.closest("[data-open]");
    if (openEl) return open(openEl.dataset.open || null);
    const segEl = tg.closest("[data-seg]");
    if (segEl) {
      const k = segEl.dataset.seg, v = segEl.dataset.val;
      S[k] = v === "true" ? true : v === "false" ? false : v;
      if (k === "tree") localStorage.setItem("suri.tree", S.tree ? "1" : "0");
      sfx("pop"); renderDetail(); return;
    }
    const rev = tg.closest("[data-reveal]");
    if (rev) { sfx("pop"); invoke("reveal", { path: rev.dataset.reveal }); return; }
    const of = tg.closest("[data-open-folder]");
    if (of) { sfx("pop"); invoke("open_folder", { path: of.dataset.openFolder }); return; }
    const cp = tg.closest("[data-copy]");
    if (cp) {
      const it = Object.values(S.results).flat().find(i => String(i.id) === cp.dataset.copy);
      if (it?.copyText) { try { await navigator.clipboard.writeText(it.copyText); toast(t("web.copied")); } catch { toast(it.copyText); } }
      sfx("pop"); return;
    }
    const caret = tg.closest("[data-caret]");
    if (caret) { const id = caret.dataset.caret; S.expanded.has(id) ? S.expanded.delete(id) : S.expanded.add(id); sfx("blip"); renderList(); return; }
    const node = tg.closest("[data-node]");
    if (node && S.view) {
      const n = S._nodes[node.dataset.node]; const cat = CAT[S.view];
      if (cat.view) { if (n.children.length) { S.expanded.has(n.id) ? S.expanded.delete(n.id) : S.expanded.add(n.id); renderList(); } return; }
      const all = n.ids.every(id => S.sel.has(id));
      n.ids.forEach(id => all ? S.sel.delete(id) : S.sel.add(id));
      sfx(all ? "pop" : "coin"); renderList(); return;
    }
    const itemEl = tg.closest("[data-item]");
    if (itemEl) { const id = Number(itemEl.dataset.item); S.sel.has(id) ? S.sel.delete(id) : S.sel.add(id); sfx("pop"); renderList(); return; }
    const act = tg.closest("[data-act]")?.dataset.act;
    if (!act) return;
    const cat = CAT[S.view];
    switch (act) {
      case "scanAll":
        if (S.adminDone) { runScan(CATS.map(c => c.id)); break; }
        sfx("pop");
        choiceBox(t("web.scope.title"), t("web.scope.text"), [
          [t("web.scope.mine"), C.mint, () => runScan(CATS.map(c => c.id))],
          [t("web.scope.all"), C.orange, async () => { await runScan(CATS.map(c => c.id)); adminScan(); }],
        ]);
        break;
      case "admin": adminScan(); break;
      case "rescan": if (cat) { if (["buildDeps", "gitRepos", "duplicates", "bigFiles", "installers"].includes(cat.id)) await invoke("invalidate_index"); runScan([cat.id]); } break;
      case "cancel": if (S.busy) { S.busy.cancelled = true; S.busy.title = t("web.busy.stopping"); showBusy(); invoke("cancel_scan"); sfx("error"); } break;
      case "mute": S.muted = !S.muted; localStorage.setItem("suri.muted", S.muted ? "1" : "0"); Chiptune.setMuted(S.muted); renderSidebar(); break;
      case "refresh": sfx("pop"); await pruneMissing(); await refreshDisk(); render(); break;
      case "askEmpty": sfx("pop"); confirmBox(t("web.empty.ask_title"), t("web.empty.ask_text", bytes(S.trash)), t("web.empty.ask_ok"), emptyTrash); break;
      case "closeCele": sfx("pop"); document.querySelector("#cele")?.remove(); break;
      case "selRec": items(cat.id).forEach(i => i.recommended ? S.sel.add(i.id) : S.sel.delete(i.id)); sfx("coin"); renderList(); break;
      case "selAll": items(cat.id).forEach(i => S.sel.add(i.id)); sfx("pop"); renderList(); break;
      case "selNone": items(cat.id).forEach(i => S.sel.delete(i.id)); sfx("pop"); renderList(); break;
      case "askClean": {
        const sel = items(cat.id).filter(i => S.sel.has(i.id));
        sfx("pop");
        if (cat.id === "systemAreas") confirmBox(t("web.clean.sys_title"), t("web.clean.sys_text", nItems(sel.length), bytes(total(sel)), S.platform === "windows" ? "Windows" : "Ubuntu"), t("web.clean.sys_ok"), () => clean(cat.id));
        else confirmBox(t("web.clean.ask_title"), t("web.clean.ask_text", nItems(sel.length), bytes(total(sel))), t("web.clean.ask_ok"), () => clean(cat.id));
        break;
      }
      case "expandAll": { const walk = ns => ns.forEach(n => { if (n.children.length) { S.expanded.add(n.id); walk(n.children); } }); walk(buildTree(items(cat.id))); sfx("pop"); renderList(); break; }
      case "collapseAll": S.expanded = new Set(["__none__"]); sfx("pop"); renderList(); break;
      case "update": installUpdate(); break;
      case "checkUpdate": checkUpdate(true); break;
      case "autoUpdate": S.autoUpdate = tg.checked; localStorage.setItem("suri.autoUpdate", S.autoUpdate ? "1" : "0"); break;
      case "cleanmgr": invoke("open_folder", { path: "cleanmgr.exe" }); break;
    }
  });

  document.addEventListener("change", e => {
    const sel = e.target.closest && e.target.closest("[data-lang]");
    if (sel) changeLang(sel.value);
  });

  document.addEventListener("mouseover", e => {
    const el = e.target.closest(".btn, .zone, .side-row");
    if (el && el !== document._lastHover) { document._lastHover = el; sfx("blip"); }
  });

  window.addEventListener("focus", async () => { if (!S.busy) { await pruneMissing(); await refreshDisk(); render(); } });

  // ───────── start ─────────
  async function start() {
    background();
    await I18n.init();
    localize();
    try { S.platform = await invoke("platform"); S.version = await invoke("app_version"); S.kind = await invoke("install_kind"); } catch (e) { console.error(e); }
    await refreshDisk();
    render();
    T.event.listen("suri-progress", ev => {
      if (!S.busy) return;
      S.busy.detail = msg(ev.payload.text);
      const p = ev.payload.progress;
      if (p != null) S.busy.progress = S.steps > 1 ? (S.busy.step + Math.min(1, Math.max(0, p))) / S.steps : p;
      showBusy();
    });
    setTimeout(() => toast(t("web.music.tap")), 1200);
    setTimeout(() => checkUpdate(false), 4000);
    setInterval(() => checkUpdate(false), 6 * 3600 * 1000);
  }
  start();
})();
