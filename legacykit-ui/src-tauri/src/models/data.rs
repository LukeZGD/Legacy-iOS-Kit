use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupCreateRequest {
    pub backup_root: String,
    pub udid: Option<String>,
    pub full: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupCreateResult {
    pub backup_path: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRestoreRequest {
    pub backup_path: String,
    pub udid: Option<String>,
    pub system: bool,
    pub settings: bool,
    pub reboot: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRestoreResult {
    pub backup_path: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EraseDeviceRequest {
    pub udid: Option<String>,
    pub confirmation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EraseDeviceResult {
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BackupEncryptionAction {
    On,
    Off,
    ChangePassword,
}

impl BackupEncryptionAction {
    pub fn as_args(&self) -> Vec<String> {
        match self {
            BackupEncryptionAction::On => vec!["encryption".into(), "on".into()],
            BackupEncryptionAction::Off => vec!["encryption".into(), "off".into()],
            BackupEncryptionAction::ChangePassword => vec!["changepw".into()],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupEncryptionRequest {
    pub action: BackupEncryptionAction,
    pub udid: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupEncryptionResult {
    pub action: BackupEncryptionAction,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListBackupsRequest {
    pub backup_root: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupEntry {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    pub modified_unix: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListBackupsResult {
    pub backup_root: String,
    pub backups: Vec<BackupEntry>,
}
