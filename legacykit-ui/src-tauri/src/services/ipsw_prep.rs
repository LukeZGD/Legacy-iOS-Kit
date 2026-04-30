use crate::error::AppError;
use std::path::{Path, PathBuf};

/// Derives the output path for a powdersn0w-prepared IPSW.
/// Appends `_custom` to the source filename stem in the given output directory.
pub fn powdersn0w_output_path(source_ipsw: &str, output_dir: &str) -> Result<PathBuf, AppError> {
    let stem = Path::new(source_ipsw)
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| AppError::Parse("Cannot determine IPSW filename stem".to_string()))?;
    Ok(PathBuf::from(output_dir).join(format!("{stem}_custom.ipsw")))
}

/// Builds the CLI argument list for a powdersn0w invocation.
///
/// - `-i` / `-o` are always included (input IPSW and output IPSW).
/// - `-b <blob>` is added when `shsh_path` is Some — required for A5/A5X blob-based restores.
/// - `--ecid <ecid>` is added when `device_ecid` is Some.
pub fn build_powdersn0w_args(
    ipsw_path: &str,
    output_path: &Path,
    shsh_path: Option<&str>,
    device_ecid: Option<&str>,
) -> Vec<String> {
    let mut args = vec![
        "-i".to_string(),
        ipsw_path.to_string(),
        "-o".to_string(),
        output_path.to_string_lossy().to_string(),
    ];
    if let Some(shsh) = shsh_path {
        args.push("-b".to_string());
        args.push(shsh.to_string());
    }
    if let Some(ecid) = device_ecid {
        args.push("--ecid".to_string());
        args.push(ecid.to_string());
    }
    args
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_path_appends_custom_suffix() {
        let out = powdersn0w_output_path("/tmp/iPhone3,1_7.1.2.ipsw", "/tmp/out").unwrap();
        assert_eq!(out.file_name().unwrap(), "iPhone3,1_7.1.2_custom.ipsw");
        assert_eq!(out.parent().unwrap(), Path::new("/tmp/out"));
    }

    #[test]
    fn args_without_shsh_or_ecid() {
        let out = Path::new("/tmp/out/custom.ipsw");
        let args = build_powdersn0w_args("/tmp/in.ipsw", out, None, None);
        assert_eq!(args, vec!["-i", "/tmp/in.ipsw", "-o", "/tmp/out/custom.ipsw"]);
    }

    #[test]
    fn args_with_shsh_and_ecid() {
        let out = Path::new("/tmp/out/custom.ipsw");
        let args =
            build_powdersn0w_args("/tmp/in.ipsw", out, Some("/tmp/blob.shsh2"), Some("AABBCC"));
        assert_eq!(
            args,
            vec![
                "-i",
                "/tmp/in.ipsw",
                "-o",
                "/tmp/out/custom.ipsw",
                "-b",
                "/tmp/blob.shsh2",
                "--ecid",
                "AABBCC",
            ]
        );
    }
}
