/* SuriClean translations for the desktop app (Tauri) and the website.
   Loads i18n/<code>.json (flat {key: text}); falls back to English, then Italian, then the key itself.
   Exposes window.I18n: init(), setLang(code|null), t(key, ...args), tp(keyBase, n, ...args), msg(token, fmt). */
(function () {
  const FALLBACK_LANGS = [{ code: "it", name: "Italiano" }, { code: "en", name: "English" }];
  let langs = FALLBACK_LANGS, code = "it", chosen = null, dict = {}, en = {}, it = {};

  const store = {
    get() { try { return localStorage.getItem("suri.lang"); } catch (e) { return null; } },
    set(v) { try { v ? localStorage.setItem("suri.lang", v) : localStorage.removeItem("suri.lang"); } catch (e) { } },
  };

  async function fetchJSON(path) {
    try {
      const r = await fetch(path, { cache: "no-cache" });
      if (!r.ok) return null;
      return await r.json();
    } catch (e) { return null; }
  }

  function has(c) { return langs.some(l => l.code === c); }

  /** Best match of the system languages against the available ones. */
  function detect() {
    const prefs = (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"]).map(s => String(s).toLowerCase());
    for (const p of prefs) {
      let c;
      if (p.startsWith("zh")) c = /hant|tw|hk|mo/.test(p) ? "zh-Hant" : "zh-Hans";
      else {
        const pre = p.split(/[-_]/)[0];
        c = { no: "nb", nn: "nb", nb: "nb", iw: "he", in: "id" }[pre] || pre;
      }
      if (has(c)) return c;
    }
    return has("en") ? "en" : "it";
  }

  function isRTL(c) { const l = langs.find(x => x.code === (c || code)); return !!(l && l.rtl); }

  function apply() {
    const root = document.documentElement;
    root.lang = code;
    root.dir = isRTL() ? "rtl" : "ltr";
  }

  async function loadDict() {
    const [d, e, i] = await Promise.all([
      code === "en" || code === "it" ? Promise.resolve(null) : fetchJSON(`i18n/${code}.json`),
      fetchJSON("i18n/en.json"),
      fetchJSON("i18n/it.json"),
    ]);
    en = e || {}; it = i || {};
    dict = code === "en" ? en : code === "it" ? it : (d || {});
  }

  async function init() {
    const l = await fetchJSON("i18n/languages.json");
    if (Array.isArray(l) && l.length) langs = l;
    chosen = store.get();
    if (chosen && !has(chosen)) chosen = null;
    code = chosen || detect();
    await loadDict();
    apply();
  }

  /** null = follow the system language. */
  async function setLang(c) {
    chosen = c && has(c) ? c : null;
    store.set(chosen);
    code = chosen || detect();
    await loadDict();
    apply();
  }

  function t(key, ...args) {
    const s = dict[key] ?? en[key] ?? it[key] ?? key;
    return String(s).replace(/\{(\d+)\}/g, (m, i) => (args[i] ?? ""));
  }

  function tp(base, n, ...args) {
    return t(`${base}.${n === 1 ? "one" : "other"}`, ...args);
  }

  /** Messages built by the Rust backend: "\u0001" + JSON [key, [args]]; args may be messages
      themselves or byte counts "\u0003<n>" (formatted with fmt.bytes). Plain strings pass through. */
  function msg(s, fmt) {
    if (typeof s !== "string") return s;
    if (s.charCodeAt(0) === 3) return fmt && fmt.bytes ? fmt.bytes(Number(s.slice(1))) : s.slice(1);
    if (s.charCodeAt(0) !== 1) return s;
    try {
      const [key, args] = JSON.parse(s.slice(1));
      return t(key, ...(args || []).map(a => msg(a, fmt)));
    } catch (e) { return s; }
  }

  /** Decimal number in the current language (e.g. 1,5 or 1.5). */
  function num(v, digits) {
    try { return new Intl.NumberFormat(code, { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v); }
    catch (e) { return v.toFixed(digits); }
  }

  window.I18n = {
    init, setLang, t, tp, msg, num, isRTL,
    get lang() { return code; },
    get chosen() { return chosen; },
    get languages() { return langs; },
  };
})();
