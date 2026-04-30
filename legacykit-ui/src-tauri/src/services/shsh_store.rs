use crate::error::AppError;
use crate::models::shsh::SavedBlob;
use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

pub fn list_saved_blobs(directory: &str) -> Result<Vec<SavedBlob>, AppError> {
    let dir = Path::new(directory);
    if !dir.exists() {
        return Ok(Vec::new());
    }
    if !dir.is_dir() {
        return Err(AppError::Parse(format!(
            "{} is not a directory",
            dir.display()
        )));
    }

    let mut blobs = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let file_name = match path.file_name().and_then(|n| n.to_str()) {
            Some(name) => name.to_string(),
            None => continue,
        };
        if !is_blob_file(&file_name) {
            continue;
        }

        let metadata = entry.metadata()?;
        let modified_unix = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs());

        let parsed = parse_blob_filename(&file_name);
        blobs.push(SavedBlob {
            path: path.to_string_lossy().to_string(),
            file_name,
            size_bytes: metadata.len(),
            modified_unix,
            device_type: parsed.device_type,
            device_ecid: parsed.device_ecid,
            ios_version: parsed.ios_version,
            build_id: parsed.build_id,
        });
    }

    blobs.sort_by_key(|b| std::cmp::Reverse(b.modified_unix));
    Ok(blobs)
}

fn is_blob_file(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.ends_with(".shsh") || lower.ends_with(".shsh2")
}

#[derive(Debug, Default)]
struct ParsedBlob {
    device_type: Option<String>,
    device_ecid: Option<String>,
    ios_version: Option<String>,
    build_id: Option<String>,
}

/// Best-effort parse of common blob filename shapes:
/// - `<ecid>_<deviceType>_<board>ap_<version>-<build>_<apnonce?>...shsh*`
/// - `<ecid>-<deviceType>-<version>.shsh*`
/// - `<ecid>-<deviceType>-<build>.shsh*`
fn parse_blob_filename(name: &str) -> ParsedBlob {
    let stem = name
        .strip_suffix(".shsh2")
        .or_else(|| name.strip_suffix(".shsh"))
        .unwrap_or(name);

    if let Some(parsed) = parse_underscore_form(stem) {
        return parsed;
    }
    if let Some(parsed) = parse_dash_form(stem) {
        return parsed;
    }
    ParsedBlob::default()
}

fn parse_underscore_form(stem: &str) -> Option<ParsedBlob> {
    let parts: Vec<&str> = stem.split('_').collect();
    if parts.len() < 4 {
        return None;
    }
    let ecid = parts[0];
    let device_type = parts[1];
    if !device_type.starts_with("iPhone")
        && !device_type.starts_with("iPad")
        && !device_type.starts_with("iPod")
    {
        return None;
    }
    let version_build = parts[3];
    let (version, build) = match version_build.split_once('-') {
        Some((v, b)) => (Some(v.to_string()), Some(b.to_string())),
        None => (Some(version_build.to_string()), None),
    };
    Some(ParsedBlob {
        device_type: Some(device_type.to_string()),
        device_ecid: Some(ecid.to_string()),
        ios_version: version,
        build_id: build,
    })
}

fn parse_dash_form(stem: &str) -> Option<ParsedBlob> {
    let parts: Vec<&str> = stem.splitn(3, '-').collect();
    if parts.len() < 3 {
        return None;
    }
    let ecid = parts[0];
    let device_type = parts[1];
    if !device_type.starts_with("iPhone")
        && !device_type.starts_with("iPad")
        && !device_type.starts_with("iPod")
    {
        return None;
    }
    let tail = parts[2];
    let (version, build) = if looks_like_build_id(tail) {
        (None, Some(tail.to_string()))
    } else {
        (Some(tail.to_string()), None)
    };
    Some(ParsedBlob {
        device_type: Some(device_type.to_string()),
        device_ecid: Some(ecid.to_string()),
        ios_version: version,
        build_id: build,
    })
}

fn looks_like_build_id(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 4 || bytes.len() > 7 {
        return false;
    }
    bytes.iter().all(|b| b.is_ascii_alphanumeric())
        && bytes.iter().any(|b| b.is_ascii_alphabetic())
        && bytes.iter().any(|b| b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_tsschecker_underscore_form() {
        let parsed = parse_blob_filename(
            "1234567890_iPhone6,2_n53ap_10.3.3-14G60_0x1111111111111111.shsh2",
        );
        assert_eq!(parsed.device_type.as_deref(), Some("iPhone6,2"));
        assert_eq!(parsed.device_ecid.as_deref(), Some("1234567890"));
        assert_eq!(parsed.ios_version.as_deref(), Some("10.3.3"));
        assert_eq!(parsed.build_id.as_deref(), Some("14G60"));
    }

    #[test]
    fn parses_dash_form_with_version() {
        let parsed = parse_blob_filename("1234567890-iPhone6,2-10.3.3.shsh");
        assert_eq!(parsed.device_type.as_deref(), Some("iPhone6,2"));
        assert_eq!(parsed.ios_version.as_deref(), Some("10.3.3"));
        assert_eq!(parsed.build_id, None);
    }

    #[test]
    fn parses_dash_form_with_build() {
        let parsed = parse_blob_filename("1234567890-iPhone6,2-14G60.shsh");
        assert_eq!(parsed.device_type.as_deref(), Some("iPhone6,2"));
        assert_eq!(parsed.build_id.as_deref(), Some("14G60"));
        assert_eq!(parsed.ios_version, None);
    }

    #[test]
    fn rejects_non_blob_files() {
        assert!(!is_blob_file("foo.txt"));
        assert!(is_blob_file("foo.shsh"));
        assert!(is_blob_file("FOO.SHSH2"));
    }
}
