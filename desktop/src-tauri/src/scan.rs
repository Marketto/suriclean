// Scanners for Windows and Linux. Mirrors the logic of the native macOS version.
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

const MB: u64 = 1_048_576;

// ───────────────────────── progress ─────────────────────────

pub type Emit = Arc<dyn Fn(String, Option<f64>) + Send + Sync>;

pub struct Reporter {
    emit: Emit,
    cancel: &'static AtomicBool,
    last: Mutex<Instant>,
}

impl Reporter {
    pub fn new(emit: Emit, cancel: &'static AtomicBool) -> Self {
        Self { emit, cancel, last: Mutex::new(Instant::now() - Duration::from_secs(5)) }
    }
    pub fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }
    pub fn report(&self, text: &str, p: Option<f64>) {
        {
            let mut l = self.last.lock().unwrap();
            if l.elapsed() < Duration::from_millis(80) {
                return;
            }
            *l = Instant::now();
        }
        (self.emit)(text.to_string(), p);
    }
    pub fn report_force(&self, text: &str, p: Option<f64>) {
        *self.last.lock().unwrap() = Instant::now();
        (self.emit)(text.to_string(), p);
    }
}

// ───────────────────────── model ─────────────────────────

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Serialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    pub id: u64,
    pub path: String,
    pub name: String,
    pub detail: String,
    pub size: u64,
    pub date: Option<i64>,
    pub risk: String,
    pub recommended: bool,
    pub badges: Vec<String>,
    pub extra: Vec<String>,
    pub copy_text: Option<String>,
    pub group: Option<u32>,
    pub group_label: Option<String>,
}

fn new_item(path: &Path, name: String, detail: String, size: u64, date: Option<SystemTime>, risk: &str, rec: bool, badges: Vec<String>) -> Item {
    Item {
        id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
        path: path.to_string_lossy().to_string(),
        name,
        detail,
        size,
        date: unix(date),
        risk: risk.to_string(),
        recommended: rec,
        badges,
        ..Default::default()
    }
}

// ───────────────────────── helpers ─────────────────────────

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}
fn local() -> PathBuf {
    dirs::data_local_dir().unwrap_or_else(|| home().join(".local/share"))
}
fn config() -> PathBuf {
    dirs::config_dir().unwrap_or_else(|| home().join(".config"))
}
fn cache() -> PathBuf {
    dirs::cache_dir().unwrap_or_else(|| home().join(".cache"))
}
fn downloads() -> PathBuf {
    dirs::download_dir().unwrap_or_else(|| home().join("Downloads"))
}

fn unix(t: Option<SystemTime>) -> Option<i64> {
    t.and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs() as i64)
}

fn mtime(p: &Path) -> Option<SystemTime> {
    fs::symlink_metadata(p).ok().and_then(|m| m.modified().ok())
}

fn newest(p: &Path, excluding: &[&str]) -> Option<SystemTime> {
    let mut best = mtime(p);
    if let Ok(rd) = fs::read_dir(p) {
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if excluding.contains(&name.as_str()) {
                continue;
            }
            if let Some(t) = mtime(&e.path()) {
                if best.map_or(true, |b| t > b) {
                    best = Some(t);
                }
            }
        }
    }
    best
}

fn days_since(t: Option<SystemTime>) -> u64 {
    match t {
        None => 99_999,
        Some(t) => SystemTime::now().duration_since(t).map(|d| d.as_secs() / 86_400).unwrap_or(0),
    }
}

pub fn rel_time(t: Option<SystemTime>) -> String {
    let Some(t) = t else { return "mai".to_string() };
    let s = SystemTime::now().duration_since(t).map(|d| d.as_secs()).unwrap_or(0);
    let d = s / 86_400;
    if s < 3_600 {
        "poco fa".into()
    } else if d < 1 {
        "oggi".into()
    } else if d < 2 {
        "ieri".into()
    } else if d < 30 {
        format!("{} giorni fa", d)
    } else if d < 365 {
        let m = d / 30;
        if m == 1 { "1 mese fa".into() } else { format!("{} mesi fa", m) }
    } else {
        let y = d / 365;
        if y == 1 { "1 anno fa".into() } else { format!("{} anni fa", y) }
    }
}

pub fn fmt_bytes(b: u64) -> String {
    let units = ["byte", "KB", "MB", "GB", "TB"];
    let mut v = b as f64;
    let mut i = 0;
    while v >= 1000.0 && i < 4 {
        v /= 1000.0;
        i += 1;
    }
    if i == 0 { format!("{} byte", b) } else { format!("{:.1} {}", v, units[i]).replace('.', ",") }
}

pub fn pretty(p: &Path) -> String {
    let h = home();
    match p.strip_prefix(&h) {
        Ok(rest) => {
            let r = rest.to_string_lossy();
            if r.is_empty() { "~".into() } else { format!("~{}{}", std::path::MAIN_SEPARATOR, r) }
        }
        Err(_) => p.to_string_lossy().to_string(),
    }
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| p.to_string_lossy().to_string())
}

/// Files that are only placeholders of cloud storage (OneDrive & co.): reading them would download them.
#[cfg(windows)]
fn is_cloud_placeholder(m: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    let a = m.file_attributes();
    a & 0x0040_0000 != 0 || a & 0x0000_1000 != 0 || a & 0x0004_0000 != 0
}
#[cfg(not(windows))]
fn is_cloud_placeholder(_m: &fs::Metadata) -> bool {
    false
}

/// Real size on disk of a file or folder (symlinks are not followed).
pub fn size_of(p: &Path, rep: Option<&Reporter>) -> u64 {
    let Ok(m) = fs::symlink_metadata(p) else { return 0 };
    if !m.is_dir() {
        return if is_cloud_placeholder(&m) { 0 } else { m.len() };
    }
    let mut total = 0u64;
    for (n, e) in WalkDir::new(p).follow_links(false).into_iter().flatten().enumerate() {
        if n % 500 == 0 {
            if let Some(r) = rep {
                if r.cancelled() {
                    break;
                }
                r.report(&pretty(e.path()), None);
            }
        }
        if e.file_type().is_file() {
            if let Ok(md) = e.metadata() {
                if !is_cloud_placeholder(&md) {
                    total += md.len();
                }
            }
        }
    }
    total
}

