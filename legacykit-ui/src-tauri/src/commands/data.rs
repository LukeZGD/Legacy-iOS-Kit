use crate::error::AppError;
use crate::models::data::{
    BackupCreateRequest, BackupCreateResult, BackupEncryptionRequest, BackupEncryptionResult,
    BackupEntry, BackupRestoreRequest, BackupRestoreResult, EraseDeviceRequest, EraseDeviceResult,
    ListBackupsRequest, ListBackupsResult,
};
use crate::platform::resolve_binary_path;
use serde::Serialize;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::UNIX_EPOCH;
use tauri::{AppHandle, Emitter};

const ERASE_CONFIRMATION: &str = "Yes, do as I say";

#[tauri::command]
pub async fn create_backup(
    app: AppHandle,
    request: BackupCreateRequest,
) -> Result<BackupCreateResult, AppError> {
    let backup_root = request.backup_root.trim();
    if backup_root.is_empty() {
        return Err(AppError::Parse("Backup root directory is required".into()));
    }
    fs::create_dir_all(backup_root)?;

    let stamp = format_timestamp_dir();
    let backup_path = Path::new(backup_root).join(&stamp);
    fs::create_dir_all(&backup_path)?;

    let mut args: Vec<String> = Vec::new();
    if let Some(udid) = nullable(request.udid.as_deref()) {
        args.push("-u".into());
        args.push(udid.to_string());
    }
    args.push("backup".into());
    if request.full {
        args.push("--full".into());
    }
    args.push(backup_path.to_string_lossy().to_string());

    let binary = resolve_binary_path(&app, "idevicebackup2").map_err(AppError::CommandFailed)?;
    emit_data_log(
        &app,
        "info",
        &format!("Starting idevicebackup2 backup → {}", backup_path.display()),
    );
    run_process_streaming(&app, binary, &args)?;
    emit_data_log(&app, "info", "Backup completed");

    Ok(BackupCreateResult {
        backup_path: backup_path.to_string_lossy().to_string(),
        args,
    })
}

#[tauri::command]
pub async fn restore_backup(
    app: AppHandle,
    request: BackupRestoreRequest,
) -> Result<BackupRestoreResult, AppError> {
    let backup_path = request.backup_path.trim();
    if backup_path.is_empty() {
        return Err(AppError::Parse("Backup path is required".into()));
    }
    if !Path::new(backup_path).exists() {
        return Err(AppError::Parse(format!(
            "Backup path does not exist: {backup_path}"
        )));
    }

    let mut args: Vec<String> = Vec::new();
    if let Some(udid) = nullable(request.udid.as_deref()) {
        args.push("-u".into());
        args.push(udid.to_string());
    }
    args.push("restore".into());
    if request.system {
        args.push("--system".into());
    }
    if request.settings {
        args.push("--settings".into());
    }
    if request.reboot {
        args.push("--reboot".into());
    }
    args.push(backup_path.to_string());

    let binary = resolve_binary_path(&app, "idevicebackup2").map_err(AppError::CommandFailed)?;
    emit_data_log(
        &app,
        "info",
        &format!("Restoring backup from {backup_path}"),
    );
    run_process_streaming(&app, binary, &args)?;
    emit_data_log(&app, "info", "Restore completed");

    Ok(BackupRestoreResult {
        backup_path: backup_path.to_string(),
        args,
    })
}

#[tauri::command]
pub async fn erase_device(
    app: AppHandle,
    request: EraseDeviceRequest,
) -> Result<EraseDeviceResult, AppError> {
    if request.confirmation.trim() != ERASE_CONFIRMATION {
        return Err(AppError::Parse(format!(
            "Confirmation phrase must exactly match: {ERASE_CONFIRMATION}"
        )));
    }

    let mut args: Vec<String> = Vec::new();
    if let Some(udid) = nullable(request.udid.as_deref()) {
        args.push("-u".into());
        args.push(udid.to_string());
    }
    args.push("erase".into());

    let binary = resolve_binary_path(&app, "idevicebackup2").map_err(AppError::CommandFailed)?;
    emit_data_log(
        &app,
        "warn",
        "Erasing device (Erase All Content and Settings)",
    );
    run_process_streaming(&app, binary, &args)?;
    emit_data_log(&app, "info", "Erase request issued");

    Ok(EraseDeviceResult { args })
}

