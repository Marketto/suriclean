// Scanners for Windows and Linux. Mirrors the logic of the native macOS version.
use serde::{Deserialize, Serialize};
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

// ───────────────────────── messages ─────────────────────────

/// A message the UI translates: "\u{1}" + JSON [key, [args…]]. Args may be messages themselves,
/// or byte counts made with `mb` ("\u{3}<n>") that the UI formats in the user's language.
pub fn m(key: &str, args: &[&str]) -> String {
    let a: Vec<&str> = args.to_vec();
    format!("\u{1}{}", serde_json::to_string(&(key, a)).unwrap_or_default())
}

/// A byte count for a message argument.
pub fn mb(b: u64) -> String {
    format!("\u{3}{}", b)
}

// ───────────────────────── model ─────────────────────────

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Serialize, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase", default)]
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
    /// Lives in a system area: removed for good by an administrator, not moved to the Trash.
    pub admin: bool,
    /// Removed by running this command as administrator instead of deleting the path.
    pub cmd: Option<String>,
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
    let Some(t) = t else { return m("web.rs.never", &[]) };
    let s = SystemTime::now().duration_since(t).map(|d| d.as_secs()).unwrap_or(0);
    let d = s / 86_400;
    if s < 3_600 {
        m("web.rs.just_now", &[])
    } else if d < 1 {
        m("web.rs.today", &[])
    } else if d < 2 {
        m("web.rs.yesterday", &[])
    } else if d < 30 {
        m("web.rs.days_ago", &[&d.to_string()])
    } else if d < 365 {
        let mo = d / 30;
        m(if mo == 1 { "web.rs.months_ago.one" } else { "web.rs.months_ago.other" }, &[&mo.to_string()])
    } else {
        let y = d / 365;
        m(if y == 1 { "web.rs.years_ago.one" } else { "web.rs.years_ago.other" }, &[&y.to_string()])
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
        per_child(h.join(".claude/projects"), &m("web.rs.ai.cc_sessions", &[]), 30),
        t(h.join(".claude/file-history"), &m("web.rs.ai.cc_file_history", &[])),
        t(h.join(".claude/shell-snapshots"), &m("web.rs.ai.cc_shell_snapshots", &[])),
        t(h.join(".claude/todos"), &m("web.rs.ai.cc_todos", &[])),
        t(h.join(".claude/debug"), &m("web.rs.ai.cc_debug", &[])),
        t(h.join(".claude/statsig"), &m("web.rs.ai.cc_statsig", &[])),
        t(h.join(".claude/paste-cache"), &m("web.rs.ai.cc_paste", &[])),
        t(cache().join("claude-cli-nodejs"), &m("web.rs.ai.cc_mcp", &[])),
        per_child(h.join(".codex/sessions"), &m("web.rs.ai.codex_sessions", &[]), 30),
        review(h.join(".codex/archived_sessions"), &m("web.rs.ai.codex_archived", &[])),
        t(h.join(".codex/log"), &m("web.rs.ai.codex_log", &[])),
        t(h.join(".gemini/tmp"), &m("web.rs.ai.gemini_tmp", &[])),
        review(c.join("Claude/vm_bundles"), &m("web.rs.ai.claude_vm", &[])),
        review(h.join(".cache/huggingface"), &m("web.rs.ai.hf", &[])),
        review(h.join(".ollama/models"), &m("web.rs.ai.ollama", &[])),
        review(h.join(".lmstudio/models"), &m("web.rs.ai.lmstudio", &[])),
        review(h.join(".cache/lm-studio"), &m("web.rs.ai.lmstudio_cache", &[])),
        review(h.join(".cache/whisper"), &m("web.rs.ai.whisper", &[])),
        review(h.join(".cache/torch"), &m("web.rs.ai.torch", &[])),
    ];
    if cfg!(windows) {
        v.push(review(local().join("AnthropicClaude/packages"), &m("web.rs.ai.claude_pkgs", &[])));
        v.push(t(local().join("cursor-updater"), &m("web.rs.ai.cursor_updates", &[])));
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
        t(h.join(".npm/_cacache"), &m("web.rs.dev.npm", &[])),
        t(h.join(".npm/_npx"), &m("web.rs.dev.npx", &[])),
        t(h.join(".yarn/berry/cache"), &m("web.rs.dev.yarn_berry", &[])),
        t(h.join(".bun/install/cache"), &m("web.rs.dev.bun", &[])),
        t(h.join(".gradle/caches"), &m("web.rs.dev.gradle", &[])),
        t(h.join(".gradle/wrapper/dists"), &m("web.rs.dev.gradle_dists", &[])),
        t(h.join(".m2/repository"), &m("web.rs.dev.maven", &[])),
        t(h.join(".cargo/registry"), &m("web.rs.dev.cargo_registry", &[])),
        t(h.join(".cargo/git"), &m("web.rs.dev.cargo_git", &[])),
        review(h.join(".rustup/toolchains"), &m("web.rs.dev.rustup", &[])),
        t(h.join("go/pkg/mod"), &m("web.rs.dev.go_mod", &[])),
        t(h.join(".nuget/packages"), &m("web.rs.dev.nuget", &[])),
        t(h.join(".android/cache"), &m("web.rs.dev.android_cache", &[])),
        review(h.join(".android/avd"), &m("web.rs.dev.android_avd", &[])),
        t(h.join(".cache/puppeteer"), &m("web.rs.dev.puppeteer", &[])),
        t(h.join(".cache/pre-commit"), &m("web.rs.dev.precommit", &[])),
    ];
    if cfg!(windows) {
        v.extend([
            t(l.join("npm-cache/_cacache"), &m("web.rs.dev.npm", &[])),
            t(l.join("npm-cache/_npx"), &m("web.rs.dev.npx", &[])),
            t(l.join("Yarn/Cache"), &m("web.rs.dev.yarn", &[])),
            t(l.join("pnpm/store"), &m("web.rs.dev.pnpm_store", &[])),
            t(l.join("pnpm-cache"), &m("web.rs.dev.pnpm_cache", &[])),
            t(l.join("pip/cache"), &m("web.rs.dev.pip", &[])),
            t(l.join("uv/cache"), &m("web.rs.dev.uv", &[])),
            t(l.join("go-build"), &m("web.rs.dev.go_build", &[])),
            t(l.join("NuGet/v3-cache"), &m("web.rs.dev.nuget_http", &[])),
            t(l.join("NuGet/Cache"), &m("web.rs.dev.nuget_cache", &[])),
            t(l.join("Pub/Cache"), &m("web.rs.dev.pub", &[])),
            t(l.join("node-gyp/Cache"), &m("web.rs.dev.nodegyp", &[])),
            t(l.join("ms-playwright"), &m("web.rs.dev.playwright", &[])),
            review(l.join("JetBrains"), &m("web.rs.dev.jetbrains", &[])),
            T { path: l.join("Docker/wsl"), name: m("web.rs.dev.docker_vm", &[]), risk: "careful", rec: false, per_child: false, older: None },
        ]);
    } else {
        let c = cache();
        v.extend([
            t(c.join("yarn"), &m("web.rs.dev.yarn", &[])),
            t(l.join("pnpm/store"), &m("web.rs.dev.pnpm_store", &[])),
            t(c.join("pip"), &m("web.rs.dev.pip", &[])),
            t(c.join("uv"), &m("web.rs.dev.uv", &[])),
            t(c.join("go-build"), &m("web.rs.dev.go_build", &[])),
            t(h.join(".pub-cache"), &m("web.rs.dev.pub", &[])),
            t(c.join("node-gyp"), &m("web.rs.dev.nodegyp", &[])),
            t(c.join("ms-playwright"), &m("web.rs.dev.playwright", &[])),
            review(c.join("JetBrains"), &m("web.rs.dev.jetbrains", &[])),
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
                if let Some(it) = make_item(&ch, m("web.rs.join", &[&t.name, &label]),
                    Some(m("web.rs.last_modified", &[&pretty(&ch), &rel_time(d)])),
                    t.risk, old, rep, 100 * 1024,
                    vec![if old { m("web.rs.badge.old", &[]) } else { m("web.rs.badge.recent", &[]) }], d) {
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
            (l.join("Microsoft/Windows/INetCache"), m("web.rs.cache.inet", &[])),
            (l.join("D3DSCache"), m("web.rs.cache.d3d", &[])),
            (l.join("NVIDIA/DXCache"), m("web.rs.cache.nv_dx", &[])),
            (l.join("NVIDIA/GLCache"), m("web.rs.cache.nv_gl", &[])),
            (l.join("AMD/DxCache"), m("web.rs.cache.amd", &[])),
            (l.join("Microsoft/Edge/User Data/ShaderCache"), m("web.rs.cache.edge_shader", &[])),
        ] {
            if let Some(it) = make_item(&p, n.clone(), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
        rep.report(&m("web.rs.p.browsers", &[]), Some(0.3));
        let subs = ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"];
        browser_profiles(&l.join("Google/Chrome/User Data"), "Chrome", &subs, rep, &mut out);
        browser_profiles(&l.join("Microsoft/Edge/User Data"), "Edge", &subs, rep, &mut out);
        browser_profiles(&l.join("BraveSoftware/Brave-Browser/User Data"), "Brave", &subs, rep, &mut out);
        browser_profiles(&l.join("Mozilla/Firefox/Profiles"), "Firefox", &["cache2"], rep, &mut out);
        rep.report(&m("web.rs.p.apps", &[]), Some(0.6));
        electron_caches(&config(), rep, &mut out);
        for pkg in children(&l.join("Packages")) {
            if rep.cancelled() {
                break;
            }
            let name = file_name(&pkg);
            let short = name.split('_').next().unwrap_or(&name).to_string();
            for (s, lab) in [("LocalCache", "web.rs.store_cache"), ("AC/INetCache", "web.rs.store_webcache")] {
                if let Some(it) = make_item(&pkg.join(s), m(lab, &[&short]), None, "safe", true, rep, 5 * MB, vec![], None) {
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
            if let Some(it) = make_item(k, m("web.rs.cache_of", &[&name]), None, "safe", true, rep, MB, vec![], None) {
                out.push(it);
            }
        }
        if let Some(it) = make_item(&home().join(".thumbnails"), m("web.rs.thumbnails", &[]), None, "safe", true, rep, MB, vec![], None) {
            out.push(it);
        }
        rep.report(&m("web.rs.p.electron", &[]), Some(0.8));
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
            if let Some(it) = make_item(&k, m("web.rs.temp_item", &[&file_name(&k)]), Some(m("web.rs.temp_detail", &[&rel_time(d)])),
                "safe", true, rep, 256 * 1024, vec![], d) {
                out.push(it);
            }
        }
    }
    if cfg!(windows) {
        let l = local();
        for (p, n) in [
            (l.join("CrashDumps"), m("web.rs.crash_dumps", &[])),
            (l.join("Microsoft/Windows/WER"), m("web.rs.wer_user", &[])),
            (l.join("Microsoft/Windows/WebCache.old"), m("web.rs.webcache_old", &[])),
        ] {
            if let Some(it) = make_item(&p, n.clone(), None, "safe", true, rep, 256 * 1024, vec![], None) {
                out.push(it);
            }
        }
    } else {
        let h = home();
        for (p, n) in [
            (h.join(".xsession-errors.old"), m("web.rs.xsession_old", &[])),
            (h.join(".local/share/xorg"), m("web.rs.xorg_log", &[])),
            (h.join(".local/share/recently-used.xbel.bak"), m("web.rs.recent_bak", &[])),
        ] {
            if let Some(it) = make_item(&p, n.clone(), None, "safe", true, rep, 256 * 1024, vec![], None) {
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

fn dep_kind(dir: &Path) -> Option<String> {
    let name = file_name(dir);
    let parent = dir.parent()?;
    let has = |f: &str| parent.join(f).exists();
    match name.as_str() {
        "node_modules" if has("package.json") => Some("Node.js (npm/yarn/pnpm)".into()),
        ".venv" | "venv" | "env" if dir.join("pyvenv.cfg").exists() => Some("Python virtualenv".into()),
        "target" if has("Cargo.toml") => Some("Rust (cargo)".into()),
        "target" if has("pom.xml") => Some("Maven".into()),
        ".build" if has("Package.swift") => Some("Swift Package Manager".into()),
        "Pods" if has("Podfile") => Some("CocoaPods".into()),
        ".gradle" if has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") => Some(m("web.rs.dep.gradle_cache", &[])),
        "build" if has("build.gradle") || has("build.gradle.kts") => Some("Gradle (build)".into()),
        "build" if has("pubspec.yaml") => Some("Flutter (build)".into()),
        ".next" if has("package.json") => Some("Next.js (build)".into()),
        ".nuxt" | ".output" if has("nuxt.config.ts") || has("nuxt.config.js") => Some("Nuxt (build)".into()),
        ".dart_tool" if has("pubspec.yaml") => Some("Dart/Flutter".into()),
        "vendor" if has("composer.json") => Some("PHP Composer".into()),
        ".turbo" | ".parcel-cache" | ".angular" if has("package.json") => Some(m("web.rs.dep.js_build", &[])),
        "bin" | "obj" if fs::read_dir(parent).map(|rd| rd.flatten().any(|e| {
            let n = e.file_name().to_string_lossy().to_lowercase();
            n.ends_with(".csproj") || n.ends_with(".fsproj") || n.ends_with(".vbproj")
        })).unwrap_or(false) => Some(".NET (bin/obj)".into()),
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
                deps.borrow_mut().push((p.to_path_buf(), k));
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
            rep.report(&m("web.rs.p.sniffed", &[&count.to_string(), &pretty(e.path())]), None);
        }
        if e.file_type().is_file() {
            if let Ok(m) = e.metadata() {
                if m.len() >= MB && !is_cloud_placeholder(&m) {
                    files.push(Indexed { path: e.path().to_path_buf(), size: m.len(), modified: m.modified().ok() });
                }
            }
        }
    }
    rep.report_force(&m("web.rs.p.explored", &[&count.to_string()]), None);
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
            Some(m("web.rs.dep_detail", &[kind, &pretty(project), &rel_time(active)])),
            "safe", old, rep, MB, vec![if old { m("web.rs.badge.project_idle", &[]) } else { m("web.rs.badge.project_active", &[]) }], active) {
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
        if safe { badges.push(m("web.rs.git.safe", &[])); }
        if remote.is_none() { badges.push(m("web.rs.git.local_only", &[])); }
        if dirty { badges.push(m("web.rs.git.dirty", &[])); }
        if unpushed > 0 { badges.push(m(if unpushed == 1 { "web.rs.git.unpushed.one" } else { "web.rs.git.unpushed.other" }, &[&unpushed.to_string()])); }
        if !stash.is_empty() { badges.push("📦 stash".into()); }
        if days > 365 { badges.push(m("web.rs.git.idle_year", &[])); }
        let risk = if safe { "safe" } else if remote.is_some() { "review" } else { "careful" };
        let mut detail = m("web.rs.git.detail", &[&pretty(repo), &rel_time(activity)]);
        if let Some(r) = &remote {
            detail = m("web.rs.join", &[&detail, &short_remote(r)]);
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
        rep.report(&m("web.rs.p.fingerprints", &[&file_name(&g[0].path)]), Some(i as f64 / n as f64 * 0.4));
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
        rep.report(&m("web.rs.p.sha", &[&file_name(&g[0].path)]), Some(0.4 + i as f64 / n as f64 * 0.6));
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
        let label = m("web.rs.dup_label", &[&file_name(&g[0].path), &g.len().to_string(), &mb(g[0].size)]);
        for (j, f) in g.iter().enumerate() {
            let keep = j == 0;
            let mut it = new_item(&f.path, file_name(&f.path),
                f.path.parent().map(pretty).unwrap_or_default(), f.size, f.modified,
                if keep { "careful" } else { "safe" }, !keep,
                vec![if keep { m("web.rs.badge.keep", &[]) } else { m("web.rs.badge.copy", &[]) }]);
            it.group = Some(gid as u32);
            it.group_label = Some(label.clone());
            out.push(it);
        }
    }
    out
}

// ───────────────────────── big files, installers, downloads ─────────────────────────

fn badge_for_ext(ext: &str) -> Option<String> {
    let k = match ext {
        "mov" | "mp4" | "mkv" | "avi" | "m4v" | "webm" => "web.rs.ext.video",
        "zip" | "rar" | "7z" | "tar" | "gz" | "tgz" | "bz2" | "xz" | "zst" => "web.rs.ext.archive",
        "iso" | "img" | "dmg" => "web.rs.ext.disk_image",
        "vmdk" | "vdi" | "vhd" | "vhdx" | "qcow2" => "web.rs.ext.vm",
        "psd" | "ai" | "blend" | "kra" => "web.rs.ext.graphics",
        "wav" | "flac" | "aiff" => "web.rs.ext.audio",
        _ => return None,
    };
    Some(m(k, &[]))
}

fn ext_of(p: &Path) -> String {
    p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

fn big_files(idx: &HomeIndex) -> Vec<Item> {
    let mut big: Vec<&Indexed> = idx.files.iter().filter(|f| f.size >= 100 * MB).collect();
    big.sort_by(|a, b| b.size.cmp(&a.size));
    big.into_iter().take(250).map(|f| {
        let badges = badge_for_ext(&ext_of(&f.path)).map(|b| vec![b]).unwrap_or_default();
        new_item(&f.path, file_name(&f.path),
            m("web.rs.modified", &[&f.path.parent().map(pretty).unwrap_or_default(), &rel_time(f.modified)]),
            f.size, f.modified, "careful", false, badges)
    }).collect()
}

/// Files Schiaccia can make lighter (docs/SCHIACCIA.md): PDF and JPG from 1 MB, videos from 20 MB,
/// only among the user's own files (no hidden folders, app bundles or build output).
fn squeeze_candidates(idx: &HomeIndex) -> Vec<Item> {
    let h = home();
    let skip = ["node_modules", "build", "dist", "target", "Library", "AppData", "vendor", "Pods", "DerivedData"];
    let mut list: Vec<(&Indexed, &str)> = vec![];
    for f in &idx.files {
        let ext = ext_of(&f.path);
        let (kind, min, max) = match ext.as_str() {
            "pdf" => ("pdf", MB, u64::MAX),
            "jpg" | "jpeg" => ("jpg", MB, u64::MAX),
            // the whole video passes through the webview's memory: keep it reasonable
            "mp4" | "mov" | "m4v" | "webm" | "mkv" => ("video", 20 * MB, 1500 * MB),
            _ => continue,
        };
        if f.size < min || f.size > max {
            continue;
        }
        let rel = f.path.strip_prefix(&h).unwrap_or(&f.path);
        let hidden = rel.components().any(|c| {
            let s = c.as_os_str().to_string_lossy();
            s.starts_with('.') || s.ends_with(".app") || skip.contains(&s.as_ref())
        });
        if hidden {
            continue;
        }
        list.push((f, kind));
    }
    list.sort_by(|a, b| b.0.size.cmp(&a.0.size));
    list.into_iter().take(600).map(|(f, kind)| {
        let badge = m(&format!("web.rs.squeeze.{}", kind), &[]);
        new_item(&f.path, file_name(&f.path),
            m("web.rs.join", &[&f.path.parent().map(pretty).unwrap_or_default(), &rel_time(f.modified)]),
            f.size, f.modified, "safe", false, vec![badge])
    }).collect()
}

/// Puts Schiaccia's lighter version in place of `orig`: the result is written next to it under a
/// temporary name, the original goes to the system Trash, then the result takes `name`
/// (which differs only for WebM/MKV → MP4). Returns the final path.
pub fn replace_with_squeezed(orig: &Path, name: &str, data: &[u8]) -> Result<PathBuf, String> {
    let dir = orig.parent().ok_or_else(|| m("web.rs.squeeze.no_folder", &[]))?;
    if name.is_empty() || name.contains('/') || name.contains('\\') || name == "." || name == ".." {
        return Err(m("web.rs.squeeze.bad_name", &[]));
    }
    let meta = fs::metadata(orig).map_err(|e| e.to_string())?;
    let tmp = dir.join(format!(".{}.suriclean-tmp", name));
    fs::write(&tmp, data).map_err(|e| e.to_string())?;
    if let Ok(mt) = meta.modified() {
        if let Ok(f) = fs::File::options().write(true).open(&tmp) {
            let _ = f.set_modified(mt);
        }
    }
    let mut dest = dir.join(name);
    if dest != orig && dest.exists() {
        // e.g. video.webm → video.mp4 when video.mp4 already exists: never overwrite another file
        let stem = Path::new(name).file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        let ext = Path::new(name).extension().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        let mut k = 1;
        while dest.exists() {
            dest = dir.join(format!("{} ({}).{}", stem, k, ext));
            k += 1;
        }
    }
    if let Err(e) = trash::delete(orig) {
        let _ = fs::remove_file(&tmp);
        return Err(m("web.rs.squeeze.no_trash", &[&e.to_string()]));
    }
    if fs::rename(&tmp, &dest).is_err() {
        fs::copy(&tmp, &dest).map_err(|e| e.to_string())?;
        let _ = fs::remove_file(&tmp);
    }
    Ok(dest)
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
        let badge = m(if image { "web.rs.ext.disk_image" } else if ext == "appimage" { "web.rs.badge.appimage" } else { "web.rs.badge.installer" }, &[]);
        out.push(new_item(&f.path, file_name(&f.path),
            m("web.rs.join", &[&f.path.parent().map(pretty).unwrap_or_default(), &rel_time(f.modified)]),
            f.size, f.modified, if rec { "safe" } else { "review" }, rec, vec![badge]));
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
        if let Some(it) = make_item(k, name, Some(m("web.rs.downloaded", &[&rel_time(d)])), "review", false, rep, 100 * 1024,
            if days > 365 { vec![m("web.rs.badge.over_year", &[])] } else { vec![] }, d) {
            out.push(it);
        }
    }
    out
}

// ───────────────────────── disk map ─────────────────────────

/// Every folder >= 300 MB down to 4 levels below Home (view-only).
pub fn fresh_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

fn disk_map(rep: &Reporter) -> Vec<Item> {
    disk_map_at(&home(), &m("web.rs.map.home", &[]), "~", &m("web.rs.map.home_badge", &[]), rep)
}

/// The whole system drive (needs the administrator to see everything).
fn disk_map_full(rep: &Reporter) -> Vec<Item> {
    let root = if cfg!(windows) {
        PathBuf::from(std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into()) + "\\")
    } else {
        PathBuf::from("/")
    };
    let label = root.to_string_lossy().to_string();
    disk_map_at(&root, &m("web.rs.map.disk", &[]), &label, &m("web.rs.map.disk_badge", &[]), rep)
}

fn disk_map_at(h: &Path, title: &str, detail: &str, badge: &str, rep: &Reporter) -> Vec<Item> {
    let h = h.to_path_buf();
    let base = h.components().count();
    let mut sizes: HashMap<PathBuf, u64> = HashMap::new();
    let mut total = 0u64;
    let mut n = 0u64;
    let skip: [&Path; 3] = [Path::new("/proc"), Path::new("/snap"), Path::new("/run")];
    for e in WalkDir::new(&h).follow_links(false).same_file_system(true).into_iter()
        .filter_entry(|e| !skip.contains(&e.path())).flatten() {
        n += 1;
        if n % 500 == 0 {
            if rep.cancelled() {
                return vec![];
            }
            rep.report(&m("web.rs.p.measured", &[&n.to_string(), &pretty(e.path())]), None);
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
    let mut out = vec![new_item(&h, title.into(), detail.into(), total, None, "careful", false, vec![badge.into()])];
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
    let needs_index = matches!(category, "buildDeps" | "gitRepos" | "duplicates" | "bigFiles" | "installers" | "squeeze");
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
        ("diskMapFull", _) => disk_map_full(rep),
        ("caches", _) => caches(rep),
        ("logsTemp", _) => logs_temp(rep),
        ("systemAreas", _) => system_areas(rep),
        ("aiTools", _) => fixed(ai_targets(), rep),
        ("devCaches", _) => fixed(dev_targets(), rep),
        ("oldDownloads", _) => old_downloads(rep),
        ("buildDeps", Some(i)) => build_deps(&i, rep),
        ("gitRepos", Some(i)) => git_repos(&i, rep),
        ("duplicates", Some(i)) => duplicates(&i, rep),
        ("bigFiles", Some(i)) => big_files(&i),
        ("installers", Some(i)) => installers(&i),
        ("squeeze", Some(i)) => squeeze_candidates(&i),
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

// ───────────────────────── system areas ─────────────────────────

fn admin_item(mut it: Item) -> Item {
    it.admin = true;
    it.badges.push(m("web.rs.sys.badge_admin", &[]));
    it
}

/// Like make_item, but keeps folders we can't look into (their size is only known to the administrator).
fn sys_item(p: &Path, name: &str, detail: &str, risk: &str, rec: bool, rep: &Reporter, min: u64, badges: &[&str]) -> Option<Item> {
    if !p.exists() {
        return None;
    }
    let unreadable = p.is_dir() && fs::read_dir(p).is_err();
    let mut b: Vec<String> = badges.iter().map(|s| s.to_string()).collect();
    if unreadable {
        b.push(m("web.rs.sys.badge_locked", &[]));
        return Some(admin_item(new_item(p, name.into(), detail.into(), 0, mtime(p), risk, rec, b)));
    }
    make_item(p, name.into(), Some(detail.into()), risk, rec, rep, min, b, None).map(admin_item)
}

/// Many small files shown as one row: the first is the path, the others go in `extra`.
fn grouped(files: Vec<PathBuf>, name: String, detail: String, risk: &str, rec: bool, badges: &[&str]) -> Option<Item> {
    let size: u64 = files.iter().map(|f| fs::symlink_metadata(f).map(|m| m.len()).unwrap_or(0)).sum();
    if size < 512 * 1024 {
        return None;
    }
    let newest_t = files.iter().filter_map(|f| mtime(f)).max();
    let mut it = new_item(&files[0], m("web.rs.sys.n_files", &[&name, &files.len().to_string()]), detail, size, newest_t, risk, rec,
        badges.iter().map(|s| s.to_string()).collect());
    it.extra = files[1..].iter().map(|f| f.to_string_lossy().to_string()).collect();
    Some(admin_item(it))
}

fn files_where(root: &Path, depth: usize, keep: impl Fn(&Path, &fs::Metadata) -> bool) -> Vec<PathBuf> {
    WalkDir::new(root).max_depth(depth).follow_links(false).into_iter().flatten()
        .filter(|e| e.file_type().is_file())
        .filter(|e| e.metadata().map(|m| keep(e.path(), &m)).unwrap_or(false))
        .map(|e| e.path().to_path_buf())
        .collect()
}

#[allow(dead_code)]
fn is_rotated(name: &str) -> bool {
    let n = name.to_lowercase();
    if [".gz", ".xz", ".bz2", ".zip", ".old", ".zst"].iter().any(|e| n.ends_with(e)) {
        return true;
    }
    match n.rsplit_once('.') {
        Some((_, last)) => !last.is_empty() && last.chars().all(|c| c.is_ascii_digit()),
        None => false,
    }
}

fn old_enough(m: &fs::Metadata, days: u64) -> bool {
    days_since(m.modified().ok()) >= days
}

fn system_areas(rep: &Reporter) -> Vec<Item> {
    let mut out = vec![];
    if cfg!(windows) {
        system_windows(rep, &mut out);
    } else {
        system_linux(rep, &mut out);
    }
    out
}

fn system_windows(rep: &Reporter, out: &mut Vec<Item>) {
    let win = PathBuf::from(std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into()));
    let drive = PathBuf::from(std::env::var("SystemDrive").unwrap_or_else(|_| "C:".into()) + "\\");
    let pdata = PathBuf::from(std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".into()));

    rep.report_force(&m("web.rs.sys.p_win_temp", &[]), Some(0.0));
    let wtemp = win.join("Temp");
    if fs::read_dir(&wtemp).is_ok() {
        for k in children(&wtemp) {
            if rep.cancelled() { return; }
            if days_since(newest(&k, &[])) < 1 { continue; }
            if let Some(it) = make_item(&k, m("web.rs.sys.win_temp_item", &[&file_name(&k)]), Some(pretty(&k)), "safe", true, rep, 256 * 1024, vec![m("web.rs.sys.badge_temp", &[])], None) {
                out.push(admin_item(it));
            }
        }
    } else if let Some(it) = sys_item(&wtemp, &m("web.rs.sys.p_win_temp", &[]), &m("web.rs.sys.win_temp_detail", &[]), "safe", true, rep, 0, &[m("web.rs.sys.badge_temp", &[]).as_str()]) {
        out.push(it);
    }

    rep.report_force(&m("web.rs.sys.p_updates", &[]), Some(0.15));
    let sd = win.join("SoftwareDistribution").join("Download");
    for k in children(&sd) {
        if rep.cancelled() { return; }
        if let Some(it) = sys_item(&k, &m("web.rs.sys.wu_item", &[&file_name(&k)]), &m("web.rs.sys.wu_detail", &[]), "safe", true, rep, MB, &[m("web.rs.sys.badge_redownload", &[]).as_str()]) {
            out.push(it);
        }
    }
    let dopt = win.join("ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Cache");
    if let Some(mut it) = sys_item(&dopt, &m("web.rs.sys.dopt", &[]), &m("web.rs.sys.dopt_detail", &[]), "safe", true, rep, MB, &[m("web.rs.sys.badge_redownload", &[]).as_str()]) {
        it.cmd = Some("powershell -NoProfile -Command \"Delete-DeliveryOptimizationCache -Force\"".into());
        out.push(it);
    }

    rep.report_force(&m("web.rs.sys.p_logs", &[]), Some(0.35));
    let logs = files_where(&win.join("Logs"), 6, |_, m| old_enough(m, 7));
    if !logs.is_empty() {
        if let Some(it) = grouped(logs, m("web.rs.sys.win_logs", &[]), m("web.rs.sys.win_logs_detail", &[]), "safe", true, &[m("web.rs.sys.badge_log", &[]).as_str()]) {
            out.push(it);
        }
    }
    for (sub, name) in [("ReportArchive", m("web.rs.sys.wer_archive", &[])), ("ReportQueue", m("web.rs.sys.wer_queue", &[])), ("Temp", m("web.rs.sys.wer_temp", &[]))] {
        let p = pdata.join("Microsoft\\Windows\\WER").join(sub);
        if let Some(it) = sys_item(&p, &name, &pretty(&p), "safe", true, rep, 256 * 1024, &[m("web.rs.sys.badge_crash", &[]).as_str()]) {
            out.push(it);
        }
    }

    rep.report_force(&m("web.rs.sys.p_dumps", &[]), Some(0.55));
    for (p, name) in [
        (win.join("MEMORY.DMP"), m("web.rs.sys.memory_dmp", &[])),
        (win.join("Minidump"), m("web.rs.sys.minidump", &[])),
        (win.join("LiveKernelReports"), m("web.rs.sys.kernel_reports", &[])),
    ] {
        if let Some(it) = sys_item(&p, &name, &pretty(&p), "safe", true, rep, MB, &[m("web.rs.sys.badge_crash", &[]).as_str()]) {
            out.push(it);
        }
    }

    rep.report_force(&m("web.rs.sys.p_old_windows", &[]), Some(0.7));
    let old = drive.join("Windows.old");
    if old.exists() {
        let size = size_of(&old, Some(rep));
        let mut it = admin_item(new_item(&old, m("web.rs.sys.windows_old", &[]),
            m("web.rs.sys.windows_old_detail", &[]), size, mtime(&old), "review", false, vec![m("web.rs.sys.badge_rollback", &[])]));
        it.cmd = Some("cleanmgr /autoclean".into());
        out.push(it);
    }
    let hib = drive.join("hiberfil.sys");
    if let Ok(md) = fs::metadata(&hib) {
        if md.len() > 512 * MB {
            let mut it = admin_item(new_item(&hib, m("web.rs.sys.hiberfil", &[]),
                m("web.rs.sys.hiberfil_detail", &[]), md.len(), None, "careful", false, vec![m("web.rs.sys.badge_hibernate", &[])]));
            it.cmd = Some("powercfg /hibernate off".into());
            out.push(it);
        }
    }
    let mut it = admin_item(new_item(&win.join("WinSxS"), m("web.rs.sys.winsxs", &[]),
        m("web.rs.sys.winsxs_detail", &[]), 0, None, "review", false, vec![m("web.rs.sys.badge_components", &[])]));
    it.cmd = Some("Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet".into());
    out.push(it);
}

fn system_linux(rep: &Reporter, out: &mut Vec<Item>) {
    rep.report_force(&m("web.rs.sys.p_rotated", &[]), Some(0.0));
    let logs = files_where(Path::new("/var/log"), 4, |p, m| {
        old_enough(m, 1) && is_rotated(&p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default())
            && !p.starts_with("/var/log/journal")
    });
    if !logs.is_empty() {
        if let Some(it) = grouped(logs, m("web.rs.sys.rotated_logs", &[]), m("web.rs.sys.rotated_logs_detail", &[]), "safe", true, &[m("web.rs.sys.badge_log", &[]).as_str()]) {
            out.push(it);
        }
    }
    let journal = Path::new("/var/log/journal");
    if journal.exists() {
        let old: u64 = files_where(journal, 2, |p, m| {
            let n = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            (n.contains('@') || n.ends_with("~")) && old_enough(m, 7)
        }).iter().map(|f| fs::metadata(f).map(|m| m.len()).unwrap_or(0)).sum();
        if old > MB {
            let mut it = admin_item(new_item(journal, m("web.rs.sys.journal", &[]),
                m("web.rs.sys.journal_detail", &[]), old, mtime(journal), "safe", true, vec![m("web.rs.sys.badge_log", &[])]));
            it.cmd = Some("journalctl --vacuum-time=7d".into());
            out.push(it);
        }
    }
    if rep.cancelled() { return; }

    rep.report_force(&m("web.rs.sys.p_packages", &[]), Some(0.25));
    let debs = files_where(Path::new("/var/cache/apt/archives"), 1, |p, _| p.extension().map_or(false, |e| e == "deb"));
    if !debs.is_empty() {
        if let Some(it) = grouped(debs, m("web.rs.sys.debs", &[]), m("web.rs.sys.debs_detail", &[]), "safe", true, &[m("web.rs.sys.badge_redownload", &[]).as_str()]) {
            out.push(it);
        }
    }
    for k in children(Path::new("/var/cache/PackageKit")) {
        if let Some(it) = sys_item(&k, &m("web.rs.sys.packagekit", &[&file_name(&k)]), &pretty(&k), "safe", true, rep, MB, &[m("web.rs.sys.badge_redownload", &[]).as_str()]) {
            out.push(it);
        }
    }

    rep.report_force(&m("web.rs.sys.p_snaps", &[]), Some(0.45));
    if let Ok(o) = Command::new("snap").args(["list", "--all"]).output() {
        for line in String::from_utf8_lossy(&o.stdout).lines().skip(1) {
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.len() < 3 || !line.contains("disabled") { continue; }
            let (name, rev) = (f[0], f[2]);
            let file = PathBuf::from(format!("/var/lib/snapd/snaps/{}_{}.snap", name, rev));
            let size = fs::metadata(&file).map(|m| m.len()).unwrap_or(0);
            let mut it = admin_item(new_item(&file, m("web.rs.sys.snap", &[name, rev]),
                m("web.rs.sys.snap_detail", &[]), size, mtime(&file), "safe", true, vec!["📦 snap".into()]));
            it.cmd = Some(format!("snap remove {} --revision={}", name, rev));
            out.push(it);
        }
    }
    if rep.cancelled() { return; }

    rep.report_force(&m("web.rs.sys.p_crash", &[]), Some(0.65));
    for (dir, label) in [("/var/crash", "web.rs.sys.crash_report"), ("/var/lib/systemd/coredump", "web.rs.sys.core_dump")] {
        for k in children(Path::new(dir)) {
            if let Some(it) = sys_item(&k, &m(label, &[&file_name(&k)]), &pretty(&k), "safe", true, rep, 256 * 1024, &[m("web.rs.sys.badge_crash", &[]).as_str()]) {
                out.push(it);
            }
        }
    }

    rep.report_force(&m("web.rs.sys.p_tmp_backups", &[]), Some(0.8));
    for k in children(Path::new("/var/tmp")) {
        if rep.cancelled() { return; }
        let d = newest(&k, &[]);
        if days_since(d) < 3 { continue; }
        if let Some(it) = sys_item(&k, &m("web.rs.sys.var_tmp", &[&file_name(&k)]), &m("web.rs.sys.var_tmp_detail", &[&rel_time(d)]), "safe", true, rep, 256 * 1024, &[m("web.rs.sys.badge_temp", &[]).as_str()]) {
            out.push(it);
        }
    }
    let backups = files_where(Path::new("/var/backups"), 1, |p, m| {
        old_enough(m, 7) && is_rotated(&p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default())
    });
    if !backups.is_empty() {
        if let Some(it) = grouped(backups, m("web.rs.sys.backups", &[]), m("web.rs.sys.backups_detail", &[]), "safe", true, &[m("web.rs.sys.badge_backup", &[]).as_str()]) {
            out.push(it);
        }
    }
}

/// Runs the given shell lines as administrator with ONE prompt (UAC on Windows, pkexec on Linux).
pub fn run_elevated(lines: &[String]) -> Result<(), String> {
    let dir = std::env::temp_dir().join(format!("suriclean-admin-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let res = if cfg!(windows) {
        let script = dir.join("suri.cmd");
        let body = format!("@echo off\r\nchcp 65001 >nul\r\n{}\r\n", lines.join("\r\n"));
        fs::write(&script, body).map_err(|e| e.to_string())?;
        let ps = format!("Start-Process -FilePath '{}' -Verb RunAs -Wait -WindowStyle Hidden",
            script.to_string_lossy().replace('\'', "''"));
        let st = hidden_cmd("powershell").args(["-NoProfile", "-NonInteractive", "-Command", &ps]).status().map_err(|e| e.to_string())?;
        if st.success() { Ok(()) } else { Err(m("web.rs.err.uac_cancelled", &[])) }
    } else {
        let script = dir.join("suri.sh");
        fs::write(&script, format!("#!/bin/sh\n{}\nexit 0\n", lines.join("\n"))).map_err(|e| e.to_string())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
        }
        match Command::new("pkexec").arg("/bin/sh").arg(&script).status() {
            Ok(st) if st.code() == Some(126) || st.code() == Some(127) => Err(m("web.rs.err.pw_cancelled", &[])),
            Ok(_) => Ok(()),
            Err(_) => Err(m("web.rs.err.no_pkexec", &[])),
        }
    };
    res
}

/// Quoted for the shell the elevated script runs in.
pub fn shell_quote(p: &str) -> String {
    if cfg!(windows) {
        format!("\"{}\"", p.replace('"', ""))
    } else {
        format!("'{}'", p.replace('\'', "'\\''"))
    }
}

pub fn delete_line(p: &Path) -> String {
    let q = shell_quote(&p.to_string_lossy());
    if cfg!(windows) {
        if p.is_dir() { format!("rd /s /q {}", q) } else { format!("del /f /q /a {}", q) }
    } else {
        format!("rm -rf -- {}", q)
    }
}
