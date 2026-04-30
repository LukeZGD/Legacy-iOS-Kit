use crate::models::device::DeviceInfo;
use crate::models::restore::{RestoreOption, RestoreOptionKind, RestoreOptionsResponse};

pub fn determine_restore_options(device: DeviceInfo) -> RestoreOptionsResponse {
    let product_type = device.product_type.clone();
    let processor_generation = product_type.as_deref().and_then(infer_processor_generation);

    let mut response = RestoreOptionsResponse {
        product_type,
        processor_generation,
        options: Vec::new(),
        warnings: Vec::new(),
    };

    let Some(product_type) = response.product_type.clone() else {
        response.warnings.push(
            "Connect a device in normal, recovery, or DFU mode before choosing a restore path."
                .to_string(),
        );
        response.options.push(ipsw_downloader_option());
        return response;
    };

    add_ota_downgrades(&mut response, &product_type);
    add_powdersnow_options(&mut response, &product_type);
    add_latest_option(&mut response);
    add_special_versions(&mut response, &product_type);
    add_blob_and_custom_options(&mut response, &product_type);
    add_mode_options(&mut response);
    add_device_warnings(&mut response, &product_type);
    response.options.push(ipsw_downloader_option());

    response
}

fn add_ota_downgrades(response: &mut RestoreOptionsResponse, product_type: &str) {
    if matches_any(
        product_type,
        &[
            "iPad4,1",
            "iPad4,2",
            "iPad4,3",
            "iPad4,4",
            "iPad4,5",
            "iPhone6,1",
            "iPhone6,2",
        ],
    ) {
        response.options.push(version_option(
            RestoreOptionKind::OtaDowngrade,
            "iOS 10.3.3",
            "OTA downgrade path supported by the legacy restore workflow.",
            false,
            false,
        ));
    }

    if product_family_in(product_type, "iPad2", 1..=7)
        || product_family_in(product_type, "iPad3", 1..=6)
        || matches_any(
            product_type,
            &["iPhone4,1", "iPhone5,1", "iPhone5,2", "iPod5,1"],
        )
    {
        response.options.push(version_option(
            RestoreOptionKind::OtaDowngrade,
            "iOS 8.4.1",
            "OTA downgrade path supported by the legacy restore workflow.",
            false,
            false,
        ));
    }

    if product_family_in(product_type, "iPad2", 1..=3) || product_type == "iPhone4,1" {
        response.options.push(version_option(
            RestoreOptionKind::OtaDowngrade,
            "iOS 6.1.3",
            "OTA downgrade path supported by the legacy restore workflow.",
            false,
            false,
        ));
    }

    match product_type {
        "iPhone2,1" => {
            for version in ["5.1.1", "4.3.5", "4.1", "3.1.3"] {
                response.options.push(version_option(
                    RestoreOptionKind::OtaDowngrade,
                    version,
                    "Legacy 3GS restore path from the original menu.",
                    false,
                    false,
                ));
            }
            response.options.push(more_versions_option());
        }
        "iPod3,1" => response.options.push(version_option(
            RestoreOptionKind::OtaDowngrade,
            "4.1",
            "Legacy iPod touch restore path from the original menu.",
            false,
            false,
        )),
        "iPhone1,2" | "iPod2,1" => {
            for version in ["4.1", "3.1.3"] {
                response.options.push(version_option(
                    RestoreOptionKind::OtaDowngrade,
                    version,
                    "Legacy restore path from the original menu.",
                    false,
                    false,
                ));
            }
            if product_type == "iPod2,1" {
                response.options.push(more_versions_option());
                response.warnings.push(
                    "iPod2,1 extra versions depend on bootrom details that are not detected yet."
                        .to_string(),
                );
            }
        }
        _ => {}
    }
}

fn add_powdersnow_options(response: &mut RestoreOptionsResponse, product_type: &str) {
    if product_type == "iPhone3,1"
        || product_type == "iPhone3,3"
        || product_type == "iPad1,1"
        || product_type == "iPod3,1"
    {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::Powdersnow,
            title: "powdersn0w (any iOS)".to_string(),
            description: "Build and restore a powdersn0w custom IPSW for supported A4-era devices."
                .to_string(),
            target_version: None,
            requires_blobs: true,
            requires_dfu: true,
        });
    }

    let Some(proc_gen) = response.processor_generation else {
        return;
    };

    if proc_gen != 4 && can_use_powdersnow_blobs(product_type) {
        let target = if matches_any(
            product_type,
            &[
                "iPhone5,1",
                "iPhone5,2",
                "iPhone5,3",
                "iPhone5,4",
                "iPod5,1",
            ],
        ) {
            "7.x"
        } else if product_family_in(product_type, "iPad3", 4..=6) {
            "7.0.x"
        } else {
            "7.1.x"
        };

        response.options.push(RestoreOption {
            kind: RestoreOptionKind::Powdersnow,
            title: format!("Other (powdersn0w {target} blobs)"),
            description: "Use saved blobs with the powdersn0w restore flow.".to_string(),
            target_version: Some(target.to_string()),
            requires_blobs: true,
            requires_dfu: true,
        });
    }
}

