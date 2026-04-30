use std::path::PathBuf;
use tauri::{AppHandle, Manager};

/// Resolves the path to a bundled sidecar binary based on the current platform and architecture.
/// 
/// Note: Tauri's built-in `resolve_resource` or sidecar mechanisms are preferred,
/// but since we copied the existing directory structure directly, this helper
/// constructs the path based on `std::env::consts`.
pub fn resolve_binary_path(app: &AppHandle, binary_name: &str) -> Result<PathBuf, String> {
    let os = std::env::consts::OS;
    let arch = std::env::consts::ARCH;

    let platform_dir = match os {
        "macos" => "macos",
        "linux" => "linux",
        _ => return Err(format!("Unsupported operating system: {}", os)),
    };

    // Note: The bin directory has binaries at macos/ and macos/arm64/.
    // For linux, it's linux/x86_64/ and linux/arm64/.
    // We try to find the binary in the most specific directory first, then fallback.
    
    let resource_path = app
        .path()
        .resource_dir()
        .map_err(|e| format!("Failed to get resource dir: {}", e))?;

    let base_bin_dir = resource_path.join("binaries").join(platform_dir);

    // Construct possible paths
    let mut possible_paths = Vec::new();

    if os == "macos" {
        if arch == "aarch64" {
            possible_paths.push(base_bin_dir.join("arm64").join(binary_name));
        }
        // Fallback or x86_64 path for macOS
        possible_paths.push(base_bin_dir.join(binary_name));
    } else if os == "linux" {
        if arch == "aarch64" {
             possible_paths.push(base_bin_dir.join("arm64").join(binary_name));
        } else if arch == "x86_64" {
             possible_paths.push(base_bin_dir.join("x86_64").join(binary_name));
        }
    }

    // Return the first path that actually exists
    for path in possible_paths {
        if path.exists() {
            return Ok(path);
        }
    }

    Err(format!("Binary '{}' not found for OS {} and Arch {}", binary_name, os, arch))
}
