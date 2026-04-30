use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RestoreOptionKind {
    OtaDowngrade,
    Powdersnow,
    Latest,
    BlobRestore,
    Tethered,
    CustomIpsw,
    DfuIpsw,
    SetNonce,
    IpswDownloader,
    MoreVersions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreOption {
    pub kind: RestoreOptionKind,
    pub title: String,
    pub description: String,
    pub target_version: Option<String>,
    pub requires_blobs: bool,
    pub requires_dfu: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreOptionsResponse {
    pub product_type: Option<String>,
    pub processor_generation: Option<u8>,
    pub options: Vec<RestoreOption>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswDownloadRequest {
    pub url: String,
    pub output_dir: String,
    pub file_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswDownloadResult {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswVerifyRequest {
    pub path: String,
    pub expected_sha1: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpswVerifyResult {
    pub path: String,
    pub calculated_sha1: String,
    pub expected_sha1: Option<String>,
    pub matches: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RestoreTool {
    IdeviceRestore,
    FutureRestore,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreRunRequest {
    pub tool: RestoreTool,
    pub ipsw_path: String,
    pub shsh_path: Option<String>,
    pub erase: bool,
    pub update: bool,
    pub use_pwndfu: bool,
    pub skip_blob: bool,
    pub set_nonce: bool,
    pub no_baseband: bool,
    pub latest_sep: bool,
    pub latest_baseband: bool,
    pub dry_run: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreCommandPreview {
    pub supported: bool,
    pub tool: RestoreTool,
    pub binary: String,
    pub args: Vec<String>,
    pub warnings: Vec<String>,
}
