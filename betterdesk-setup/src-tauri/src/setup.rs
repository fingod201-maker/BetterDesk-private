use anyhow::{anyhow, Result};
use log::{info, warn};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Everything the UI needs to render the setup screen.
#[derive(Debug, Clone, Serialize)]
pub struct DetectInfo {
    pub platform: String,
    pub arch: String,
    pub os_label: String,
    pub default_console: String,
    pub install_dir: String,
    pub config_dir: String,
    pub client_path: String,
    pub already_installed: bool,
}

/// Asset metadata returned by the console landing API.
#[derive(Debug, Clone, Deserialize)]
struct LandingResponse {
    #[serde(default)]
    data: LandingData,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct LandingData {
    #[serde(default)]
    recommended: Option<RecommendedAsset>,
    #[serde(default)]
    available: Vec<RecommendedAsset>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct RecommendedAsset {
    pub name: String,
    #[serde(default)]
    pub size: u64,
    pub platform: String,
    pub arch: String,
    pub format: String,
    #[serde(rename = "downloadPath", default)]
    pub download_path: String,
    #[serde(default)]
    pub sha256: Option<String>,
}

fn home_dir() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

/// Per-OS install layout (user level — no administrator rights required).
pub fn install_paths() -> (PathBuf, PathBuf, PathBuf) {
    if cfg!(windows) {
        let local = std::env::var("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|_| home_dir().join("AppData").join("Local"));
        let install = local.join("Programs").join("zoom-private");
        let config = local.join("zoom-private").join("agent");
        let client = install.join("zoom-private.agent.exe");
        (install, config, client)
    } else if cfg!(target_os = "macos") {
        let install = home_dir().join("Applications");
        let config = home_dir()
            .join("Library")
            .join("Application Support")
            .join("zoom-private")
            .join("agent");
        let client = install.join("zoom-private.agent.app");
        (install, config, client)
    } else {
        let install = home_dir().join(".local").join("share").join("zoom-private");
        let config = home_dir().join(".config").join("zoom-private").join("agent");
        let client = install.join("zoom-private.agent");
        (install, config, client)
    }
}

pub fn platform_key() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "linux"
    }
}

pub fn arch_key() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "x64"
    }
}

pub fn os_label() -> &'static str {
    if cfg!(windows) {
        "Windows"
    } else if cfg!(target_os = "macos") {
        "macOS"
    } else {
        "Linux"
    }
}

/// Normalise the console address into an origin (scheme://host[:port]).
pub fn normalize_console(input: &str) -> Result<String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("Console address is empty"));
    }
    let with_scheme = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("https://{}", trimmed)
    };
    let parsed = url::Url::parse(&with_scheme).map_err(|e| anyhow!("Invalid address: {}", e))?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        return Err(anyhow!("Only http:// and https:// are supported"));
    }
    if parsed.host_str().is_none() {
        return Err(anyhow!("Address must include a host"));
    }
    let host = parsed.host_str().unwrap_or("");
    let host = if host.contains(':') && !host.starts_with('[') {
        format!("[{}]", host)
    } else {
        host.to_string()
    };
    let port = match parsed.port() {
        Some(p) => format!(":{}", p),
        None => String::new(),
    };
    Ok(format!("{}://{}{}", parsed.scheme(), host, port))
}

/// Connection profile the console publishes for freshly installed clients.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct AgentProfile {
    #[serde(default)]
    pub server_address: String,
    #[serde(default)]
    pub api_url: String,
    #[serde(default)]
    pub cdap_url: String,
    #[serde(default)]
    pub cdap_port: u16,
    #[serde(default)]
    pub console_url: String,
    #[serde(default)]
    pub server_key: String,
}

/// Fetch the agent connection profile (API origin, CDAP URL, console URL).
pub async fn fetch_agent_profile(
    client: &reqwest::Client,
    console: &str,
) -> Result<AgentProfile> {
    let url = format!("{}/api/landing/agent-profile", console);
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| anyhow!("Cannot reach the console at {}: {}", console, e))?;
    if !resp.status().is_success() {
        return Err(anyhow!("Console returned {} for {}", resp.status(), url));
    }
    let parsed: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| anyhow!("Console returned an unexpected payload: {}", e))?;
    let data = parsed.get("data").cloned().unwrap_or_default();
    Ok(serde_json::from_value::<AgentProfile>(data).unwrap_or_default())
}

