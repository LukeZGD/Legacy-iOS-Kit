use crate::error::AppError;
use crate::platform::resolve_binary_path;
use serde::{Deserialize, Serialize};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswExtractRequest {
    pub ipsw_path: String,
    pub component_path: String,
    pub output_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswExtractResult {
    pub output_path: String,
    pub bytes: u64,
}

#[tauri::command]
pub async fn extract_ipsw_component(
    app: AppHandle,
    request: IpswExtractRequest,
) -> Result<IpswExtractResult, AppError> {
    let ipsw_path = request.ipsw_path.trim();
    if ipsw_path.is_empty() {
        return Err(AppError::Parse("IPSW path is required".to_string()));
    }
    if !Path::new(ipsw_path).exists() {
        return Err(AppError::Parse(format!(
            "IPSW does not exist: {ipsw_path}"
        )));
    }

    let component_path = request.component_path.trim();
    if component_path.is_empty() {
        return Err(AppError::Parse("Component path is required".to_string()));
    }

    let output_path = PathBuf::from(request.output_path.trim());
    if output_path.as_os_str().is_empty() {
        return Err(AppError::Parse("Output path is required".to_string()));
    }
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }

    emit_firmware_log(
        &app,
        "info",
        &format!("Extracting {component_path} from {ipsw_path}"),
    );

    let bytes = extract_zip_entry(ipsw_path, component_path, &output_path)?;

    emit_firmware_log(
        &app,
        "info",
        &format!("Wrote {} bytes to {}", bytes, output_path.display()),
    );

    Ok(IpswExtractResult {
        output_path: output_path.to_string_lossy().to_string(),
        bytes,
    })
}

