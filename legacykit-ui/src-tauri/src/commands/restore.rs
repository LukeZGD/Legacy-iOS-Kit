use crate::error::AppError;
use crate::models::device::DeviceInfo;
use crate::models::restore::{
    IpswDownloadRequest, IpswDownloadResult, IpswVerifyRequest, IpswVerifyResult,
    RestoreCommandPreview, RestoreOptionsResponse, RestoreRunRequest, RestoreTool,
};
use crate::platform::resolve_binary_path;
use crate::services::restore_options::determine_restore_options;
use crate::services::sha1::sha1_file;
use serde::Serialize;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use tauri::{AppHandle, Emitter};

#[tauri::command]
pub async fn get_restore_options(device: DeviceInfo) -> Result<RestoreOptionsResponse, AppError> {
    Ok(determine_restore_options(device))
}

#[tauri::command]
pub async fn download_ipsw(
    app: AppHandle,
    request: IpswDownloadRequest,
) -> Result<IpswDownloadResult, AppError> {
    let url = request.url.trim();
    if url.is_empty() {
        return Err(AppError::Parse("Download URL is required".to_string()));
    }

    let output_dir = PathBuf::from(request.output_dir.trim());
    if output_dir.as_os_str().is_empty() {
        return Err(AppError::Parse("Output directory is required".to_string()));
    }
    fs::create_dir_all(&output_dir)?;

    let file_name = request
        .file_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .or_else(|| file_name_from_url(url))
        .ok_or_else(|| AppError::Parse("Unable to infer IPSW filename from URL".to_string()))?;

    if !file_name.ends_with(".ipsw") {
        return Err(AppError::Parse(
            "IPSW download filename must end with .ipsw".to_string(),
        ));
    }
    if Path::new(&file_name).file_name().and_then(|name| name.to_str()) != Some(file_name.as_str()) {
        return Err(AppError::Parse(
            "IPSW download filename cannot include path separators".to_string(),
        ));
    }

    emit_restore_log(&app, "info", &format!("Downloading {file_name}"));
    let aria2c = resolve_binary_path(&app, "aria2c").map_err(AppError::CommandFailed)?;
    let args = vec![
        "--continue=true".to_string(),
        "--max-connection-per-server=8".to_string(),
        "--split=8".to_string(),
        "--summary-interval=1".to_string(),
        "--dir".to_string(),
        output_dir.to_string_lossy().to_string(),
        "--out".to_string(),
        file_name.clone(),
        url.to_string(),
    ];

    run_process_streaming(&app, aria2c, &args)?;

    let path = output_dir.join(file_name);
    if !path.exists() {
        return Err(AppError::CommandFailed(format!(
            "Download finished but {} was not created",
            path.display()
        )));
    }

    Ok(IpswDownloadResult {
        path: path.to_string_lossy().to_string(),
    })
}

#[tauri::command]
pub async fn verify_ipsw(request: IpswVerifyRequest) -> Result<IpswVerifyResult, AppError> {
    let path = request.path.trim();
    if path.is_empty() {
        return Err(AppError::Parse("IPSW path is required".to_string()));
    }
    if !Path::new(path).exists() {
        return Err(AppError::Parse(format!("IPSW does not exist: {path}")));
    }

    let calculated_sha1 = sha1_file(path)?;
    let expected_sha1 = request
        .expected_sha1
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty());
    let matches = expected_sha1
        .as_ref()
        .map(|expected| expected == &calculated_sha1);

    Ok(IpswVerifyResult {
        path: path.to_string(),
        calculated_sha1,
        expected_sha1,
        matches,
    })
}

#[tauri::command]
pub async fn preview_restore_command(
    request: RestoreRunRequest,
) -> Result<RestoreCommandPreview, AppError> {
    build_restore_command(&request)
}

#[tauri::command]
pub async fn start_restore(
    app: AppHandle,
    request: RestoreRunRequest,
) -> Result<RestoreCommandPreview, AppError> {
    let preview = build_restore_command(&request)?;
    if request.dry_run {
        emit_restore_log(
            &app,
            "info",
            "Dry run requested; restore command was not started",
        );
        return Ok(preview);
    }

    let binary_path =
        resolve_binary_path(&app, &preview.binary).map_err(AppError::CommandFailed)?;
    emit_restore_log(
        &app,
        "info",
        &format!("Starting {} {}", preview.binary, preview.args.join(" ")),
    );
    run_process_streaming(&app, binary_path, &preview.args)?;
    emit_restore_log(&app, "info", "Restore tool finished");

    Ok(preview)
}

fn build_restore_command(request: &RestoreRunRequest) -> Result<RestoreCommandPreview, AppError> {
    let ipsw_path = request.ipsw_path.trim();
    if ipsw_path.is_empty() {
        return Err(AppError::Parse("Target IPSW path is required".to_string()));
    }
    if !Path::new(ipsw_path).exists() {
        return Err(AppError::Parse(format!("IPSW does not exist: {ipsw_path}")));
    }

    let mut warnings = Vec::new();
    let (binary, args) = match request.tool {
        RestoreTool::IdeviceRestore => {
            let mut args = Vec::new();
            if request.update {
                args.push("-u".to_string());
            } else if request.erase {
                args.push("-e".to_string());
            }
            args.push(ipsw_path.to_string());
            ("idevicerestore".to_string(), args)
        }
        RestoreTool::FutureRestore => {
            let shsh_path = request
                .shsh_path
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| {
                    AppError::Parse("FutureRestore requires a target SHSH blob".to_string())
                })?;
            if !Path::new(shsh_path).exists() {
                return Err(AppError::Parse(format!(
                    "SHSH blob does not exist: {shsh_path}"
                )));
            }

            let mut args = Vec::new();
            if request.no_baseband {
                args.push("--no-baseband".to_string());
            }
            if request.latest_sep {
                args.push("--latest-sep".to_string());
            }
            if request.latest_baseband {
                args.push("--latest-baseband".to_string());
            }
            if request.use_pwndfu {
                args.push("--use-pwndfu".to_string());
                warnings.push(
                    "Pwned DFU restore assumes the device is already in the required state."
                        .to_string(),
                );
            }
            if request.skip_blob {
                args.push("--skip-blob".to_string());
            }
            if request.set_nonce {
                args.push("--set-nonce".to_string());
            }
            args.push("-t".to_string());
            args.push(shsh_path.to_string());
            args.push(ipsw_path.to_string());
            ("futurerestore_new".to_string(), args)
        }
    };

    if matches!(request.tool, RestoreTool::IdeviceRestore) && !request.erase && !request.update {
        warnings.push(
            "idevicerestore will run without erase/update flags; confirm this is intended."
                .to_string(),
        );
    }

    Ok(RestoreCommandPreview {
        supported: true,
        tool: request.tool.clone(),
        binary,
        args,
        warnings,
    })
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
            emit_restore_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_restore_log(&stderr_app, "stderr", &line);
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

fn file_name_from_url(url: &str) -> Option<String> {
    url.split('/')
        .next_back()
        .and_then(|part| part.split('?').next())
        .filter(|part| !part.is_empty())
        .map(ToOwned::to_owned)
}

fn emit_restore_log(app: &AppHandle, level: &str, text: &str) {
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