#[tauri::command]
pub async fn set_backup_encryption(
    app: AppHandle,
    request: BackupEncryptionRequest,
) -> Result<BackupEncryptionResult, AppError> {
    let mut args: Vec<String> = vec!["-i".into()];
    if let Some(udid) = nullable(request.udid.as_deref()) {
        args.push("-u".into());
        args.push(udid.to_string());
    }
    args.extend(request.action.as_args());

    let binary = resolve_binary_path(&app, "idevicebackup2").map_err(AppError::CommandFailed)?;
    emit_data_log(
        &app,
        "info",
        &format!("Backup encryption: {:?}", request.action),
    );
    run_process_streaming(&app, binary, &args)?;

    Ok(BackupEncryptionResult {
        action: request.action,
        args,
    })
}

#[tauri::command]
pub async fn list_backups(request: ListBackupsRequest) -> Result<ListBackupsResult, AppError> {
    let backup_root = request.backup_root.trim().to_string();
    if backup_root.is_empty() {
        return Err(AppError::Parse("Backup root directory is required".into()));
    }
    let root = Path::new(&backup_root);
    if !root.exists() {
        return Ok(ListBackupsResult {
            backup_root,
            backups: Vec::new(),
        });
    }

    let mut backups = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let metadata = entry.metadata()?;
        let modified_unix = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs());
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_string();
        if name.is_empty() {
            continue;
        }
        backups.push(BackupEntry {
            path: path.to_string_lossy().to_string(),
            name,
            size_bytes: dir_size(&path).unwrap_or(0),
            modified_unix,
        });
    }

    backups.sort_by_key(|b| std::cmp::Reverse(b.modified_unix));
    Ok(ListBackupsResult {
        backup_root,
        backups,
    })
}

fn dir_size(dir: &Path) -> Option<u64> {
    let mut total: u64 = 0;
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(sub) = dir_size(&path) {
                total += sub;
            }
        } else if let Ok(meta) = entry.metadata() {
            total += meta.len();
        }
    }
    Some(total)
}

fn format_timestamp_dir() -> String {
    use std::time::SystemTime;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (year, month, day, hour, minute) = unix_to_components(now);
    format!("{year:04}-{month:02}-{day:02}-{hour:02}{minute:02}")
}

/// Minimal Unix-timestamp → (year, month, day, hour, minute) decomposition without
/// pulling in chrono. Good for filename stamps.
fn unix_to_components(secs: u64) -> (u32, u32, u32, u32, u32) {
    let days = (secs / 86_400) as i64;
    let seconds_of_day = (secs % 86_400) as u32;
    let hour = seconds_of_day / 3600;
    let minute = (seconds_of_day % 3600) / 60;

    // 1970-01-01 is day 0 (Thursday). Use civil_from_days algorithm.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    (year as u32, m as u32, d as u32, hour, minute)
}

fn nullable(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|v| !v.is_empty())
}

fn run_process_streaming(
    app: &AppHandle,
    binary: PathBuf,
    args: &[String],
) -> Result<(), AppError> {
    let mut child = Command::new(&binary)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| AppError::CommandFailed("Failed to capture process stdout".to_string()))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| AppError::CommandFailed("Failed to capture process stderr".to_string()))?;

    let stdout_app = app.clone();
    let stdout_thread = thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines().map_while(Result::ok) {
            emit_data_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_data_log(&stderr_app, "stderr", &line);
        }
    });

    let status = child.wait()?;
    let _ = stdout_thread.join();
    let _ = stderr_thread.join();

    if !status.success() {
        return Err(AppError::CommandFailed(format!(
            "{} exited with status {}",
            binary.display(),
            status
        )));
    }
    Ok(())
}

fn emit_data_log(app: &AppHandle, level: &str, text: &str) {
    let payload = LogEventPayload {
        text: text.to_string(),
        kind: level.to_string(),
    };
    let _ = app.emit("log_event", payload);
}

#[derive(Clone, Serialize)]
struct LogEventPayload {
    text: String,
    #[serde(rename = "type")]
    kind: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unix_epoch_decomposes_correctly() {
        assert_eq!(unix_to_components(0), (1970, 1, 1, 0, 0));
    }

    #[test]
    fn known_timestamp_decomposes_correctly() {
        // 2026-04-30 12:34:00 UTC = 1777552440
        assert_eq!(unix_to_components(1_777_552_440), (2026, 4, 30, 12, 34));
    }

    #[test]
    fn leap_day_decomposes_correctly() {
        // 2024-02-29 00:00:00 UTC = 1709164800
        assert_eq!(unix_to_components(1_709_164_800), (2024, 2, 29, 0, 0));
    }
}