fn make_item(p: &Path, name: String, detail: Option<String>, risk: &str, rec: bool, rep: &Reporter, min: u64, badges: Vec<String>, date: Option<SystemTime>) -> Option<Item> {
    if !p.exists() {
        return None;
    }
    rep.report(&pretty(p), None);
    let size = size_of(p, Some(rep));
    if size < min {
        return None;
    }
    let d = date.or_else(|| mtime(p));
    Some(new_item(p, name, detail.unwrap_or_else(|| pretty(p)), size, d, risk, rec, badges))
}

fn children(p: &Path) -> Vec<PathBuf> {
    fs::read_dir(p).map(|rd| rd.flatten().map(|e| e.path()).collect()).unwrap_or_default()
}

fn hidden_cmd(program: &str) -> Command {
    #[allow(unused_mut)]
    let mut c = Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    c
}

// ───────────────────────── fixed targets ─────────────────────────

struct T {
    path: PathBuf,
    name: String,
    risk: &'static str,
    rec: bool,
    per_child: bool,
    older: Option<u64>,
}

fn t(path: PathBuf, name: &str) -> T {
    T { path, name: name.to_string(), risk: "safe", rec: true, per_child: false, older: None }
}
fn review(path: PathBuf, name: &str) -> T {
    T { path, name: name.to_string(), risk: "review", rec: false, per_child: false, older: None }
}
fn per_child(path: PathBuf, name: &str, older: u64) -> T {
    T { path, name: name.to_string(), risk: "review", rec: false, per_child: true, older: Some(older) }
}

fn electron(base: PathBuf, label: &str) -> Vec<T> {
    ["Cache", "CachedData", "Code Cache", "GPUCache", "CachedExtensionVSIXs", "DawnCache", "DawnGraphiteCache", "logs", "Crashpad"]
        .iter()
        .map(|s| t(base.join(s), &format!("{} · {}", label, s)))
        .collect()
}

fn ai_targets() -> Vec<T> {
    let h = home();
    let c = config();
    let mut v = vec![
        per_child(h.join(".claude/projects"), "Claude Code · sessioni", 30),
        t(h.join(".claude/file-history"), "Claude Code · storico file modificati"),
        t(h.join(".claude/shell-snapshots"), "Claude Code · snapshot della shell"),
        t(h.join(".claude/todos"), "Claude Code · liste todo vecchie"),
        t(h.join(".claude/debug"), "Claude Code · log di debug"),
        t(h.join(".claude/statsig"), "Claude Code · cache telemetria"),
        t(h.join(".claude/paste-cache"), "Claude Code · cache incolla"),
        t(cache().join("claude-cli-nodejs"), "Claude Code · log MCP e cache"),
        per_child(h.join(".codex/sessions"), "Codex · sessioni", 30),
        review(h.join(".codex/archived_sessions"), "Codex · sessioni archiviate"),
        t(h.join(".codex/log"), "Codex · log"),
        t(h.join(".gemini/tmp"), "Gemini CLI · temporanei"),
        review(c.join("Claude/vm_bundles"), "Claude Desktop · immagini VM"),
        review(h.join(".cache/huggingface"), "Hugging Face · modelli scaricati"),
        review(h.join(".ollama/models"), "Ollama · modelli"),
        review(h.join(".lmstudio/models"), "LM Studio · modelli"),
        review(h.join(".cache/lm-studio"), "LM Studio · cache"),
        review(h.join(".cache/whisper"), "Whisper · modelli"),
        review(h.join(".cache/torch"), "PyTorch · cache modelli"),
    ];
    if cfg!(windows) {
        v.push(review(local().join("AnthropicClaude/packages"), "Claude Desktop · pacchetti di aggiornamento"));
        v.push(t(local().join("cursor-updater"), "Cursor · aggiornamenti scaricati"));
    }
    v.extend(electron(c.join("Claude"), "Claude Desktop"));
    v.extend(electron(c.join("Cursor"), "Cursor"));
    v.extend(electron(c.join("Code"), "VS Code"));
    v.extend(electron(c.join("Windsurf"), "Windsurf"));
    v
}

