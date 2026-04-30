use crate::error::AppError;
use crate::models::device::{DeviceInfo, DeviceMode};
use crate::platform::resolve_binary_path;
use std::process::Command;

#[tauri::command]
pub async fn detect_device(app: tauri::AppHandle) -> Result<DeviceInfo, AppError> {
    // Try ideviceinfo first (normal mode)
    if let Ok(ideviceinfo_path) = resolve_binary_path(&app, "ideviceinfo") {
        if let Ok(output) = Command::new(&ideviceinfo_path).output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut info = DeviceInfo {
                    connected: true,
                    mode: DeviceMode::Normal,
                    ..Default::default()
                };
                
                for line in stdout.lines() {
                    if let Some((key, value)) = line.split_once(": ") {
                        let key = key.trim();
                        let value = value.trim().to_string();
                        match key {
                            "DeviceName" => info.name = Some(value),
                            "UniqueDeviceID" => info.udid = Some(value),
                            "SerialNumber" => info.serial = Some(value),
                            "ProductType" => info.product_type = Some(value),
                            "HardwareModel" => info.model = Some(value),
                            "ProductVersion" => info.ios_version = Some(value),
                            "UniqueChipID" => info.ecid = Some(value),
                            _ => {}
                        }
                    }
                }
                
                return Ok(info);
            }
        }
    }
    
    // Fallback: try irecovery for Recovery/DFU mode
    if let Ok(irecovery_path) = resolve_binary_path(&app, "irecovery") {
        if let Ok(output) = Command::new(&irecovery_path).arg("-q").output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut info = DeviceInfo {
                    connected: true,
                    mode: DeviceMode::Recovery,
                    ..Default::default()
                };
                
                for line in stdout.lines() {
                    if let Some((key, value)) = line.split_once(": ") {
                        let key = key.trim();
                        let value = value.trim().to_string();
                        match key {
                            "ECID" => info.ecid = Some(value),
                            "SRNM" => info.serial = Some(value),
                            "PRODUCT" | "ProductType" => info.product_type = Some(value),
                            "MODEL" => info.model = Some(value),
                            "MODE" => {
                                info.mode = match value.as_str() {
                                    "DFU" => DeviceMode::DFU,
                                    "Recovery" => DeviceMode::Recovery,
                                    _ => DeviceMode::Recovery,
                                };
                            }
                            _ => {}
                        }
                    }
                }
                
                return Ok(info);
            }
        }
    }
    
    // No device found
    Ok(DeviceInfo::default())
}