pub async fn fetch_recommended(
    client: &reqwest::Client,
    console: &str,
    platform: &str,
    arch: &str,
) -> Result<RecommendedAsset> {
    let url = format!(
        "{}/api/landing/client?platform={}&arch={}",
        console, platform, arch
    );
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| anyhow!("Cannot reach the console at {}: {}", console, e))?;
    if !resp.status().is_success() {
        return Err(anyhow!("Console returned {} for {}", resp.status(), url));
    }
    let parsed: LandingResponse = resp
        .json()
        .await
        .map_err(|e| anyhow!("Console returned an unexpected payload: {}", e))?;

    // Prefer the portable zip bundle for this platform.
    let mut candidates: Vec<RecommendedAsset> = parsed.data.available.clone();
    if let Some(rec) = parsed.data.recommended.clone() {
        candidates.insert(0, rec);
    }
    let pick = candidates
        .iter()
        .find(|a| a.format == "zip" && a.platform == platform)
        .or_else(|| candidates.iter().find(|a| a.platform == platform))
        .cloned()
        .ok_or_else(|| anyhow!("No client build published for {}", platform))?;

    if pick.download_path.is_empty() {
        return Err(anyhow!("Console did not return a download path for {}", pick.name));
    }
    Ok(pick)
}

pub async fn download_bundle(
    client: &reqwest::Client,
    console: &str,
    asset: &RecommendedAsset,
) -> Result<Vec<u8>> {
    let url = format!("{}{}", console, asset.download_path);
    info!("downloading {}", url);
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| anyhow!("Download failed: {}", e))?;
    if !resp.status().is_success() {
        return Err(anyhow!("Download failed with {}", resp.status()));
    }
    let bytes = resp
        .bytes()
        .await
        .map_err(|e| anyhow!("Download interrupted: {}", e))?;
    Ok(bytes.to_vec())
}

pub fn verify_sha256(bytes: &[u8], expected: &str) -> Result<()> {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let actual = digest.iter().map(|b| format!("{:02x}", b)).collect::<String>();
    if !actual.eq_ignore_ascii_case(expected.trim()) {
        return Err(anyhow!(
            "Checksum mismatch — expected {}, got {}. Refusing to install.",
            expected,
            actual
        ));
    }
    Ok(())
}

/// Extract the zip and return the directory that holds the payload root.
pub fn extract_bundle(bytes: &[u8], dest: &Path) -> Result<PathBuf> {
    std::fs::create_dir_all(dest)?;
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(bytes))
        .map_err(|e| anyhow!("Bundle is not a valid zip: {}", e))?;
    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| anyhow!("Cannot read bundle entry: {}", e))?;
        let Some(relative) = file.enclosed_name() else {
            continue; // zip-slip protection
        };
        let out_path = dest.join(&relative);
        if file.is_dir() {
            std::fs::create_dir_all(&out_path)?;
            continue;
        }
        if let Some(parent) = out_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut out = std::fs::File::create(&out_path)?;

        std::io::copy(&mut file, &mut out)?;
    }
    Ok(dest.to_path_buf())
}