fn add_latest_option(response: &mut RestoreOptionsResponse) {
    let platform = std::env::consts::OS;
    let Some(proc_gen) = response.processor_generation else {
        return;
    };

    if proc_gen < 7 || platform == "linux" {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::Latest,
            title: "Latest iOS".to_string(),
            description: "Restore to the latest supported firmware for this device.".to_string(),
            target_version: None,
            requires_blobs: false,
            requires_dfu: false,
        });
    }
}

fn add_special_versions(response: &mut RestoreOptionsResponse, product_type: &str) {
    match product_type {
        "iPod4,1" => response.options.push(version_option(
            RestoreOptionKind::OtaDowngrade,
            "7.1.2",
            "Special restore path for iPod touch 4.",
            false,
            false,
        )),
        "iPod3,1" => {
            for version in ["6.0", "6.1.3", "6.1.6"] {
                response.options.push(version_option(
                    RestoreOptionKind::OtaDowngrade,
                    version,
                    "Special restore path for iPod touch 3.",
                    false,
                    false,
                ));
            }
        }
        "iPad1,1" => {
            for version in ["6.1.3", "7.1.2"] {
                response.options.push(version_option(
                    RestoreOptionKind::OtaDowngrade,
                    version,
                    "Special restore path for iPad 1.",
                    false,
                    false,
                ));
            }
        }
        _ => {}
    }
}

fn add_blob_and_custom_options(response: &mut RestoreOptionsResponse, product_type: &str) {
    let Some(proc_gen) = response.processor_generation else {
        return;
    };

    if proc_gen != 1 && product_type != "iPod2,1" && proc_gen <= 10 {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::BlobRestore,
            title: "Other (Use SHSH Blobs)".to_string(),
            description: "Restore to another firmware using a matching saved SHSH blob."
                .to_string(),
            target_version: None,
            requires_blobs: true,
            requires_dfu: false,
        });

        if proc_gen < 7 {
            response.options.push(RestoreOption {
                kind: RestoreOptionKind::Tethered,
                title: "Other (Tethered)".to_string(),
                description: "Prepare a tethered downgrade path for pre-A7 devices.".to_string(),
                target_version: None,
                requires_blobs: true,
                requires_dfu: true,
            });
        }
    }

    if proc_gen < 5 {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::CustomIpsw,
            title: "Other (Custom IPSW)".to_string(),
            description: "Restore using a user-provided custom IPSW.".to_string(),
            target_version: None,
            requires_blobs: false,
            requires_dfu: true,
        });
    }
}

fn add_mode_options(response: &mut RestoreOptionsResponse) {
    let Some(proc_gen) = response.processor_generation else {
        return;
    };

    if proc_gen < 7 {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::DfuIpsw,
            title: "DFU IPSW".to_string(),
            description: "Create or use a DFU IPSW for low-level restore preparation.".to_string(),
            target_version: None,
            requires_blobs: false,
            requires_dfu: true,
        });
    } else if proc_gen <= 10 {
        response.options.push(RestoreOption {
            kind: RestoreOptionKind::SetNonce,
            title: "Set Nonce Only".to_string(),
            description: "Set the device nonce before a blob-based restore.".to_string(),
            target_version: None,
            requires_blobs: true,
            requires_dfu: true,
        });
    }
}

fn add_device_warnings(response: &mut RestoreOptionsResponse, product_type: &str) {
    match product_type {
        "iPad2,4" => response
            .warnings
            .push("iPad2,4 does not support 6.1.3 downgrades without blobs.".to_string()),
        "iPhone5,3" | "iPhone5,4" => response
            .warnings
            .push("iPhone 5C does not support 8.4.1 downgrades without blobs.".to_string()),
        "iPhone3,2" => response
            .warnings
            .push("iPhone3,2 does not support downgrades with powdersn0w.".to_string()),
        "iPod4,1" => response
            .warnings
            .push("iPod touch 4 does not support untethered downgrades without blobs.".to_string()),
        _ => {}
    }

    if std::env::consts::OS == "macos" {
        if let Some(proc_gen) = response.processor_generation {
            if proc_gen >= 7 {
                response.warnings.push(
                    "Restoring 64-bit devices to latest iOS is not supported on macOS; use Finder or iTunes for that path."
                        .to_string(),
                );
            }
        }
    }
}

fn version_option(
    kind: RestoreOptionKind,
    version: &str,
    description: &str,
    requires_blobs: bool,
    requires_dfu: bool,
) -> RestoreOption {
    RestoreOption {
        kind,
        title: version.to_string(),
        description: description.to_string(),
        target_version: Some(version.to_string()),
        requires_blobs,
        requires_dfu,
    }
}

