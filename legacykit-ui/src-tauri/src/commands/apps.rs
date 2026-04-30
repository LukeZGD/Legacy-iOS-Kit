use crate::error::AppError;
use crate::models::apps::{
    AppListScope, InstallIpaRequest, InstallIpaResult, InstalledApp, ListAppsRequest,
    ListAppsResult, UninstallAppRequest, UninstallAppResult,
};
use crate::platform::resolve_binary_path;
use serde::Serialize;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use tauri::{AppHandle, Emitter};

#[tauri::command]
pub async fn list_installed_apps(
    app: AppHandle,
    request: ListAppsRequest,
) -> Result<ListAppsResult, AppError> {
    let binary = resolve_binary_path(&app, "ideviceinstaller").map_err(AppError::CommandFailed)?;
    let scope_arg = request.scope.as_arg().to_string();
    let args = vec!["list".to_string(), scope_arg];

    emit_apps_log(
        &app,
        "info",
        &format!("Listing installed apps ({})", request.scope.as_arg()),
    );

    let output = Command::new(&binary)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(AppError::CommandFailed(if stderr.is_empty() {
            format!("ideviceinstaller list exited with {}", output.status)
        } else {
            stderr
        }));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let apps = parse_ideviceinstaller_list(&stdout);
    emit_apps_log(&app, "info", &format!("Found {} app(s)", apps.len()));

    Ok(ListAppsResult {
        scope: request.scope,
        apps,
    })
}

#[tauri::command]
pub async fn install_ipa(
    app: AppHandle,
    request: InstallIpaRequest,
) -> Result<InstallIpaResult, AppError> {
    if request.ipa_paths.is_empty() {
        return Err(AppError::Parse(
            "At least one IPA path is required".to_string(),
        ));
    }
    for path in &request.ipa_paths {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            return Err(AppError::Parse("IPA path is empty".to_string()));
        }
        if !Path::new(trimmed).exists() {
            return Err(AppError::Parse(format!("IPA does not exist: {trimmed}")));
        }
    }

    let binary = resolve_binary_path(&app, "ideviceinstaller").map_err(AppError::CommandFailed)?;
    let mut installed = Vec::with_capacity(request.ipa_paths.len());

    for path in &request.ipa_paths {
        let trimmed = path.trim().to_string();
        emit_apps_log(&app, "info", &format!("Installing {trimmed}"));
        let args = vec!["install".to_string(), trimmed.clone()];
        run_process_streaming(&app, binary.clone(), &args)?;
        installed.push(trimmed);
    }

    emit_apps_log(&app, "info", &format!("Installed {} IPA(s)", installed.len()));
    Ok(InstallIpaResult { installed })
}

#[tauri::command]
pub async fn uninstall_app(
    app: AppHandle,
    request: UninstallAppRequest,
) -> Result<UninstallAppResult, AppError> {
    let bundle_id = request.bundle_id.trim();
    if bundle_id.is_empty() {
        return Err(AppError::Parse("Bundle identifier is required".to_string()));
    }

    let binary = resolve_binary_path(&app, "ideviceinstaller").map_err(AppError::CommandFailed)?;
    let args = vec!["uninstall".to_string(), bundle_id.to_string()];
    emit_apps_log(&app, "info", &format!("Uninstalling {bundle_id}"));
    run_process_streaming(&app, binary, &args)?;
    emit_apps_log(&app, "info", &format!("Uninstalled {bundle_id}"));

    Ok(UninstallAppResult {
        bundle_id: bundle_id.to_string(),
    })
}

/// Parses `ideviceinstaller list` output. The header line is `CFBundleIdentifier,
/// CFBundleShortVersionString, CFBundleDisplayName` and subsequent rows are CSV with
/// optional quotes around fields.
fn parse_ideviceinstaller_list(output: &str) -> Vec<InstalledApp> {
    let mut apps = Vec::new();
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.starts_with("CFBundleIdentifier") || trimmed.starts_with("Total:") {
            continue;
        }
        let fields = split_csv_row(trimmed);
        if fields.is_empty() {
            continue;
        }
        let bundle_id = fields[0].trim().to_string();
        if bundle_id.is_empty() {
            continue;
        }
        let version = fields.get(1).map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
        let display_name = fields.get(2).map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
        apps.push(InstalledApp {
            bundle_id,
            display_name,
            version,
        });
    }
    apps
}

/// Lightweight CSV row splitter that respects double-quoted fields. Sufficient for
/// `ideviceinstaller list` output, which never contains embedded newlines or commas
/// outside of quoted strings.
fn split_csv_row(row: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut chars = row.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '"' => {
                if in_quotes && chars.peek() == Some(&'"') {
                    current.push('"');
                    chars.next();
                } else {
                    in_quotes = !in_quotes;
                }
            }
            ',' if !in_quotes => {
                fields.push(std::mem::take(&mut current));
            }
            _ => current.push(ch),
        }
    }
    fields.push(current);
    fields
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
            emit_apps_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_apps_log(&stderr_app, "stderr", &line);
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

fn emit_apps_log(app: &AppHandle, level: &str, text: &str) {
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

// Suppress unused-variant warnings; AppListScope is round-tripped through the type.
#[allow(dead_code)]
fn _ensure_scope_used(_scope: AppListScope) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_quoted_csv_rows() {
        let out = r#"CFBundleIdentifier, CFBundleShortVersionString, CFBundleDisplayName
"com.example.foo", "1.0", "Foo"
"com.example.bar", "2.5.1", "Bar App"
"#;
        let apps = parse_ideviceinstaller_list(out);
        assert_eq!(apps.len(), 2);
        assert_eq!(apps[0].bundle_id, "com.example.foo");
        assert_eq!(apps[0].version.as_deref(), Some("1.0"));
        assert_eq!(apps[0].display_name.as_deref(), Some("Foo"));
        assert_eq!(apps[1].bundle_id, "com.example.bar");
        assert_eq!(apps[1].display_name.as_deref(), Some("Bar App"));
    }

    #[test]
    fn skips_empty_and_total_lines() {
        let out = r#"CFBundleIdentifier, CFBundleShortVersionString, CFBundleDisplayName

"com.example.x", "1", "X"
Total: 1 app(s)
"#;
        let apps = parse_ideviceinstaller_list(out);
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].bundle_id, "com.example.x");
    }

    #[test]
    fn handles_unquoted_fields() {
        let apps = parse_ideviceinstaller_list("com.unquoted.app, 3.0, App Name\n");
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].bundle_id, "com.unquoted.app");
        assert_eq!(apps[0].version.as_deref(), Some("3.0"));
        assert_eq!(apps[0].display_name.as_deref(), Some("App Name"));
    }

    #[test]
    fn handles_doubled_quotes() {
        let apps = parse_ideviceinstaller_list(r#""com.q.app", "1", "He said ""hi"""
"#);
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].display_name.as_deref(), Some(r#"He said "hi""#));
    }
}
