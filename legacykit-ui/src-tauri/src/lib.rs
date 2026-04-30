pub mod platform;
pub mod tools;
pub mod error;
pub mod models;
pub mod commands;
pub mod services;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::new().build())
        .invoke_handler(tauri::generate_handler![
            tools::runner::execute_tool,
            tools::runner::execute_idevice_info,
            tools::runner::execute_irecovery,
            commands::device::detect_device,
            commands::restore::get_restore_options,
            commands::restore::download_ipsw,
            commands::restore::verify_ipsw,
            commands::restore::preview_restore_command,
            commands::restore::start_restore,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
