use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader};
use tauri::{AppHandle, Emitter};
use crate::platform::resolve_binary_path;
use std::thread;

#[tauri::command]
pub async fn execute_tool(
    app: AppHandle,
    binary_name: String,
    args: Vec<String>,
    event_name: String,
) -> Result<(), String> {
    let bin_path = resolve_binary_path(&app, &binary_name)?;

    let mut child = Command::new(bin_path)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn child process: {}", e))?;

    let stdout = child.stdout.take().expect("Failed to grab stdout");
    let stderr = child.stderr.take().expect("Failed to grab stderr");

    let app_clone1 = app.clone();
    let event_name_clone1 = event_name.clone();
    
    // Spawn thread for stdout
    thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            if let Ok(l) = line {
                let _ = app_clone1.emit(&event_name_clone1, l);
            }
        }
    });

    let app_clone2 = app.clone();
    let event_name_clone2 = event_name.clone();

    // Spawn thread for stderr
    thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            if let Ok(l) = line {
                let _ = app_clone2.emit(&event_name_clone2, l);
            }
        }
    });

    // Wait for the process to finish
    thread::spawn(move || {
        let _ = child.wait();
        let _ = app.emit(&format!("{}_finished", event_name), "Process finished");
    });

    Ok(())
}

#[tauri::command]
pub async fn execute_idevice_info(
    app: AppHandle,
    args: Vec<String>,
    event_name: String,
) -> Result<(), String> {
    execute_tool(app, "ideviceinfo".to_string(), args, event_name).await
}

#[tauri::command]
pub async fn execute_irecovery(
    app: AppHandle,
    args: Vec<String>,
    event_name: String,
) -> Result<(), String> {
    execute_tool(app, "irecovery".to_string(), args, event_name).await
}
