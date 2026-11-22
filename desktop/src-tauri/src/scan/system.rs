//! System areas of Windows and Ubuntu, and the one administrator step (UAC / pkexec).
//! Child module of scan.rs: it uses the scanner helpers of its parent.

use super::*;

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

pub(super) fn system_areas(rep: &Reporter) -> Vec<Item> {
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
        if in_use_temp(&k) { continue; }
        let d = newest(&k, &[]);
        // /var/tmp is meant to survive reboots: systemd itself waits 30 days
        if days_since(d) < 30 { continue; }
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

/// A new folder only this user can open, for the files exchanged with the administrator step
/// (script, results). Random name, created atomically: it fails if something is already there.
pub fn private_dir() -> Result<PathBuf, String> {
    let base = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).filter(|p| p.is_dir()).unwrap_or_else(std::env::temp_dir);
    let nanos = SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let dir = base.join(format!("suriclean-{}-{:x}-{}", std::process::id(), nanos, fresh_id()));
    let mut b = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        b.mode(0o700);
    }
    b.create(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

/// Runs the given shell lines as administrator with ONE prompt (UAC on Windows, pkexec on Linux),
/// from a script written in `dir` (made by `private_dir`).
pub fn run_elevated(dir: &Path, lines: &[String]) -> Result<(), String> {
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
        // in a .cmd file %VAR% is expanded even inside quotes: %% is a literal %
        format!("\"{}\"", p.replace('"', "").replace('%', "%%"))
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
