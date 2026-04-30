use crate::error::AppError;
use crate::platform::resolve_binary_path;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum GasterAction {
    Pwn,
    Reset,
}

impl GasterAction {
    fn as_arg(&self) -> &'static str {
        match self {
            GasterAction::Pwn => "pwn",
            GasterAction::Reset => "reset",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasterRequest {
    pub action: GasterAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasterResult {
    pub action: GasterAction,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn run_gaster(
    app: AppHandle,
    request: GasterRequest,
) -> Result<GasterResult, AppError> {
    let binary = resolve_binary_path(&app, "gaster").map_err(AppError::CommandFailed)?;
    let args = vec![request.action.as_arg().to_string()];

    emit_jailbreak_log(
        &app,
        "info",
        &format!("Running gaster {}...", request.action.as_arg()),
    );
    run_process_streaming(&app, binary.clone(), &args)?;
    emit_jailbreak_log(&app, "info", "gaster finished");

    Ok(GasterResult {
        action: request.action,
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KloaderRequest {
    pub ibss_path: String,
    pub ibec_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KloaderResult {
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn run_kloader(
    app: AppHandle,
    request: KloaderRequest,
) -> Result<KloaderResult, AppError> {
    let ibss_path = request.ibss_path.trim();
    if ibss_path.is_empty() {
        return Err(AppError::Parse("Patched iBSS path is required".to_string()));
    }
    if !Path::new(ibss_path).exists() {
        return Err(AppError::Parse(format!(
            "Patched iBSS does not exist: {ibss_path}"
        )));
    }

    let ibec_path = request
        .ibec_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if let Some(ibec) = ibec_path {
        if !Path::new(ibec).exists() {
            return Err(AppError::Parse(format!(
                "Patched iBEC does not exist: {ibec}"
            )));
        }
    }

    let mut args = vec![ibss_path.to_string()];
    if let Some(ibec) = ibec_path {
        args.push(ibec.to_string());
    }

    let binary = resolve_binary_path(&app, "kloader").map_err(AppError::CommandFailed)?;
    emit_jailbreak_log(
        &app,
        "info",
        &format!("Booting patched components with kloader: {}", args.join(" ")),
    );
    run_process_streaming(&app, binary.clone(), &args)?;
    emit_jailbreak_log(&app, "info", "kloader finished");

    Ok(KloaderResult {
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UntetherRequest {
    /// Optional extra flags (e.g. `["-v"]`). Passed verbatim after any required positional args.
    pub extra_args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UntetherResult {
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn run_g1lbertjb(
    app: AppHandle,
    request: UntetherRequest,
) -> Result<UntetherResult, AppError> {
    run_untether(&app, "g1lbertJB", request.extra_args).await
}

#[tauri::command]
pub async fn run_evasi0n(
    app: AppHandle,
    request: UntetherRequest,
) -> Result<UntetherResult, AppError> {
    run_untether(&app, "evasi0n", request.extra_args).await
}

async fn run_untether(
    app: &AppHandle,
    binary_name: &str,
    extra_args: Vec<String>,
) -> Result<UntetherResult, AppError> {
    let args: Vec<String> = extra_args
        .into_iter()
        .map(|arg| arg.trim().to_string())
        .filter(|arg| !arg.is_empty())
        .collect();

    let binary = resolve_binary_path(app, binary_name).map_err(AppError::CommandFailed)?;
    emit_jailbreak_log(
        app,
        "info",
        &format!("Running {} {}", binary_name, args.join(" ")),
    );
    run_process_streaming(app, binary.clone(), &args)?;
    emit_jailbreak_log(app, "info", &format!("{binary_name} finished"));

    Ok(UntetherResult {
        binary: binary.to_string_lossy().to_string(),
        args,
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
            emit_jailbreak_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_jailbreak_log(&stderr_app, "stderr", &line);
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

fn emit_jailbreak_log(app: &AppHandle, level: &str, text: &str) {
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