/// The bundle contains a single top-level folder — find it.
pub fn payload_root(extracted: &Path) -> PathBuf {
    let mut entries: Vec<_> = std::fs::read_dir(extracted)
        .map(|rd| rd.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    entries.sort();
    for entry in entries {
        if entry.is_dir() {
            return entry;
        }
    }
    extracted.to_path_buf()
}

/// Run the bundled installer script, streaming its output to `on_log`.
pub async fn run_installer(
    root: &Path,
    console: &str,
    install_dir: &Path,
    config_dir: &Path,
    on_log: &(dyn Fn(String) + Send + Sync),
) -> Result<()> {
    if cfg!(windows) {
        let script = root.join("install.ps1");
        if !script.exists() {
            return Err(anyhow!("install.ps1 missing from the bundle"));
        }
        let mut cmd = Command::new("powershell.exe");
        cmd.arg("-NoProfile")
            .arg("-ExecutionPolicy")
            .arg("Bypass")
            .arg("-File")
            .arg(&script)
            .arg("-ServerAddress")
            .arg(console)
            .arg("-InstallDir")
            .arg(install_dir)
            .arg("-ConfigDir")
            .arg(config_dir)
            .arg("-NoLaunch");
        run_streaming(cmd, on_log).await?;
    } else {
        let script = root.join("install.sh");
        if !script.exists() {
            return Err(anyhow!("install.sh missing from the bundle"));
        }
        let mut cmd = Command::new("bash");
        cmd.arg(&script).arg(console);
        cmd.env("BETTERDESK_INSTALL_DIR", install_dir);
        cmd.env("BETTERDESK_CONFIG_DIR", config_dir);
        run_streaming(cmd, on_log).await?;
    }
    Ok(())
}

/// Spawn a command and forward its stdout/stderr to the callback.
async fn run_streaming(mut cmd: Command, on_log: &(dyn Fn(String) + Send + Sync)) -> Result<()> {
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd
        .spawn()
        .map_err(|e| anyhow!("Cannot start the installer: {}", e))?;

    if let Some(stdout) = child.stdout.take() {
        let mut reader = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = reader.next_line().await {
            if !line.trim().is_empty() {
                on_log(line);
            }
        }
    }
    if let Some(stderr) = child.stderr.take() {
        let mut reader = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = reader.next_line().await {
            if !line.trim().is_empty() {
                on_log(line);
            }
        }
    }

    let status = child
        .wait()
        .await
        .map_err(|e| anyhow!("Installer did not finish: {}", e))?;
    if !status.success() {
        return Err(anyhow!("Installer exited with {}", status));
    }
    Ok(())
}

/// Merge the connection profile into the installed agent config.
pub fn apply_profile(config_path: &Path, profile: &AgentProfile) -> Result<()> {
    if !config_path.exists() {
        return Err(anyhow!(
            "Agent config missing at {} — the installer did not run",
            config_path.display()
        ));
    }
    let raw = std::fs::read_to_string(config_path)?;
    // Windows PowerShell writes UTF-8 with a BOM — strip it before parsing.
    let raw = raw.trim_start_matches('\u{feff}');
    let mut value: serde_json::Value = serde_json::from_str(raw)
        .map_err(|e| anyhow!("Agent config is not valid JSON: {}", e))?;
    if !value.is_object() {
        value = serde_json::json!({});
    }
    let obj = value.as_object_mut().unwrap();

    if !profile.server_address.trim().is_empty() {
        obj.insert(
            "server_address".to_string(),
            serde_json::Value::String(profile.server_address.trim().to_string()),
        );
    }
    if !profile.cdap_url.trim().is_empty() {
        obj.insert(
            "cdap_url".to_string(),
            serde_json::Value::String(profile.cdap_url.trim().to_string()),
        );
    }
    if !profile.console_url.trim().is_empty() {
        obj.insert(
            "console_url".to_string(),
            serde_json::Value::String(profile.console_url.trim().to_string()),
        );
    }
    if !profile.server_key.trim().is_empty() {
        obj.insert(
            "server_key".to_string(),
            serde_json::Value::String(profile.server_key.trim().to_string()),
        );
    }

    std::fs::write(config_path, serde_json::to_string_pretty(&value)?)?;
    Ok(())
}

/// Start the installed client.
pub fn launch_client(client_path: &Path) -> Result<()> {
    if cfg!(target_os = "macos") {
        let mut cmd = Command::new("open");
        cmd.arg("-a").arg(client_path);
        cmd.stdout(Stdio::null()).stderr(Stdio::null());
        let _ = cmd.spawn();
        return Ok(());
    }
    let mut cmd = Command::new(client_path);
    cmd.current_dir(
        client_path
            .parent()
            .unwrap_or_else(|| Path::new(".")),
    );
    cmd.stdout(Stdio::null()).stderr(Stdio::null());
    cmd.spawn()
        .map_err(|e| anyhow!("Cannot start the client: {}", e))?;
    Ok(())
}

/// Open a URL in the default browser.
pub fn open_url(url: &str) -> Result<()> {
    if cfg!(windows) {
        Command::new("cmd")
            .args(["/C", "start", "", url])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| anyhow!("Cannot open the browser: {}", e))?;
    } else if cfg!(target_os = "macos") {
        Command::new("open")
            .arg(url)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| anyhow!("Cannot open the browser: {}", e))?;
    } else {
        Command::new("xdg-open")
            .arg(url)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| anyhow!("Cannot open the browser: {}", e))?;
    }
    Ok(())
}