fn dev_targets() -> Vec<T> {
    let h = home();
    let l = local();
    let mut v = vec![
        t(h.join(".npm/_cacache"), "npm · cache"),
        t(h.join(".npm/_npx"), "npx · pacchetti temporanei"),
        t(h.join(".yarn/berry/cache"), "Yarn Berry · cache"),
        t(h.join(".bun/install/cache"), "Bun · cache"),
        t(h.join(".gradle/caches"), "Gradle · cache"),
        t(h.join(".gradle/wrapper/dists"), "Gradle · distribuzioni"),
        t(h.join(".m2/repository"), "Maven · repository locale"),
        t(h.join(".cargo/registry"), "Cargo · registry"),
        t(h.join(".cargo/git"), "Cargo · dipendenze git"),
        review(h.join(".rustup/toolchains"), "Rust · toolchain installate"),
        t(h.join("go/pkg/mod"), "Go · moduli"),
        t(h.join(".nuget/packages"), "NuGet · pacchetti"),
        t(h.join(".android/cache"), "Android · cache"),
        review(h.join(".android/avd"), "Android · emulatori"),
        t(h.join(".cache/puppeteer"), "Puppeteer · browser"),
        t(h.join(".cache/pre-commit"), "pre-commit · ambienti"),
    ];
    if cfg!(windows) {
        v.extend([
            t(l.join("npm-cache/_cacache"), "npm · cache"),
            t(l.join("npm-cache/_npx"), "npx · pacchetti temporanei"),
            t(l.join("Yarn/Cache"), "Yarn · cache"),
            t(l.join("pnpm/store"), "pnpm · store"),
            t(l.join("pnpm-cache"), "pnpm · cache"),
            t(l.join("pip/cache"), "Python pip · cache"),
            t(l.join("uv/cache"), "uv · cache Python"),
            t(l.join("go-build"), "Go · cache di build"),
            t(l.join("NuGet/v3-cache"), "NuGet · cache HTTP"),
            t(l.join("NuGet/Cache"), "NuGet · cache"),
            t(l.join("Pub/Cache"), "Dart/Flutter · pub cache"),
            t(l.join("node-gyp/Cache"), "node-gyp · header"),
            t(l.join("ms-playwright"), "Playwright · browser di test"),
            review(l.join("JetBrains"), "JetBrains IDE · cache e indici"),
            T { path: l.join("Docker/wsl"), name: "Docker · disco della VM".into(), risk: "careful", rec: false, per_child: false, older: None },
        ]);
    } else {
        let c = cache();
        v.extend([
            t(c.join("yarn"), "Yarn · cache"),
            t(l.join("pnpm/store"), "pnpm · store"),
            t(c.join("pip"), "Python pip · cache"),
            t(c.join("uv"), "uv · cache Python"),
            t(c.join("go-build"), "Go · cache di build"),
            t(h.join(".pub-cache"), "Dart/Flutter · pub cache"),
            t(c.join("node-gyp"), "node-gyp · header"),
            t(c.join("ms-playwright"), "Playwright · browser di test"),
            review(c.join("JetBrains"), "JetBrains IDE · cache e indici"),
        ]);
    }
    v
}

fn fixed(list: Vec<T>, rep: &Reporter) -> Vec<Item> {
    let mut out = vec![];
    let mut seen = HashSet::new();
    let n = list.len().max(1);
    for (i, t) in list.into_iter().enumerate() {
        if rep.cancelled() {
            break;
        }
        rep.report(&t.name, Some(i as f64 / n as f64));
        if !t.path.exists() || !seen.insert(t.path.clone()) {
            continue;
        }
        if t.per_child {
            for ch in children(&t.path) {
                if rep.cancelled() {
                    break;
                }
                let d = newest(&ch, &[]);
                let old = days_since(d) > t.older.unwrap_or(30);
                let label = pretty_child(&file_name(&ch));
                if let Some(it) = make_item(&ch, format!("{} · {}", t.name, label),
                    Some(format!("{} · ultima modifica {}", pretty(&ch), rel_time(d))),
                    t.risk, old, rep, 100 * 1024,
                    vec![if old { "💤 vecchia".into() } else { "🔥 recente".into() }], d) {
                    out.push(it);
                }
            }
        } else if let Some(it) = make_item(&t.path, t.name.clone(), None, t.risk, t.rec, rep, 512 * 1024, vec![], None) {
            out.push(it);
        }
    }
    out
}

fn pretty_child(s: &str) -> String {
    if s.starts_with('-') {
        let parts: Vec<&str> = s.split('-').filter(|p| !p.is_empty()).collect();
        let k = parts.len();
        return parts[k.saturating_sub(2)..].join("/");
    }
    s.to_string()
}

// ───────────────────────── caches & temp ─────────────────────────

const AI_APPS: [&str; 5] = ["Claude", "Cursor", "Code", "Code - Insiders", "Windsurf"];
const ELECTRON_SUBS: [&str; 8] = ["Cache", "Code Cache", "GPUCache", "CachedData", "DawnCache", "DawnGraphiteCache", "Service Worker/CacheStorage", "Crashpad/completed"];

