use crate::error::AppError;
use crate::models::shsh::{
    CydiaBlobAttempt, CydiaBlobRequest, CydiaBlobResult, DumpOnboardBlobRequest,
    DumpOnboardBlobResult, ListBlobsRequest, ListBlobsResult, SaveShshRequest, SaveShshResult,
};
use crate::platform::resolve_binary_path;
use crate::services::shsh_store;
use serde::Serialize;
use std::ffi::OsStr;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use tauri::{AppHandle, Emitter};

const CYDIA_TSS_URL: &str = "http://cydia.saurik.com/TSS/controller?action=2/";

#[tauri::command]
pub async fn save_shsh_blob(
    app: AppHandle,
    request: SaveShshRequest,
) -> Result<SaveShshResult, AppError> {
    let device_type = require_field(&request.device_type, "Device type")?;
    let device_ecid = require_field(&request.device_ecid, "Device ECID")?;
    let ios_version = require_field(&request.ios_version, "iOS version")?;
    let output_dir = require_field(&request.output_dir, "Output directory")?;
    fs::create_dir_all(&output_dir)?;

    let manifest_path = request
        .build_manifest_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if let Some(manifest) = manifest_path {
        if !Path::new(manifest).exists() {
            return Err(AppError::Parse(format!(
                "BuildManifest does not exist: {manifest}"
            )));
        }
    }

    let board_config = request
        .board_config
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let build_id = request
        .build_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let apnonce = request
        .apnonce
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let generator = request
        .generator
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());

    let mut args: Vec<String> = vec![
        "-d".to_string(),
        device_type.clone(),
        "-e".to_string(),
        device_ecid.clone(),
        "-i".to_string(),
        ios_version.clone(),
        "-s".to_string(),
        "-o".to_string(),
        "--save-path".to_string(),
        output_dir.clone(),
    ];

    if let Some(board) = board_config {
        args.push("-B".to_string());
        args.push(board.to_string());
    }
    if let Some(build) = build_id {
        args.push("--buildid".to_string());
        args.push(build.to_string());
    }
    if let Some(manifest) = manifest_path {
        args.push("-m".to_string());
        args.push(manifest.to_string());
    }
    if let Some(nonce) = apnonce {
        args.push("--apnonce".to_string());
        args.push(nonce.to_string());
    } else if let Some(gen_value) = generator {
        args.push("-g".to_string());
        args.push(gen_value.to_string());
    } else {
        args.push("-g".to_string());
        args.push("0x1111111111111111".to_string());
    }

    let binary = resolve_binary_path(&app, "tsschecker").map_err(AppError::CommandFailed)?;
    emit_shsh_log(
        &app,
        "info",
        &format!(
            "Saving SHSH for {device_type} ({device_ecid}) at iOS {ios_version}"
        ),
    );

    let blobs_before = collect_blob_paths(Path::new(&output_dir));
    run_process_streaming(&app, binary.clone(), &args)?;
    let blobs_after = collect_blob_paths(Path::new(&output_dir));

    let new_blobs: Vec<String> = blobs_after
        .into_iter()
        .filter(|p| !blobs_before.contains(p))
        .collect();

    if new_blobs.is_empty() {
        return Err(AppError::CommandFailed(
            "tsschecker finished but no new blob files were saved".to_string(),
        ));
    }

    emit_shsh_log(
        &app,
        "info",
        &format!("Saved {} blob file(s)", new_blobs.len()),
    );

    Ok(SaveShshResult {
        blob_paths: new_blobs,
        args,
    })
}

