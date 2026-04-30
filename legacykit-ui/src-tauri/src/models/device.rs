use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub enum DeviceMode {
    #[default]
    Normal,
    Recovery,
    DFU,
    #[serde(rename = "kDFU")]
    KDFU,
    #[serde(rename = "pwnDFU")]
    PwnDFU,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DeviceInfo {
    pub connected: bool,
    pub name: Option<String>,
    pub udid: Option<String>,
    pub ecid: Option<String>,
    pub serial: Option<String>,
    pub model: Option<String>,
    pub product_type: Option<String>,
    pub ios_version: Option<String>,
    pub mode: DeviceMode,
}