fn electron_caches(base: &Path, rep: &Reporter, out: &mut Vec<Item>) {
    for app in children(base) {
        if rep.cancelled() || !app.is_dir() {
            continue;
        }
        let an = file_name(&app);
        if AI_APPS.contains(&an.as_str()) {
            continue;
        }
        for s in ELECTRON_SUBS {
            let p = app.join(s);
            if let Some(it) = make_item(&p, format!("{} · {}", an, s), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
    }
}

fn browser_profiles(root: &Path, label: &str, subs: &[&str], rep: &Reporter, out: &mut Vec<Item>) {
    for profile in children(root) {
        if !profile.is_dir() {
            continue;
        }
        for s in subs {
            let p = profile.join(s);
            if let Some(it) = make_item(&p, format!("{} ({}) · {}", label, file_name(&profile), s), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
    }
}

fn caches(rep: &Reporter) -> Vec<Item> {
    let mut out = vec![];
    if cfg!(windows) {
        let l = local();
        for (p, n) in [
            (l.join("Microsoft/Windows/INetCache"), "Windows · cache Internet"),
            (l.join("D3DSCache"), "DirectX · cache shader"),
            (l.join("NVIDIA/DXCache"), "NVIDIA · cache shader"),
            (l.join("NVIDIA/GLCache"), "NVIDIA · cache OpenGL"),
            (l.join("AMD/DxCache"), "AMD · cache shader"),
            (l.join("Microsoft/Edge/User Data/ShaderCache"), "Edge · cache shader"),
        ] {
            if let Some(it) = make_item(&p, n.to_string(), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
        rep.report("Browser…", Some(0.3));
        let subs = ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"];
        browser_profiles(&l.join("Google/Chrome/User Data"), "Chrome", &subs, rep, &mut out);
        browser_profiles(&l.join("Microsoft/Edge/User Data"), "Edge", &subs, rep, &mut out);
        browser_profiles(&l.join("BraveSoftware/Brave-Browser/User Data"), "Brave", &subs, rep, &mut out);
        browser_profiles(&l.join("Mozilla/Firefox/Profiles"), "Firefox", &["cache2"], rep, &mut out);
        rep.report("App…", Some(0.6));
        electron_caches(&config(), rep, &mut out);
        for pkg in children(&l.join("Packages")) {
            if rep.cancelled() {
                break;
            }
            let name = file_name(&pkg);
            let short = name.split('_').next().unwrap_or(&name).to_string();
            for (s, lab) in [("LocalCache", "cache"), ("AC/INetCache", "cache web")] {
                if let Some(it) = make_item(&pkg.join(s), format!("{} · {} (Store)", short, lab), None, "safe", true, rep, 5 * MB, vec![], None) {
                    out.push(it);
                }
            }
        }
    } else {
        let claimed: HashSet<&str> = [
            "pip", "yarn", "uv", "node-gyp", "go-build", "ms-playwright", "huggingface", "whisper", "torch",
            "lm-studio", "puppeteer", "pre-commit", "claude-cli-nodejs", "JetBrains", "suriclean", "com.suriclean.app",
        ].into_iter().collect();
        let kids = children(&cache());
        let n = kids.len().max(1);
        for (i, k) in kids.iter().enumerate() {
            if rep.cancelled() {
                return out;
            }
            let name = file_name(k);
            if claimed.contains(name.as_str()) {
                continue;
            }
            rep.report(&pretty(k), Some(i as f64 / n as f64 * 0.7));
            if let Some(it) = make_item(k, format!("Cache · {}", name), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
        if let Some(it) = make_item(&home().join(".thumbnails"), "Miniature delle immagini".into(), None, "safe", true, rep, MB, vec![], None) {
            out.push(it);
        }
        rep.report("App Electron…", Some(0.8));
        electron_caches(&config(), rep, &mut out);
    }
    out
}

fn logs_temp(rep: &Reporter) -> Vec<Item> {
    let mut out = vec![];
    let mut temps = vec![std::env::temp_dir()];
    if !cfg!(windows) && !temps.iter().any(|p| p == Path::new("/tmp")) {
        temps.push(PathBuf::from("/tmp"));
    }
    #[cfg(unix)]
    let my_uid = {
        use std::os::unix::fs::MetadataExt;
        fs::metadata(home()).map(|m| m.uid()).unwrap_or(u32::MAX)
    };
    for tmp in temps {
        for k in children(&tmp) {
            if rep.cancelled() {
                return out;
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt;
                match fs::symlink_metadata(&k) {
                    Ok(m) if m.uid() == my_uid => {}
                    _ => continue,
                }
            }
            let d = newest(&k, &[]);
            if days_since(d) < 3 {
                continue;
            }
            if let Some(it) = make_item(&k, format!("Temporaneo · {}", file_name(&k)), Some(format!("File temporaneo · {}", rel_time(d))),
                "safe", true, rep, 256 * 1024, vec![], d) {
                out.push(it);
            }
        }
    }
    if cfg!(windows) {
        let l = local();
        for (p, n) in [
            (l.join("CrashDumps"), "Dump dei crash"),
            (l.join("Microsoft/Windows/WER"), "Report errori di Windows"),
            (l.join("Microsoft/Windows/WebCache.old"), "Vecchia cache web"),
        ] {
            if let Some(it) = make_item(&p, n.into(), None, "safe", true, rep, 256 * 1024, vec![], None) {
                out.push(it);
            }
        }
    } else {
        let h = home();
        for (p, n) in [
            (h.join(".xsession-errors.old"), "Log sessione grafica (vecchio)"),
            (h.join(".local/share/xorg"), "Log di Xorg"),
            (h.join(".local/share/recently-used.xbel.bak"), "Backup dei file recenti"),
        ] {
            if let Some(it) = make_item(&p, n.into(), None, "safe", true, rep, 256 * 1024, vec![], None) {
                out.push(it);
            }
        }
    }
    out
}

// ───────────────────────── home index ─────────────────────────

pub struct Indexed {
    path: PathBuf,
    size: u64,
    modified: Option<SystemTime>,
}

#[derive(Default)]
pub struct HomeIndex {
    files: Vec<Indexed>,
    repos: Vec<PathBuf>,
    deps: Vec<(PathBuf, String)>,
}

static INDEX: OnceLock<Mutex<Option<(Instant, Arc<HomeIndex>)>>> = OnceLock::new();

pub fn invalidate_index() {
    *INDEX.get_or_init(|| Mutex::new(None)).lock().unwrap() = None;
}

fn get_index(rep: &Reporter) -> Option<Arc<HomeIndex>> {
    let slot = INDEX.get_or_init(|| Mutex::new(None));
    if let Some((t, idx)) = slot.lock().unwrap().as_ref() {
        if t.elapsed() < Duration::from_secs(900) {
            return Some(idx.clone());
        }
    }
    let idx = Arc::new(build_index(rep));
    if rep.cancelled() {
        return None;
    }
    *slot.lock().unwrap() = Some((Instant::now(), idx.clone()));
    Some(idx)
}

fn dep_kind(dir: &Path) -> Option<&'static str> {
    let name = file_name(dir);
    let parent = dir.parent()?;
    let has = |f: &str| parent.join(f).exists();
    match name.as_str() {
        "node_modules" if has("package.json") => Some("Node.js (npm/yarn/pnpm)"),
        ".venv" | "venv" | "env" if dir.join("pyvenv.cfg").exists() => Some("Python virtualenv"),
        "target" if has("Cargo.toml") => Some("Rust (cargo)"),
        "target" if has("pom.xml") => Some("Maven"),
        ".build" if has("Package.swift") => Some("Swift Package Manager"),
        "Pods" if has("Podfile") => Some("CocoaPods"),
        ".gradle" if has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") => Some("Gradle (cache progetto)"),
        "build" if has("build.gradle") || has("build.gradle.kts") => Some("Gradle (build)"),
        "build" if has("pubspec.yaml") => Some("Flutter (build)"),
        ".next" if has("package.json") => Some("Next.js (build)"),
        ".nuxt" | ".output" if has("nuxt.config.ts") || has("nuxt.config.js") => Some("Nuxt (build)"),
        ".dart_tool" if has("pubspec.yaml") => Some("Dart/Flutter"),
        "vendor" if has("composer.json") => Some("PHP Composer"),
        ".turbo" | ".parcel-cache" | ".angular" if has("package.json") => Some("Cache di build JS"),
        "bin" | "obj" if fs::read_dir(parent).map(|rd| rd.flatten().any(|e| {
            let n = e.file_name().to_string_lossy().to_lowercase();
            n.ends_with(".csproj") || n.ends_with(".fsproj") || n.ends_with(".vbproj")
        })).unwrap_or(false) => Some(".NET (bin/obj)"),
        _ => None,
    }
}

fn build_index(rep: &Reporter) -> HomeIndex {
    let h = home();
    let skip_rel: Vec<PathBuf> = [
        "AppData", ".cache", ".local/share/Trash", ".npm", ".gradle", ".m2", ".cargo", ".rustup", ".pub-cache",
        ".cocoapods", ".claude", ".codex", ".gemini", ".ollama", ".docker", ".android", ".lmstudio", ".vscode",
        ".cursor", ".nvm", ".bun", ".yarn", ".pnpm-store", ".nuget", ".var", "snap", "go/pkg", "OneDrive",
    ].iter().map(|r| h.join(r)).collect();
    let repos = RefCell::new(Vec::new());
    let deps = RefCell::new(Vec::new());
    let mut files = Vec::new();
    let mut count: u64 = 0;
    let walker = WalkDir::new(&h).follow_links(false).into_iter().filter_entry(|e| {
        if e.depth() == 0 {
            return true;
        }
        if !e.file_type().is_dir() {
            return true;
        }
        let p = e.path();
        if skip_rel.iter().any(|s| s == p) {
            return false;
        }
        let name = e.file_name().to_string_lossy();
        if name == ".git" {
            if let Some(parent) = p.parent() {
                if parent != h.as_path() {
                    repos.borrow_mut().push(parent.to_path_buf());
                }
            }
            return false;
        }
        // dependency folders inside hidden tool dirs are installed tools, not project deps
        let inside_hidden = p.strip_prefix(&h).map(|r| {
            let comps: Vec<_> = r.components().collect();
            comps[..comps.len().saturating_sub(1)].iter().any(|c| {
                let s = c.as_os_str().to_string_lossy();
                s.starts_with('.') || s == "AppData"
            })
        }).unwrap_or(true);
        if !inside_hidden {
            if let Some(k) = dep_kind(p) {
                deps.borrow_mut().push((p.to_path_buf(), k.to_string()));
                return false;
            }
        }
        true
    });
    for e in walker.flatten() {
        count += 1;
        if count % 400 == 0 {
            if rep.cancelled() {
                break;
            }
            rep.report(&format!("{} elementi annusati · {}", count, pretty(e.path())), None);
        }
        if e.file_type().is_file() {
            if let Ok(m) = e.metadata() {
                if m.len() >= MB && !is_cloud_placeholder(&m) {
                    files.push(Indexed { path: e.path().to_path_buf(), size: m.len(), modified: m.modified().ok() });
                }
            }
        }
    }
    rep.report_force(&format!("Esplorazione finita: {} elementi", count), None);
    HomeIndex { files, repos: repos.into_inner(), deps: deps.into_inner() }
}

fn project_activity(project: &Path, dep_name: &str) -> Option<SystemTime> {
    let mut best = newest(project, &[dep_name, ".git"]);
    if let Some(t) = mtime(&project.join(".git/index")) {
        if best.map_or(true, |b| t > b) {
            best = Some(t);
        }
    }
    best
}

fn build_deps(idx: &HomeIndex, rep: &Reporter) -> Vec<Item> {
    let mut out = vec![];
    let n = idx.deps.len().max(1);
    for (i, (p, kind)) in idx.deps.iter().enumerate() {
        if rep.cancelled() {
            break;
        }
        rep.report(&pretty(p), Some(i as f64 / n as f64));
        let Some(project) = p.parent() else { continue };
        let active = project_activity(project, &file_name(p));
        let old = days_since(active) > 60;
        if let Some(it) = make_item(p, format!("{} · {}", file_name(project), file_name(p)),
            Some(format!("{} · {} · progetto toccato {}", kind, pretty(project), rel_time(active))),
            "safe", old, rep, MB, vec![if old { "💤 progetto fermo".into() } else { "🔥 progetto attivo".into() }], active) {
            out.push(it);
        }
    }
    out
}

// ───────────────────────── git ─────────────────────────

pub fn git_available() -> bool {
    static G: OnceLock<bool> = OnceLock::new();
    *G.get_or_init(|| hidden_cmd("git").arg("--version").output().map(|o| o.status.success()).unwrap_or(false))
}

fn git(repo: &Path, args: &[&str]) -> (bool, String) {
    let out = hidden_cmd("git")
        .arg("-C").arg(repo).args(args)
        .env("GIT_OPTIONAL_LOCKS", "0").env("GIT_TERMINAL_PROMPT", "0").env("LC_ALL", "C")
        .output();
    match out {
        Ok(o) => (o.status.success(), String::from_utf8_lossy(&o.stdout).trim().to_string()),
        Err(_) => (false, String::new()),
    }
}

const REGENERABLE: [&str; 30] = [
    "node_modules", ".venv", "venv", "env", "target", "build", ".build", "Pods", "DerivedData", ".next", ".nuxt",
    "dist", "out", ".gradle", ".dart_tool", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    ".DS_Store", ".turbo", ".parcel-cache", ".angular", ".cache", "coverage", ".idea", ".vscode", "vendor", "bin", "obj",
];

fn sanitize_remote(r: &str) -> String {
    if let Some(i) = r.find("://") {
        let rest = &r[i + 3..];
        if let Some(at) = rest.find('@') {
            if !rest[..at].contains('/') {
                return format!("{}{}", &r[..i + 3], &rest[at + 1..]);
            }
        }
    }
    r.to_string()
}

fn short_remote(r: &str) -> String {
    let mut s = r.to_string();
    for p in ["https://", "http://", "ssh://", "git@"] {
        if let Some(x) = s.strip_prefix(p) {
            s = x.to_string();
        }
    }
    if let Some(x) = s.strip_suffix(".git") {
        s = x.to_string();
    }
    s.replace(':', "/")
}

fn git_repos(idx: &HomeIndex, rep: &Reporter) -> Vec<Item> {
    if !git_available() {
        return vec![];
    }
    let mut out = vec![];
    let n = idx.repos.len().max(1);
    for (i, repo) in idx.repos.iter().enumerate() {
        if rep.cancelled() {
            break;
        }
        rep.report(&format!("git status · {}", pretty(repo)), Some(i as f64 / n as f64));
        let mut dates: Vec<SystemTime> = vec![];
        let (ok_log, last) = git(repo, &["log", "-1", "--format=%ct"]);
        if ok_log {
            if let Ok(ts) = last.parse::<u64>() {
                dates.push(UNIX_EPOCH + Duration::from_secs(ts));
            }
        }
        for f in ["index", "FETCH_HEAD", "HEAD", "ORIG_HEAD"] {
            if let Some(t) = mtime(&repo.join(".git").join(f)) {
                dates.push(t);
            }
        }
        let activity = dates.into_iter().max();
        let mut remote = {
            let (ok, o) = git(repo, &["remote", "get-url", "origin"]);
            if ok && !o.is_empty() {
                Some(o)
            } else {
                let (_, rs) = git(repo, &["remote"]);
                rs.lines().next().and_then(|first| {
                    let (ok, u) = git(repo, &["remote", "get-url", first]);
                    if ok && !u.is_empty() { Some(u) } else { None }
                })
            }
        };
        if let Some(r) = &remote {
            let network = (r.contains("://") && !r.starts_with("file:")) || r.contains('@');
            if !network {
                remote = None;
            }
        }
        let remote = remote.map(|r| sanitize_remote(&r));
        let (ok_st, st) = git(repo, &["status", "--porcelain", "--untracked-files=normal", "--ignore-submodules=none"]);
        let mut dirty = !ok_st || !st.is_empty();
        let (ok_ign, ign) = git(repo, &["status", "--porcelain", "--ignored", "--untracked-files=normal"]);
        if !ok_ign {
            dirty = true;
        }
        for line in ign.lines().filter(|l| l.starts_with("!! ")) {
            let path = line[3..].trim_matches(|c| c == '"' || c == '/');
            let first = path.split('/').next().unwrap_or("");
            let last_c = path.split('/').last().unwrap_or("");
            if !REGENERABLE.contains(&first) && !REGENERABLE.contains(&last_c) && !last_c.ends_with(".pyc") && !last_c.ends_with(".log") {
                dirty = true;
                break;
            }
        }
        let (ok_up, up) = git(repo, &["log", "--branches", "--tags", "HEAD", "--not", "--remotes", "--oneline", "-n", "99"]);
        let unpushed = if !ok_up { if ok_log { 1 } else { 0 } } else if up.is_empty() { 0 } else { up.lines().count() };
        let (_, stash) = git(repo, &["stash", "list"]);
        let safe = remote.is_some() && !dirty && unpushed == 0 && stash.is_empty();
        let size = size_of(repo, Some(rep));
        if size < MB {
            continue;
        }
        let days = days_since(activity);
        let mut badges = vec![];
        if safe { badges.push("☁️ al sicuro sul remote".to_string()); }
        if remote.is_none() { badges.push("🏠 solo locale".into()); }
        if dirty { badges.push("✏️ modifiche non salvate".into()); }
        if unpushed > 0 { badges.push(format!("⬆️ {} commit non pushati", unpushed)); }
        if !stash.is_empty() { badges.push("📦 stash".into()); }
        if days > 365 { badges.push("🦕 fermo da 1+ anno".into()); }
        let risk = if safe { "safe" } else if remote.is_some() { "review" } else { "careful" };
        let mut detail = format!("{} · ultima attività {}", pretty(repo), rel_time(activity));
        if let Some(r) = &remote {
            detail += &format!(" · {}", short_remote(r));
        }
        let mut it = new_item(repo, file_name(repo), detail, size, activity, risk, safe && days > 180, badges);
        it.copy_text = remote.map(|r| format!("git clone {} \"{}\"", r, repo.to_string_lossy()));
        out.push(it);
    }
    out
}

pub fn append_repo_log(lines: &[String]) -> Option<String> {
    let docs = dirs::document_dir().unwrap_or_else(home);
    let path = docs.join("SuriClean - repo rimossi.txt");
    let mut text = String::new();
    if !path.exists() {
        text.push_str("# Repo spostati nel Cestino da SuriClean.\n# Per riaverli basta lanciare il comando git clone sotto ciascuno.\n\n");
    }
    text.push_str(&lines.join("\n\n"));
    text.push_str("\n\n");
    use std::io::Write;
    let mut f = fs::OpenOptions::new().create(true).append(true).open(&path).ok()?;
    f.write_all(text.as_bytes()).ok()?;
    Some(path.to_string_lossy().to_string())
}

// ───────────────────────── duplicates ─────────────────────────

fn hex(d: &[u8]) -> String {
    d.iter().map(|b| format!("{:02x}", b)).collect()
}

fn partial_hash(p: &Path) -> Option<String> {
    let mut f = fs::File::open(p).ok()?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 65_536];
    let n = f.read(&mut buf).ok()?;
    h.update(&buf[..n]);
    let len = f.metadata().ok()?.len();
    if len > 131_072 {
        f.seek(SeekFrom::Start(len - 65_536)).ok()?;
        let n = f.read(&mut buf).ok()?;
        h.update(&buf[..n]);
    }
    Some(hex(&h.finalize()))
}

fn full_hash(p: &Path, rep: &Reporter) -> Option<String> {
    let mut f = fs::File::open(p).ok()?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        if rep.cancelled() {
            return None;
        }
        let n = f.read(&mut buf).ok()?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Some(hex(&h.finalize()))
}

fn keep_score(p: &Path) -> usize {
    let s = p.to_string_lossy().to_lowercase();
    let mut score = p.components().count() * 10;
    if s.contains("download") || s.contains("desktop") || s.contains("scrivania") {
        score += 1000;
    }
    let n = file_name(p).to_lowercase();
    if n.contains("copy") || n.contains("copia") || n.contains(" (1)") || n.contains(" (2)") || n.contains(" - copia") {
        score += 500;
    }
    score
}

fn duplicates(idx: &HomeIndex, rep: &Reporter) -> Vec<Item> {
    let mut by_size: HashMap<u64, Vec<&Indexed>> = HashMap::new();
    for f in &idx.files {
        by_size.entry(f.size).or_default().push(f);
    }
    let groups: Vec<Vec<&Indexed>> = by_size.into_values().filter(|g| g.len() > 1).collect();
    let mut candidates: Vec<Vec<&Indexed>> = vec![];
    let n = groups.len().max(1);
    for (i, g) in groups.iter().enumerate() {
        if rep.cancelled() {
            return vec![];
        }
        rep.report(&format!("Confronto impronte: {}", file_name(&g[0].path)), Some(i as f64 / n as f64 * 0.4));
        let mut by_p: HashMap<String, Vec<&Indexed>> = HashMap::new();
        for f in g {
            if let Some(h) = partial_hash(&f.path) {
                by_p.entry(h).or_default().push(f);
            }
        }
        candidates.extend(by_p.into_values().filter(|g| g.len() > 1));
    }
    let mut finals: Vec<Vec<&Indexed>> = vec![];
    let n = candidates.len().max(1);
    for (i, g) in candidates.iter().enumerate() {
        if rep.cancelled() {
            return vec![];
        }
        rep.report(&format!("SHA-256 di {}", file_name(&g[0].path)), Some(0.4 + i as f64 / n as f64 * 0.6));
        let mut by_f: HashMap<String, Vec<&Indexed>> = HashMap::new();
        for f in g {
            if let Some(h) = full_hash(&f.path, rep) {
                by_f.entry(h).or_default().push(f);
            }
        }
        finals.extend(by_f.into_values().filter(|g| g.len() > 1));
    }
    finals.sort_by(|a, b| (b[0].size * b.len() as u64).cmp(&(a[0].size * a.len() as u64)));
    let mut out = vec![];
    for (gid, mut g) in finals.into_iter().enumerate() {
        g.sort_by_key(|f| keep_score(&f.path));
        let label = format!("{} · {} copie da {}", file_name(&g[0].path), g.len(), fmt_bytes(g[0].size));
        for (j, f) in g.iter().enumerate() {
            let keep = j == 0;
            let mut it = new_item(&f.path, file_name(&f.path),
                f.path.parent().map(pretty).unwrap_or_default(), f.size, f.modified,
                if keep { "careful" } else { "safe" }, !keep,
                vec![if keep { "💎 da tenere".into() } else { "👯 copia".into() }]);
            it.group = Some(gid as u32);
            it.group_label = Some(label.clone());
            out.push(it);
        }
    }
    out
}

// ───────────────────────── big files, installers, downloads ─────────────────────────

fn badge_for_ext(ext: &str) -> Option<&'static str> {
    match ext {
        "mov" | "mp4" | "mkv" | "avi" | "m4v" | "webm" => Some("🎬 video"),
        "zip" | "rar" | "7z" | "tar" | "gz" | "tgz" | "bz2" | "xz" | "zst" => Some("📦 archivio"),
        "iso" | "img" | "dmg" => Some("💿 immagine disco"),
        "vmdk" | "vdi" | "vhd" | "vhdx" | "qcow2" => Some("🖥️ macchina virtuale"),
        "psd" | "ai" | "blend" | "kra" => Some("🎨 grafica"),
        "wav" | "flac" | "aiff" => Some("🎵 audio"),
        _ => None,
    }
}

fn ext_of(p: &Path) -> String {
    p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

fn big_files(idx: &HomeIndex) -> Vec<Item> {
    let mut big: Vec<&Indexed> = idx.files.iter().filter(|f| f.size >= 100 * MB).collect();
    big.sort_by(|a, b| b.size.cmp(&a.size));
    big.into_iter().take(250).map(|f| {
        let badges = badge_for_ext(&ext_of(&f.path)).map(|b| vec![b.to_string()]).unwrap_or_default();
        new_item(&f.path, file_name(&f.path),
            format!("{} · modificato {}", f.path.parent().map(pretty).unwrap_or_default(), rel_time(f.modified)),
            f.size, f.modified, "careful", false, badges)
    }).collect()
}

fn installers(idx: &HomeIndex) -> Vec<Item> {
    let dl = downloads();
    let desk = dirs::desktop_dir().unwrap_or_else(|| home().join("Desktop"));
    let mut out = vec![];
    for f in &idx.files {
        let ext = ext_of(&f.path);
        let in_dl = f.path.starts_with(&dl);
        let in_desk = f.path.starts_with(&desk);
        let image = ext == "iso";
        let (is_inst, only_downloads) = if cfg!(windows) {
            match ext.as_str() {
                "msi" | "msix" | "msixbundle" | "appx" | "iso" => (true, false),
                "exe" => (true, true),
                _ => (false, false),
            }
        } else {
            match ext.as_str() {
                "deb" | "rpm" | "run" | "snap" | "flatpakref" | "iso" => (true, false),
                "appimage" => (true, false),
                _ => (false, false),
            }
        };
        if !is_inst || (only_downloads && !(in_dl || in_desk)) {
            continue;
        }
        let rec = if image { in_dl && days_since(f.modified) > 30 } else if ext == "appimage" { false } else { in_dl || in_desk };
        let badge = if image { "💿 immagine disco" } else if ext == "appimage" { "📲 AppImage (forse la usi?)" } else { "📦 installer" };
        out.push(new_item(&f.path, file_name(&f.path),
            format!("{} · {}", f.path.parent().map(pretty).unwrap_or_default(), rel_time(f.modified)),
            f.size, f.modified, if rec { "safe" } else { "review" }, rec, vec![badge.into()]));
    }
    out
}

fn old_downloads(rep: &Reporter) -> Vec<Item> {
    let kids = children(&downloads());
    let n = kids.len().max(1);
    let mut out = vec![];
    for (i, k) in kids.iter().enumerate() {
        if rep.cancelled() {
            break;
        }
        let name = file_name(k);
        if name == "desktop.ini" || name == ".DS_Store" {
            continue;
        }
        rep.report(&pretty(k), Some(i as f64 / n as f64));
        let d = newest(k, &[]);
        let days = days_since(d);
        if days < 90 {
            continue;
        }
        if let Some(it) = make_item(k, name, Some(format!("Scaricato {}", rel_time(d))), "review", false, rep, 100 * 1024,
            if days > 365 { vec!["🦕 più di un anno".into()] } else { vec![] }, d) {
            out.push(it);
        }
    }
    out
}

// ───────────────────────── disk map ─────────────────────────

/// Every folder >= 300 MB down to 4 levels below Home (view-only).
fn disk_map(rep: &Reporter) -> Vec<Item> {
    let h = home();
    let base = h.components().count();
    let mut sizes: HashMap<PathBuf, u64> = HashMap::new();
    let mut total = 0u64;
    let mut n = 0u64;
    for e in WalkDir::new(&h).follow_links(false).into_iter().flatten() {
        n += 1;
        if n % 500 == 0 {
            if rep.cancelled() {
                return vec![];
            }
            rep.report(&format!("{} elementi misurati · {}", n, pretty(e.path())), None);
        }
        if !e.file_type().is_file() {
            continue;
        }
        let Ok(m) = e.metadata() else { continue };
        if is_cloud_placeholder(&m) {
            continue;
        }
        let sz = m.len();
        total += sz;
        let mut anc = e.path().parent();
        while let Some(a) = anc {
            let depth = a.components().count();
            if depth <= base {
                break;
            }
            if depth <= base + 4 {
                *sizes.entry(a.to_path_buf()).or_default() += sz;
            }
            anc = a.parent();
        }
    }
    let mut out = vec![new_item(&h, "La tua cartella Inizio".into(), "~".into(), total, None, "careful", false, vec!["🏡 la tana".into()])];
    for (p, s) in sizes {
        let depth = p.components().count() - base;
        let threshold = if depth == 1 { 50 * MB } else { 300 * MB };
        if s >= threshold {
            out.push(new_item(&p, file_name(&p), pretty(&p), s, None, "careful", false, vec![]));
        }
    }
    out
}

// ───────────────────────── dispatch ─────────────────────────

pub fn scan(category: &str, rep: &Reporter) -> Vec<Item> {
    let needs_index = matches!(category, "buildDeps" | "gitRepos" | "duplicates" | "bigFiles" | "installers");
    let idx = if needs_index {
        match get_index(rep) {
            Some(i) => Some(i),
            None => return vec![],
        }
    } else {
        None
    };
    match (category, idx) {
        ("diskMap", _) => disk_map(rep),
        ("caches", _) => caches(rep),
        ("logsTemp", _) => logs_temp(rep),
        ("aiTools", _) => fixed(ai_targets(), rep),
        ("devCaches", _) => fixed(dev_targets(), rep),
        ("oldDownloads", _) => old_downloads(rep),
        ("buildDeps", Some(i)) => build_deps(&i, rep),
        ("gitRepos", Some(i)) => git_repos(&i, rep),
        ("duplicates", Some(i)) => duplicates(&i, rep),
        ("bigFiles", Some(i)) => big_files(&i),
        ("installers", Some(i)) => installers(&i),
        _ => vec![],
    }
}

// ───────────────────────── trash & shell ─────────────────────────

pub fn trash_size() -> u64 {
    if cfg!(windows) {
        match trash::os_limited::list() {
            Ok(items) => items.iter().map(|it| match trash::os_limited::metadata(it) {
                Ok(m) => match m.size {
                    trash::TrashItemSize::Bytes(b) => b,
                    trash::TrashItemSize::Entries(_) => 0,
                },
                Err(_) => 0,
            }).sum(),
            Err(_) => 0,
        }
    } else {
        let base = dirs::data_local_dir().unwrap_or_else(|| home().join(".local/share")).join("Trash/files");
        size_of(&base, None)
    }
}

pub fn empty_trash() -> Result<(), String> {
    let items = trash::os_limited::list().map_err(|e| e.to_string())?;
    if items.is_empty() {
        return Ok(());
    }
    trash::os_limited::purge_all(items).map_err(|e| e.to_string())
}

pub fn reveal(p: &Path) {
    if cfg!(windows) {
        let _ = hidden_cmd("explorer").arg(format!("/select,{}", p.to_string_lossy())).spawn();
    } else {
        let uri = format!("array:string:file://{}", p.to_string_lossy());
        let ok = Command::new("dbus-send")
            .args(["--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
                   "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", &uri, "string:"])
            .status().map(|s| s.success()).unwrap_or(false);
        if !ok {
            open_path(p.parent().unwrap_or(p));
        }
    }
}

pub fn open_path(p: &Path) {
    if cfg!(windows) {
        let _ = hidden_cmd("explorer").arg(p).spawn();
    } else {
        let _ = Command::new("xdg-open").arg(p).spawn();
    }
}

pub fn open_url(u: &str) {
    if cfg!(windows) {
        let _ = hidden_cmd("explorer").arg(u).spawn();
    } else {
        let _ = Command::new("xdg-open").arg(u).spawn();
    }
}