fn extract_zip_entry(
    archive_path: &str,
    entry_name: &str,
    output_path: &Path,
) -> Result<u64, AppError> {
    let file = File::open(archive_path)?;
    let mut archive = zip::ZipArchive::new(file)
        .map_err(|e| AppError::CommandFailed(format!("Failed to open IPSW: {e}")))?;

    let mut entry = archive
        .by_name(entry_name)
        .map_err(|e| AppError::CommandFailed(format!("Entry '{entry_name}' not found: {e}")))?;

    let mut output = File::create(output_path)?;
    let bytes = io::copy(&mut entry, &mut output)?;
    Ok(bytes)
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum IbootBitWidth {
    Bits32,
    Bits64,
}

impl IbootBitWidth {
    fn binary_name(&self) -> &'static str {
        match self {
            IbootBitWidth::Bits32 => "iBoot32Patcher",
            IbootBitWidth::Bits64 => "iBoot64Patcher",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IbootPatchRequest {
    pub input_path: String,
    pub output_path: String,
    pub bit_width: IbootBitWidth,
    pub boot_args: Option<String>,
    pub bypass_rsa: bool,
    pub debug: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IbootPatchResult {
    pub output_path: String,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn patch_iboot(
    app: AppHandle,
    request: IbootPatchRequest,
) -> Result<IbootPatchResult, AppError> {
    let input_path = request.input_path.trim();
    if input_path.is_empty() {
        return Err(AppError::Parse("iBoot input path is required".to_string()));
    }
    if !Path::new(input_path).exists() {
        return Err(AppError::Parse(format!(
            "iBoot input does not exist: {input_path}"
        )));
    }

    let output_path = request.output_path.trim();
    if output_path.is_empty() {
        return Err(AppError::Parse("iBoot output path is required".to_string()));
    }
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)?;
    }

    let args = build_iboot_args(&request);
    let binary =
        resolve_binary_path(&app, request.bit_width.binary_name()).map_err(AppError::CommandFailed)?;

    emit_firmware_log(
        &app,
        "info",
        &format!(
            "Patching iBoot ({}) -> {}",
            request.bit_width.binary_name(),
            output_path
        ),
    );
    run_process_streaming(&app, binary.clone(), &args)?;

    if !Path::new(output_path).exists() {
        return Err(AppError::CommandFailed(format!(
            "{} finished but output was not created at {output_path}",
            request.bit_width.binary_name()
        )));
    }

    Ok(IbootPatchResult {
        output_path: output_path.to_string(),
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

fn build_iboot_args(request: &IbootPatchRequest) -> Vec<String> {
    let mut args = vec![
        request.input_path.trim().to_string(),
        request.output_path.trim().to_string(),
    ];
    if let Some(boot_args) = request.boot_args.as_deref().map(str::trim) {
        if !boot_args.is_empty() {
            args.push("-b".to_string());
            args.push(boot_args.to_string());
        }
    }
    if request.bypass_rsa {
        args.push("-r".to_string());
    }
    if request.debug {
        args.push("-d".to_string());
    }
    args
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Img4PackRequest {
    pub im4p_path: String,
    pub output_path: String,
    pub shsh_path: Option<String>,
    pub im4m_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Img4PackResult {
    pub output_path: String,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn pack_img4(
    app: AppHandle,
    request: Img4PackRequest,
) -> Result<Img4PackResult, AppError> {
    let im4p_path = request.im4p_path.trim();
    if im4p_path.is_empty() {
        return Err(AppError::Parse("IM4P payload path is required".to_string()));
    }
    if !Path::new(im4p_path).exists() {
        return Err(AppError::Parse(format!(
            "IM4P payload does not exist: {im4p_path}"
        )));
    }

    let output_path = request.output_path.trim();
    if output_path.is_empty() {
        return Err(AppError::Parse("IMG4 output path is required".to_string()));
    }
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)?;
    }

    let shsh_path = request
        .shsh_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let im4m_path = request
        .im4m_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());

    if let Some(shsh) = shsh_path {
        if !Path::new(shsh).exists() {
            return Err(AppError::Parse(format!(
                "SHSH manifest does not exist: {shsh}"
            )));
        }
    }
    if let Some(im4m) = im4m_path {
        if !Path::new(im4m).exists() {
            return Err(AppError::Parse(format!(
                "IM4M manifest does not exist: {im4m}"
            )));
        }
    }

    let args = build_img4_pack_args(im4p_path, output_path, shsh_path, im4m_path);
    let binary = resolve_binary_path(&app, "img4tool").map_err(AppError::CommandFailed)?;

    emit_firmware_log(
        &app,
        "info",
        &format!("Packing IMG4 -> {output_path}"),
    );
    run_process_streaming(&app, binary.clone(), &args)?;

    if !Path::new(output_path).exists() {
        return Err(AppError::CommandFailed(format!(
            "img4tool finished but output was not created at {output_path}"
        )));
    }

    Ok(Img4PackResult {
        output_path: output_path.to_string(),
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

fn build_img4_pack_args(
    im4p_path: &str,
    output_path: &str,
    shsh_path: Option<&str>,
    im4m_path: Option<&str>,
) -> Vec<String> {
    let mut args = vec![
        "-c".to_string(),
        output_path.to_string(),
        "-p".to_string(),
        im4p_path.to_string(),
    ];
    if let Some(shsh) = shsh_path {
        args.push("-s".to_string());
        args.push(shsh.to_string());
    }
    if let Some(im4m) = im4m_path {
        args.push("-m".to_string());
        args.push(im4m.to_string());
    }
    args
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Img3RepackRequest {
    pub input_path: String,
    pub output_path: String,
    pub template_path: Option<String>,
    pub key: Option<String>,
    pub iv: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Img3RepackResult {
    pub output_path: String,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn repack_img3(
    app: AppHandle,
    request: Img3RepackRequest,
) -> Result<Img3RepackResult, AppError> {
    let input_path = request.input_path.trim();
    if input_path.is_empty() {
        return Err(AppError::Parse("IMG3 input path is required".to_string()));
    }
    if !Path::new(input_path).exists() {
        return Err(AppError::Parse(format!(
            "IMG3 input does not exist: {input_path}"
        )));
    }

    let output_path = request.output_path.trim();
    if output_path.is_empty() {
        return Err(AppError::Parse("IMG3 output path is required".to_string()));
    }
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)?;
    }

    let template_path = request
        .template_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if let Some(template) = template_path {
        if !Path::new(template).exists() {
            return Err(AppError::Parse(format!(
                "IMG3 template does not exist: {template}"
            )));
        }
    }

    let key = request
        .key
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let iv = request
        .iv
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());

    let args = build_img3_repack_args(input_path, output_path, template_path, key, iv);
    let binary = resolve_binary_path(&app, "xpwntool").map_err(AppError::CommandFailed)?;

    emit_firmware_log(
        &app,
        "info",
        &format!("Repacking IMG3 -> {output_path}"),
    );
    run_process_streaming(&app, binary.clone(), &args)?;

    if !Path::new(output_path).exists() {
        return Err(AppError::CommandFailed(format!(
            "xpwntool finished but output was not created at {output_path}"
        )));
    }

    Ok(Img3RepackResult {
        output_path: output_path.to_string(),
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

fn build_img3_repack_args(
    input_path: &str,
    output_path: &str,
    template_path: Option<&str>,
    key: Option<&str>,
    iv: Option<&str>,
) -> Vec<String> {
    let mut args = vec![input_path.to_string(), output_path.to_string()];
    if let Some(template) = template_path {
        args.push("-t".to_string());
        args.push(template.to_string());
    }
    if let Some(k) = key {
        args.push("-k".to_string());
        args.push(k.to_string());
    }
    if let Some(v) = iv {
        args.push("-iv".to_string());
        args.push(v.to_string());
    }
    args
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RamdiskAction {
    Add,
    Remove,
    Resize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RamdiskModifyRequest {
    pub ramdisk_path: String,
    pub action: RamdiskAction,
    /// For `Add`: local source file. For `Remove`: ignored. For `Resize`: ignored.
    pub source_path: Option<String>,
    /// For `Add` / `Remove`: path inside the ramdisk (e.g. `/usr/local/bin/dropbear`).
    pub target_path: Option<String>,
    /// For `Resize`: target size in MB (e.g. `35`). For `Add` / `Remove`: ignored.
    pub size_mb: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RamdiskModifyResult {
    pub ramdisk_path: String,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn modify_ramdisk(
    app: AppHandle,
    request: RamdiskModifyRequest,
) -> Result<RamdiskModifyResult, AppError> {
    let ramdisk_path = request.ramdisk_path.trim();
    if ramdisk_path.is_empty() {
        return Err(AppError::Parse("Ramdisk path is required".to_string()));
    }
    if !Path::new(ramdisk_path).exists() {
        return Err(AppError::Parse(format!(
            "Ramdisk does not exist: {ramdisk_path}"
        )));
    }

    let args = build_ramdisk_args(&request)?;
    let binary = resolve_binary_path(&app, "hfsplus").map_err(AppError::CommandFailed)?;

    emit_firmware_log(
        &app,
        "info",
        &format!("hfsplus {} {}", ramdisk_path, args[1..].join(" ")),
    );
    run_process_streaming(&app, binary.clone(), &args)?;

    Ok(RamdiskModifyResult {
        ramdisk_path: ramdisk_path.to_string(),
        binary: binary.to_string_lossy().to_string(),
        args,
    })
}

fn build_ramdisk_args(request: &RamdiskModifyRequest) -> Result<Vec<String>, AppError> {
    let ramdisk_path = request.ramdisk_path.trim().to_string();
    let mut args = vec![ramdisk_path];

    match request.action {
        RamdiskAction::Add => {
            let source = request
                .source_path
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .ok_or_else(|| {
                    AppError::Parse("`Add` requires a source path".to_string())
                })?;
            let target = request
                .target_path
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .ok_or_else(|| {
                    AppError::Parse("`Add` requires a target path inside the ramdisk".to_string())
                })?;
            if !Path::new(source).exists() {
                return Err(AppError::Parse(format!(
                    "Source file does not exist: {source}"
                )));
            }
            args.push("add".to_string());
            args.push(source.to_string());
            args.push(target.to_string());
        }
        RamdiskAction::Remove => {
            let target = request
                .target_path
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .ok_or_else(|| {
                    AppError::Parse(
                        "`Remove` requires a target path inside the ramdisk".to_string(),
                    )
                })?;
            args.push("rm".to_string());
            args.push(target.to_string());
        }
        RamdiskAction::Resize => {
            let size = request.size_mb.ok_or_else(|| {
                AppError::Parse("`Resize` requires a size in MB".to_string())
            })?;
            if size == 0 {
                return Err(AppError::Parse("Resize size must be > 0".to_string()));
            }
            args.push("grow".to_string());
            args.push(format!("{}", (size as u64) * 1024 * 1024));
        }
    }

    Ok(args)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KernelPatchRequest {
    pub input_path: String,
    pub output_path: String,
    pub bit_width: IbootBitWidth,
    /// Patcher-specific flag list (e.g. `["-a", "-f"]`). Passed through verbatim.
    pub flags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KernelPatchResult {
    pub output_path: String,
    pub binary: String,
    pub args: Vec<String>,
}

#[tauri::command]
pub async fn patch_kernel(
    app: AppHandle,
    request: KernelPatchRequest,
) -> Result<KernelPatchResult, AppError> {
    let input_path = request.input_path.trim();
    if input_path.is_empty() {
        return Err(AppError::Parse("Kernel input path is required".to_string()));
    }
    if !Path::new(input_path).exists() {
        return Err(AppError::Parse(format!(
            "Kernel input does not exist: {input_path}"
        )));
    }

    let output_path = request.output_path.trim();
    if output_path.is_empty() {
        return Err(AppError::Parse("Kernel output path is required".to_string()));
    }
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)?;
    }

    let binary_name = match request.bit_width {
        IbootBitWidth::Bits32 => "Kernel32Patcher",
        IbootBitWidth::Bits64 => "Kernel64Patcher",
    };

    let mut args = vec![input_path.to_string(), output_path.to_string()];
    for flag in request.flags.iter() {
        let trimmed = flag.trim();
        if !trimmed.is_empty() {
            args.push(trimmed.to_string());
        }
    }

    let binary = resolve_binary_path(&app, binary_name).map_err(AppError::CommandFailed)?;
    emit_firmware_log(
        &app,
        "info",
        &format!("Patching kernel ({binary_name}) -> {output_path}"),
    );
    run_process_streaming(&app, binary.clone(), &args)?;

    if !Path::new(output_path).exists() {
        return Err(AppError::CommandFailed(format!(
            "{binary_name} finished but output was not created at {output_path}"
        )));
    }

    Ok(KernelPatchResult {
        output_path: output_path.to_string(),
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
            emit_firmware_log(&stdout_app, "stdout", &line);
        }
    });

    let stderr_app = app.clone();
    let stderr_thread = thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            emit_firmware_log(&stderr_app, "stderr", &line);
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

fn emit_firmware_log(app: &AppHandle, level: &str, text: &str) {
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
    fn iboot_args_minimal() {
        let request = IbootPatchRequest {
            input_path: "/tmp/iBSS".to_string(),
            output_path: "/tmp/iBSS.patched".to_string(),
            bit_width: IbootBitWidth::Bits32,
            boot_args: None,
            bypass_rsa: false,
            debug: false,
        };
        assert_eq!(
            build_iboot_args(&request),
            vec!["/tmp/iBSS", "/tmp/iBSS.patched"]
        );
    }

    #[test]
    fn iboot_args_full() {
        let request = IbootPatchRequest {
            input_path: "/tmp/iBEC".to_string(),
            output_path: "/tmp/iBEC.patched".to_string(),
            bit_width: IbootBitWidth::Bits64,
            boot_args: Some("rd=md0 -v".to_string()),
            bypass_rsa: true,
            debug: true,
        };
        assert_eq!(
            build_iboot_args(&request),
            vec![
                "/tmp/iBEC",
                "/tmp/iBEC.patched",
                "-b",
                "rd=md0 -v",
                "-r",
                "-d",
            ]
        );
    }

    #[test]
    fn img4_pack_args_minimal() {
        let args = build_img4_pack_args("/tmp/in.im4p", "/tmp/out.img4", None, None);
        assert_eq!(args, vec!["-c", "/tmp/out.img4", "-p", "/tmp/in.im4p"]);
    }

    #[test]
    fn img4_pack_args_with_shsh() {
        let args = build_img4_pack_args(
            "/tmp/in.im4p",
            "/tmp/out.img4",
            Some("/tmp/blob.shsh2"),
            None,
        );
        assert_eq!(
            args,
            vec![
                "-c",
                "/tmp/out.img4",
                "-p",
                "/tmp/in.im4p",
                "-s",
                "/tmp/blob.shsh2",
            ]
        );
    }

    #[test]
    fn img4_pack_args_with_im4m() {
        let args = build_img4_pack_args(
            "/tmp/in.im4p",
            "/tmp/out.img4",
            None,
            Some("/tmp/manifest.im4m"),
        );
        assert_eq!(
            args,
            vec![
                "-c",
                "/tmp/out.img4",
                "-p",
                "/tmp/in.im4p",
                "-m",
                "/tmp/manifest.im4m",
            ]
        );
    }

    #[test]
    fn img3_repack_args_with_template() {
        let args = build_img3_repack_args(
            "/tmp/in.bin",
            "/tmp/out.img3",
            Some("/tmp/template.img3"),
            None,
            None,
        );
        assert_eq!(
            args,
            vec!["/tmp/in.bin", "/tmp/out.img3", "-t", "/tmp/template.img3"]
        );
    }

    #[test]
    fn img3_repack_args_with_key_iv() {
        let args = build_img3_repack_args(
            "/tmp/in.bin",
            "/tmp/out.img3",
            None,
            Some("aabbcc"),
            Some("ddeeff"),
        );
        assert_eq!(
            args,
            vec![
                "/tmp/in.bin",
                "/tmp/out.img3",
                "-k",
                "aabbcc",
                "-iv",
                "ddeeff",
            ]
        );
    }

    #[test]
    fn ramdisk_resize_args_use_bytes() {
        let request = RamdiskModifyRequest {
            ramdisk_path: "/tmp/rd.dmg".to_string(),
            action: RamdiskAction::Resize,
            source_path: None,
            target_path: None,
            size_mb: Some(35),
        };
        let args = build_ramdisk_args(&request).unwrap();
        assert_eq!(args, vec!["/tmp/rd.dmg", "grow", "36700160"]);
    }

    #[test]
    fn ramdisk_remove_requires_target() {
        let request = RamdiskModifyRequest {
            ramdisk_path: "/tmp/rd.dmg".to_string(),
            action: RamdiskAction::Remove,
            source_path: None,
            target_path: Some("/usr/local/bin/dropbear".to_string()),
            size_mb: None,
        };
        let args = build_ramdisk_args(&request).unwrap();
        assert_eq!(
            args,
            vec!["/tmp/rd.dmg", "rm", "/usr/local/bin/dropbear"]
        );
    }

    #[test]
    fn ramdisk_remove_without_target_errors() {
        let request = RamdiskModifyRequest {
            ramdisk_path: "/tmp/rd.dmg".to_string(),
            action: RamdiskAction::Remove,
            source_path: None,
            target_path: None,
            size_mb: None,
        };
        assert!(build_ramdisk_args(&request).is_err());
    }
}
