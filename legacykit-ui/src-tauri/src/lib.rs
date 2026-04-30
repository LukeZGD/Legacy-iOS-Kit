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
            commands::restore::prepare_ipsw,
            commands::restore::preview_restore_command,
            commands::restore::start_restore,
            commands::jailbreak::run_gaster,
            commands::jailbreak::run_kloader,
            commands::jailbreak::run_g1lbertjb,
            commands::jailbreak::run_evasi0n,
            commands::firmware::extract_ipsw_component,
            commands::firmware::patch_iboot,
            commands::firmware::pack_img4,
            commands::firmware::repack_img3,
            commands::firmware::patch_kernel,
            commands::firmware::modify_ramdisk,
            commands::shsh::save_shsh_blob,
            commands::shsh::fetch_cydia_blobs,
            commands::shsh::dump_onboard_blob,
            commands::shsh::list_saved_blobs,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