fn ipsw_downloader_option() -> RestoreOption {
    RestoreOption {
        kind: RestoreOptionKind::IpswDownloader,
        title: "IPSW Downloader".to_string(),
        description: "Download an IPSW by build version before choosing a restore workflow."
            .to_string(),
        target_version: None,
        requires_blobs: false,
        requires_dfu: false,
    }
}

fn more_versions_option() -> RestoreOption {
    RestoreOption {
        kind: RestoreOptionKind::MoreVersions,
        title: "More versions".to_string(),
        description: "Additional legacy firmware choices from the original restore menu."
            .to_string(),
        target_version: None,
        requires_blobs: false,
        requires_dfu: false,
    }
}

fn can_use_powdersnow_blobs(product_type: &str) -> bool {
    product_family_in(product_type, "iPad2", 1..=7)
        || product_family_in(product_type, "iPad3", 1..=6)
        || matches_any(
            product_type,
            &[
                "iPhone4,1",
                "iPhone5,1",
                "iPhone5,2",
                "iPhone5,3",
                "iPhone5,4",
                "iPod5,1",
            ],
        )
}

fn infer_processor_generation(product_type: &str) -> Option<u8> {
    if matches_any(product_type, &["iPhone1,1", "iPhone1,2", "iPod1,1"]) {
        return Some(1);
    }
    if matches_any(product_type, &["iPhone2,1", "iPod2,1"]) {
        return Some(2);
    }
    if product_type == "iPod3,1" {
        return Some(3);
    }
    if product_family_in(product_type, "iPhone3", 1..=3)
        || product_type == "iPad1,1"
        || product_type == "iPod4,1"
    {
        return Some(4);
    }
    if product_type == "iPhone4,1"
        || product_family_in(product_type, "iPad2", 1..=7)
        || product_family_in(product_type, "iPad3", 1..=3)
        || product_type == "iPod5,1"
    {
        return Some(5);
    }
    if product_family_in(product_type, "iPhone5", 1..=4)
        || product_family_in(product_type, "iPad3", 4..=6)
    {
        return Some(6);
    }
    if product_family_in(product_type, "iPhone6", 1..=2)
        || product_family_in(product_type, "iPad4", 1..=9)
    {
        return Some(7);
    }
    if product_family_in(product_type, "iPhone7", 1..=2)
        || product_type == "iPod7,1"
        || product_family_in(product_type, "iPad5", 1..=4)
    {
        return Some(8);
    }
    if product_family_in(product_type, "iPhone8", 1..=4)
        || product_family_in(product_type, "iPad6", 3..=12)
    {
        return Some(9);
    }
    if product_family_in(product_type, "iPhone9", 1..=4)
        || product_family_in(product_type, "iPad7", 1..=4)
    {
        return Some(10);
    }
    None
}

fn matches_any(value: &str, candidates: &[&str]) -> bool {
    candidates.iter().any(|candidate| value == *candidate)
}

fn product_family_in(
    product_type: &str,
    family: &str,
    range: std::ops::RangeInclusive<u8>,
) -> bool {
    let Some(suffix) = product_type.strip_prefix(family) else {
        return false;
    };
    let Some(number) = suffix.strip_prefix(',') else {
        return false;
    };

    number
        .parse::<u8>()
        .map(|value| range.contains(&value))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::device::DeviceInfo;

    fn device(product_type: Option<&str>) -> DeviceInfo {
        DeviceInfo {
            connected: product_type.is_some(),
            product_type: product_type.map(str::to_string),
            ..Default::default()
        }
    }

    fn titles(response: &RestoreOptionsResponse) -> Vec<&str> {
        response
            .options
            .iter()
            .map(|option| option.title.as_str())
            .collect()
    }

    #[test]
    fn returns_downstream_safe_option_without_device() {
        let response = determine_restore_options(device(None));

        assert_eq!(response.options.len(), 1);
        assert_eq!(response.options[0].title, "IPSW Downloader");
        assert!(!response.warnings.is_empty());
    }

    #[test]
    fn iphone_4s_gets_ota_and_blob_paths() {
        let response = determine_restore_options(device(Some("iPhone4,1")));
        let titles = titles(&response);

        assert_eq!(response.processor_generation, Some(5));
        assert!(titles.contains(&"iOS 8.4.1"));
        assert!(titles.contains(&"iOS 6.1.3"));
        assert!(titles.contains(&"Other (Use SHSH Blobs)"));
        assert!(titles.contains(&"Other (Tethered)"));
        assert!(titles.contains(&"IPSW Downloader"));
    }

    #[test]
    fn iphone_5s_gets_1033_and_nonce_paths() {
        let response = determine_restore_options(device(Some("iPhone6,1")));
        let titles = titles(&response);

        assert_eq!(response.processor_generation, Some(7));
        assert!(titles.contains(&"iOS 10.3.3"));
        assert!(titles.contains(&"Other (Use SHSH Blobs)"));
        assert!(titles.contains(&"Set Nonce Only"));
    }
}
