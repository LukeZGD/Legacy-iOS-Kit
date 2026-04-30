use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveShshRequest {
    pub device_type: String,
    pub device_ecid: String,
    pub board_config: Option<String>,
    pub ios_version: String,
    pub build_id: Option<String>,
    pub build_manifest_path: Option<String>,
    pub apnonce: Option<String>,
    pub generator: Option<String>,
    pub output_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveShshResult {
    pub blob_paths: Vec<String>,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CydiaBlobRequest {
    pub device_type: String,
    pub device_ecid: String,
    pub build_ids: Vec<String>,
    pub output_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CydiaBlobAttempt {
    pub build_id: String,
    pub saved: bool,
    pub blob_path: Option<String>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CydiaBlobResult {
    pub attempts: Vec<CydiaBlobAttempt>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DumpOnboardBlobRequest {
    pub raw_dump_path: String,
    pub output_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DumpOnboardBlobResult {
    pub blob_path: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListBlobsRequest {
    pub directory: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedBlob {
    pub path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_unix: Option<u64>,
    pub device_type: Option<String>,
    pub device_ecid: Option<String>,
    pub ios_version: Option<String>,
    pub build_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListBlobsResult {
    pub directory: String,
    pub blobs: Vec<SavedBlob>,
}
