// SuriClean for Windows and Linux (Tauri). The macOS version is native SwiftUI.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod scan;

use scan::{Item, Reporter};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter};

static CANCEL: AtomicBool = AtomicBool::new(false);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DiskInfo {
    total: u64,
    free: u64,
}

#[derive(Serialize, Clone)]
struct Progress {
    text: String,
    progress: Option<f64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TrashReq {
    id: u64,
    path: String,
    name: String,
    size: u64,
    #[serde(default)]
    extra: Vec<String>,
    #[serde(default)]
    copy_text: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TrashOutcome {
    removed: Vec<u64>,
    bytes: u64,
    failed: Vec<String>,
    repo_log: Option<String>,
}

fn reporter(app: &AppHandle) -> Reporter {
    let app = app.clone();
    Reporter::new(
        Arc::new(move |text: String, progress: Option<f64>| {
            let _ = app.emit("suri-progress", Progress { text, progress });
        }),
        &CANCEL,
    )
}

#[tauri::command]
fn platform() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "linux"
    }
}

#[tauri::command]
fn disk_info() -> DiskInfo {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    let disks = sysinfo::Disks::new_with_refreshed_list();
    let mut best: Option<(usize, u64, u64)> = None;
    for d in disks.list() {
        let mp = d.mount_point();
        if home.starts_with(mp) {
            let len = mp.as_os_str().len();
            if best.map_or(true, |b| len > b.0) {
                best = Some((len, d.total_space(), d.available_space()));
            }
        }
    }
    let (_, total, free) = best.unwrap_or((0, 0, 0));
    DiskInfo { total, free }
}

#[tauri::command]
fn has_git() -> bool {
    scan::git_available()
}

#[tauri::command]
async fn scan_category(app: AppHandle, category: String) -> Result<Vec<Item>, String> {
    CANCEL.store(false, Ordering::SeqCst);
    let rep = reporter(&app);
    tauri::async_runtime::spawn_blocking(move || scan::scan(&category, &rep))
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn cancel_scan() {
    CANCEL.store(true, Ordering::SeqCst);
}

#[tauri::command]
fn invalidate_index() {
    scan::invalidate_index();
}

#[tauri::command]
async fn trash_items(app: AppHandle, items: Vec<TrashReq>) -> Result<TrashOutcome, String> {
    CANCEL.store(false, Ordering::SeqCst);
    let rep = reporter(&app);
    tauri::async_runtime::spawn_blocking(move || {
        let mut out = TrashOutcome { removed: vec![], bytes: 0, failed: vec![], repo_log: None };
        let mut log: Vec<String> = vec![];
        let n = items.len().max(1);
        for (i, it) in items.iter().enumerate() {
            if rep.cancelled() {
                break;
            }
            rep.report_force(&it.name, Some(i as f64 / n as f64));
            let p = Path::new(&it.path);
            if !p.exists() {
                out.removed.push(it.id);
                continue;
            }
            match trash::delete(p) {
                Ok(_) => {
                    for e in &it.extra {
                        let ep = Path::new(e);
                        if ep.exists() {
                            let _ = trash::delete(ep);
                        }
                    }
                    out.removed.push(it.id);
                    out.bytes += it.size;
                    if let Some(c) = &it.copy_text {
                        log.push(format!("# {}\n{}", it.path, c));
                    }
                }
                Err(_) => out.failed.push(it.name.clone()),
            }
        }
        if !log.is_empty() {
            out.repo_log = scan::append_repo_log(&log);
        }
        rep.report_force("Fatto!", Some(1.0));
        out
    })
    .await
    .map_err(|e| e.to_string())
}

#[tauri::command]
async fn trash_size() -> u64 {
    tauri::async_runtime::spawn_blocking(scan::trash_size).await.unwrap_or(0)
}

#[tauri::command]
async fn empty_trash() -> Result<u64, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let before = scan::trash_size();
        scan::empty_trash()?;
        let after = scan::trash_size();
        Ok(before.saturating_sub(after))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
fn existing(paths: Vec<String>) -> Vec<bool> {
    paths.iter().map(|p| Path::new(p).exists()).collect()
}

#[tauri::command]
fn reveal(path: String) {
    scan::reveal(Path::new(&path));
}

#[tauri::command]
fn open_folder(path: String) {
    scan::open_path(Path::new(&path));
}

#[tauri::command]
fn open_url(url: String) {
    if url.starts_with("https://") {
        scan::open_url(&url);
    }
}

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

/// Downloads the new installer from GitHub and starts it.
/// Windows: runs the NSIS setup in passive mode and relaunches. Linux AppImage: swaps the file in place.
/// Linux .deb: saves the package in Downloads and opens it with the software installer.
#[tauri::command]
async fn install_update(app: AppHandle, url: String, kind: String) -> Result<String, String> {
    if !(url.starts_with("https://github.com/") || url.starts_with("https://objects.githubusercontent.com/")) {
        return Err("indirizzo non valido".into());
    }
    let result = tauri::async_runtime::spawn_blocking(move || -> Result<(PathBuf, bool), String> {
        let resp = ureq::get(&url).set("User-Agent", "SuriClean").call().map_err(|e| e.to_string())?;
        let mut bytes = Vec::new();
        std::io::Read::read_to_end(&mut resp.into_reader(), &mut bytes).map_err(|e| e.to_string())?;
        match kind.as_str() {
            "windows" => {
                let p = std::env::temp_dir().join("SuriClean-Windows-Setup.exe");
                std::fs::write(&p, &bytes).map_err(|e| e.to_string())?;
                std::process::Command::new(&p).args(["/P", "/R"]).spawn().map_err(|e| e.to_string())?;
                Ok((p, true))
            }
            "appimage" => {
                let current = PathBuf::from(std::env::var("APPIMAGE").map_err(|_| "non è un AppImage".to_string())?);
                let tmp = current.with_extension("new");
                std::fs::write(&tmp, &bytes).map_err(|e| e.to_string())?;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
                }
                std::fs::rename(&tmp, &current).map_err(|e| e.to_string())?;
                std::process::Command::new(&current).spawn().map_err(|e| e.to_string())?;
                Ok((current, true))
            }
            _ => {
                let dir = dirs::download_dir().unwrap_or_else(std::env::temp_dir);
                let p = dir.join("SuriClean-Linux.deb");
                std::fs::write(&p, &bytes).map_err(|e| e.to_string())?;
                scan::open_path(&p);
                Ok((p, false))
            }
        }
    })
    .await
    .map_err(|e| e.to_string())??;
    if result.1 {
        let a = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(600));
            a.exit(0);
        });
    }
    Ok(result.0.to_string_lossy().to_string())
}

#[tauri::command]
fn install_kind() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else if std::env::var("APPIMAGE").is_ok() {
        "appimage"
    } else {
        "deb"
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            platform, disk_info, has_git, scan_category, cancel_scan, invalidate_index,
            trash_items, trash_size, empty_trash, existing, reveal, open_folder, open_url,
            app_version, install_update, install_kind
        ])
        .run(tauri::generate_context!())
        .expect("error while running SuriClean");
}