#[tauri::command]
pub async fn fetch_cydia_blobs(
    app: AppHandle,
    request: CydiaBlobRequest,
) -> Result<CydiaBlobResult, AppError> {
    let device_type = require_field(&request.device_type, "Device type")?;
    let device_ecid = require_field(&request.device_ecid, "Device ECID")?;
    let output_dir = require_field(&request.output_dir, "Output directory")?;
    fs::create_dir_all(&output_dir)?;

    if request.build_ids.is_empty() {
        return Err(AppError::Parse(
            "At least one build ID is required".to_string(),
        ));
    }

    let binary = resolve_binary_path(&app, "tsschecker").map_err(AppError::CommandFailed)?;
    let mut attempts = Vec::with_capacity(request.build_ids.len());

    for raw_build in &request.build_ids {
        let build = raw_build.trim();
        if build.is_empty() {
            continue;
        }

        emit_shsh_log(&app, "info", &format!("Trying Cydia blobs for {build}..."));
        let args = vec![
            "-d".to_string(),
            device_type.clone(),
            "-e".to_string(),
            device_ecid.clone(),
            "--server-url".to_string(),
            CYDIA_TSS_URL.to_string(),
            "-s".to_string(),
            "-g".to_string(),
            "0x1111111111111111".to_string(),
            "--buildid".to_string(),
            build.to_string(),
            "--save-path".to_string(),
            output_dir.clone(),
        ];

        let blobs_before = collect_blob_paths(Path::new(&output_dir));
        match run_process_capturing(&binary, &args) {
            Ok(_) => {
                let blobs_after = collect_blob_paths(Path::new(&output_dir));
                let new_blob = blobs_after
                    .into_iter()
                    .find(|p| !blobs_before.contains(p));
                match new_blob {
                    Some(found) => {
                        let dest = Path::new(&output_dir)
                            .join(format!("{device_ecid}-{device_type}-{build}.shsh"));
                        let final_path = if Path::new(&found) == dest {
                            found
                        } else {
                            match fs::rename(&found, &dest) {
                                Ok(_) => dest.to_string_lossy().to_string(),
                                Err(_) => found,
                            }
                        };
                        emit_shsh_log(
                            &app,
                            "info",
                            &format!("Saved Cydia blobs for {build}: {final_path}"),
                        );
                        attempts.push(CydiaBlobAttempt {
                            build_id: build.to_string(),
                            saved: true,
                            blob_path: Some(final_path),
                            message: None,
                        });
                    }
                    None => {
                        emit_shsh_log(
                            &app,
                            "warn",
                            &format!("No Cydia blobs available for {build}"),
                        );
                        attempts.push(CydiaBlobAttempt {
                            build_id: build.to_string(),
                            saved: false,
                            blob_path: None,
                            message: Some("Not saved on Cydia servers".to_string()),
                        });
                    }
                }
            }
            Err(err) => {
                emit_shsh_log(
                    &app,
                    "stderr",
                    &format!("tsschecker failed for {build}: {err}"),
                );
                attempts.push(CydiaBlobAttempt {
                    build_id: build.to_string(),
                    saved: false,
                    blob_path: None,
                    message: Some(err.to_string()),
                });
            }
        }
    }

    Ok(CydiaBlobResult { attempts })
}

#[tauri::command]
pub async fn dump_onboard_blob(
    app: AppHandle,
    request: DumpOnboardBlobRequest,
) -> Result<DumpOnboardBlobResult, AppError> {
    let raw_path = request.raw_dump_path.trim();
    if raw_path.is_empty() {
        return Err(AppError::Parse("Raw dump path is required".to_string()));
    }
    if !Path::new(raw_path).exists() {
        return Err(AppError::Parse(format!(
            "Raw dump file does not exist: {raw_path}"
        )));
    }

    let output_path = request.output_path.trim();
    if output_path.is_empty() {
        return Err(AppError::Parse(
            "Output blob path is required".to_string(),
        ));
    }
    if let Some(parent) = Path::new(output_path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }

    let args = vec![
        "--convert".to_string(),
        "-s".to_string(),
        output_path.to_string(),
        raw_path.to_string(),
    ];

    let binary = resolve_binary_path(&app, "img4tool").map_err(AppError::CommandFailed)?;
    emit_shsh_log(
        &app,
        "info",
        &format!("Converting raw dump to SHSH: {raw_path}"),
    );
    run_process_streaming(&app, binary, &args)?;

    let metadata = fs::metadata(output_path)
        .map_err(|e| AppError::CommandFailed(format!("Output blob not created: {e}")))?;
    if metadata.len() == 0 {
        let _ = fs::remove_file(output_path);
        return Err(AppError::CommandFailed(
            "img4tool produced an empty SHSH file".to_string(),
        ));
    }

    emit_shsh_log(
        &app,
        "info",
        &format!("Onboard blob written to {output_path}"),
    );

    Ok(DumpOnboardBlobResult {
        blob_path: output_path.to_string(),
        args,
    })
}

#[tauri::command]
pub async fn list_saved_blobs(request: ListBlobsRequest) -> Result<ListBlobsResult, AppError> {
    let directory = request.directory.trim().to_string();
    if directory.is_empty() {
        return Err(AppError::Parse("Directory is required".to_string()));
    }
    let blobs = shsh_store::list_saved_blobs(&directory)?;
    Ok(ListBlobsResult { directory, blobs })
}

fn require_field(value: &str, label: &str) -> Result<String, AppError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(AppError::Parse(format!("{label} is required")));
    }
    Ok(trimmed.to_string())
}

fn collect_blob_paths(dir: &Path) -> Vec<String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_file() {
                return None;
            }
            let ext = path.extension().and_then(OsStr::to_str)?.to_ascii_lowercase();
            if ext == "shsh" || ext == "shsh2" {
                Some(path.to_string_lossy().to_string())
            } else {
                None
            }
        })
        .collect()
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
            emit_shsh_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_shsh_log(&stderr_app, "stderr", &line);
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

fn run_process_capturing(binary: &Path, args: &[String]) -> Result<(), AppError> {
    let output = Command::new(binary)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()?;
    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(AppError::CommandFailed(if err.is_empty() {
            format!("{} exited with status {}", binary.display(), output.status)
        } else {
            err
        }));
    }
    Ok(())
}

fn emit_shsh_log(app: &AppHandle, level: &str, text: &str) {
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
