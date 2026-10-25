use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::STANDARD as B64_STD, Engine as _};
use chrono::{SecondsFormat, Utc};
use ed25519_dalek::{Signer, SigningKey};
use log::{info, warn};
use rand::RngCore;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;
use url::Url;

use crate::config::AgentConfig;
use crate::sysinfo_collect::SystemSnapshot;

const DEFAULT_API_PORT: u16 = 21114;
const LEGACY_API_PORT: u16 = 21120;
const DISCOVERY_PORT: u16 = 21119;
const DISCOVERY_RECV_BUF_SIZE: usize = 4096;

// ---------------------------------------------------------------------------
// Device identity key + enrollment proof (bd-enrollment-v1)
// ---------------------------------------------------------------------------

/// Per-machine Ed25519 signing identity. BetterDesk Go servers (3.5.156+)
/// require a signed proof of possession of the enrolled public key before
/// they will mint a CDAP device token. The key is generated once and persisted
/// next to agent-config.json so reinstalls keep the same bound identity.
#[derive(Serialize, Deserialize)]
struct DeviceIdentity {
    private_key_b64: String,
    public_key_b64: String,
}

fn device_identity_path() -> Result<PathBuf> {
    // Keep the identity next to agent-config.json so portable deployments
    // (BETTERDESK_AGENT_CONFIG_DIR) keep a stable, bound key.
    let dir = crate::config::AgentConfig::agent_config_dir();
    std::fs::create_dir_all(&dir)?;
    Ok(dir.join("device-identity.json"))
}

fn load_or_create_identity() -> Result<(SigningKey, String)> {
    let path = device_identity_path()?;
    if path.exists() {
        if let Ok(raw) = std::fs::read_to_string(&path) {
            if let Ok(stored) = serde_json::from_str::<DeviceIdentity>(&raw) {
                if let Ok(decoded) = B64_STD.decode(&stored.private_key_b64) {
                    if let Ok(bytes) = <&[u8; 32]>::try_from(decoded.as_slice()) {
                        let key = SigningKey::from_bytes(bytes);
                        let public_b64 = B64_STD.encode(key.verifying_key().as_bytes());
                        if public_b64 == stored.public_key_b64 {
                            return Ok((key, public_b64));
                        }
                    }
                }
            }
        }
        warn!("device identity file corrupt or tampered - regenerating");
    }

    let mut seed = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut seed);
    let key = SigningKey::from_bytes(&seed);
    let public_b64 = B64_STD.encode(key.verifying_key().as_bytes());
    let identity = DeviceIdentity {
        private_key_b64: B64_STD.encode(key.to_bytes()),
        public_key_b64: public_b64.clone(),
    };
    std::fs::write(&path, serde_json::to_string_pretty(&identity)?)?;
    Ok((key, public_b64))
}

/// Bundle identifier declared for this installation (bundled branding via env
/// override, or the well-known default). The Go server requires it for
/// support-agent (`os_agent`) enrollment.
fn enrollment_bundle_id() -> String {
    if let Ok(path) = std::env::var("BETTERDESK_AGENT_BRANDING") {
        if let Ok(raw) = std::fs::read_to_string(&path) {
            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&raw) {
                if let Some(id) = value.get("bundle_id").and_then(|b| b.as_str()) {
                    let id = id.trim();
                    if !id.is_empty() {
                        return id.to_string();
                    }
                }
            }
        }
    }
    String::from("com.betterdesk.agent")
}

/// Build the `X-BD-Enrollment-*` proof-of-possession headers the Go server
/// validates via `verifyEnrollmentDeviceProof`:
///   Ed25519 over `bd-enrollment-v1\n{method}\n{path}\n{device_id}\n{public_key}\n{timestamp}\n{nonce}`
/// where `path` is the raw request path as seen by the server and `timestamp`
/// is RFC3339 UTC (±5 min skew enforced server-side, nonce replay-protected).
fn enrollment_proof_headers(
    method: &str,
    path: &str,
    device_id: &str,
    public_key_b64: &str,
    key: &SigningKey,
) -> [(&'static str, String); 3] {
    let timestamp = Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true);
    let nonce = uuid::Uuid::new_v4().simple().to_string();
    let payload = format!(
        "bd-enrollment-v1\n{}\n{}\n{}\n{}\n{}\n{}",
        method, path, device_id, public_key_b64, timestamp, nonce
    );
    let signature = B64_STD.encode(key.sign(payload.as_bytes()).to_bytes());
    [
        ("X-BD-Enrollment-Timestamp", timestamp),
        ("X-BD-Enrollment-Nonce", nonce),
        ("X-BD-Enrollment-Signature", signature),
    ]
}

#[derive(Debug, Clone)]
struct ResolvedApiEndpoint {
    scheme: String,
    host: String,
    port: u16,
}

impl ResolvedApiEndpoint {
    fn base_url(&self) -> String {
        let host_part = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        format!("{}://{}:{}/api", self.scheme, host_part, self.port)
    }

    fn origin(&self) -> String {
        let host_part = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        format!("{}://{}:{}", self.scheme, host_part, self.port)
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DiscoveredLanServer {
    pub name: String,
    pub version: String,
    pub address: String,
    pub port: u16,
    pub api_port: u16,
    pub protocol: String,
    pub console_url: String,
}

#[derive(Debug, Deserialize)]
struct DiscoveryAnnounceResponse {
    #[serde(rename = "type")]
    msg_type: String,
    #[allow(dead_code)]
    #[serde(default)]
    version: u32,
    server: DiscoveryServerInfo,
}

#[derive(Debug, Deserialize)]
struct DiscoveryServerInfo {
    name: String,
    #[serde(default)]
    version: String,
    #[serde(default)]
    port: u16,
    #[serde(rename = "apiPort", default)]
    api_port: u16,
    #[serde(default)]
    protocol: String,
}

/// Build a reqwest client honouring the BETTERDESK_STRICT_TLS gate.
pub(crate) fn build_http_client(timeout_secs: u64) -> Result<Client> {
    crate::tls::build_http_client(timeout_secs).map_err(Into::into)
}

/// Build a reqwest client with automatic redirect following DISABLED.
pub(crate) fn build_http_client_no_redirect(timeout_secs: u64) -> Result<Client> {
    crate::tls::build_http_client_no_redirect(timeout_secs).map_err(Into::into)
}

/// Result of a single validation step.
#[derive(Debug, Clone, Serialize)]
pub struct ValidationResult {
    pub step: String,
    pub success: bool,
    pub message: String,
}

/// Registration response from the server.
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct RegisterResponse {
    #[serde(default)]
    device_id: String,
    #[serde(default)]
    token: String,
}

#[derive(Debug, Deserialize)]
struct EnrollmentResponse {
    status: String,
    #[serde(default)]
    device_id: String,
    #[serde(default)]
    device_token: String,
    #[serde(default)]
    message: String,
}

/// Sync response from the server.
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct SyncResponse {
    #[serde(default)]
    status: String,
}

fn parse_user_address(address: &str) -> Result<(Option<String>, String, Option<u16>)> {
    let addr = address.trim();
    let with_scheme = if addr.contains("://") {
        addr.to_string()
    } else {
        format!("http://{}", addr)
    };

    let parsed = Url::parse(&with_scheme)
        .map_err(|e| anyhow!("Invalid URL: {}", e))?;

    let host = parsed.host_str().ok_or_else(|| anyhow!("No host in URL"))?;
    let scheme = if addr.contains("://") {
        Some(parsed.scheme().to_string())
    } else {
        None
    };

    Ok((scheme, host.to_string(), parsed.port()))
}

fn build_api_probe_url(host: &str, port: u16, scheme: &str) -> String {
    let host_part = if host.contains(':') {
        format!("[{}]", host)
    } else {
        host.to_string()
    };
    format!("{}://{}:{}/api/server/stats", scheme, host_part, port)
}

fn build_register_status_probe_url(host: &str, port: u16, scheme: &str) -> String {
    let host_part = if host.contains(':') {
        format!("[{}]", host)
    } else {
        host.to_string()
    };
    format!(
        "{}://{}:{}/api/devices/register/status?device_id=BD-PROBE",
        scheme, host_part, port
    )
}

fn candidate_schemes(explicit_scheme: Option<&str>) -> Vec<&'static str> {
    match explicit_scheme {
        Some("https") => vec!["https", "http"],
        Some("http") => vec!["http", "https"],
        _ => vec!["https", "http"],
    }
}

/// Port candidates for a scheme.
///
/// An address without an explicit port must be tried on the scheme's default
/// port first: a Cloudflare Tunnel / reverse proxy exposes the BetterDesk API
/// on 443 (https) or 80 (http), and the raw 21114 port is not reachable from
/// the internet. The well-known API ports are tried afterwards for LAN
/// deployments that expose them directly.
fn candidate_ports_for(scheme: &str, input_port: Option<u16>) -> Vec<u16> {
    let mut ports = Vec::new();

    if let Some(port) = input_port {
        ports.push(port);
    } else {
        ports.push(if scheme == "https" { 443 } else { 80 });
    }

    ports.push(DEFAULT_API_PORT);
    ports.push(LEGACY_API_PORT);

    ports.dedup();
    ports
}

async fn try_resolve_api_endpoint(address: &str) -> Result<ResolvedApiEndpoint> {
    let (explicit_scheme, host, input_port) = parse_user_address(address)?;

    for scheme in candidate_schemes(explicit_scheme.as_deref()) {
        for port in candidate_ports_for(scheme, input_port) {
            let client = build_http_client(4)?;
            let stats_url = build_api_probe_url(&host, port, scheme);
            let stats_resp = match client.get(&stats_url).send().await {
                Ok(resp) => resp,
                Err(_) => continue,
            };

            // The Go API protects /api/server/stats with an API key on newer
            // servers (401). An unauthorized JSON answer still proves that a
            // BetterDesk Go API is listening, so only a non-JSON answer (or a
            // hard error) disqualifies the candidate.
            let stats_status = stats_resp.status();
            let stats_body: serde_json::Value = match stats_resp.json().await {
                Ok(body) => body,
                Err(_) => continue,
            };

            let looks_like_go_api = (stats_status.is_success()
                && (stats_body.get("peers_count").is_some() || stats_body.get("version").is_some()))
                || stats_status.as_u16() == 401
                || stats_status.as_u16() == 403;

            if !looks_like_go_api {
                continue;
            }

            // Distinguish the real Go API from the web console reverse/proxy layer.
            // The panel may expose /api/server/stats, but only the Go API serves the
            // public enrollment status endpoint with JSON. That endpoint answers
            // 404 with a JSON body for an unknown device, so the status code is
            // not checked here — only the payload shape.
            let register_status_url = build_register_status_probe_url(&host, port, scheme);
            let register_status_resp = match client.get(&register_status_url).send().await {
                Ok(resp) => resp,
                Err(_) => continue,
            };

            let register_status_body: serde_json::Value = match register_status_resp.json().await {
                Ok(body) => body,
                Err(_) => continue,
            };

            if register_status_body.get("status").is_some()
                && register_status_body.get("device_id").is_some()
            {
                info!(
                    "Resolved BetterDesk Go API endpoint: {}://{}:{}",
                    scheme, host, port
                );
                return Ok(ResolvedApiEndpoint {
                    scheme: scheme.to_string(),
                    host: host.clone(),
                    port,
                });
            }
        }
    }

    Err(anyhow!(
        "Could not find BetterDesk Go API for {}. Use the server host or select a discovered LAN server.",
        address.trim()
    ))
}

/// Validate the user-supplied server address before any network call.
///
/// This is a CLIENT application — the user intentionally configures their own
/// server address.  LAN / private-IP deployments are the primary use case, so
/// private / loopback addresses are explicitly allowed.
///
/// Only the URL scheme is enforced: only `http://` and `https://` are accepted
/// to prevent `file://`, `javascript:`, or other dangerous scheme abuse.
pub fn validate_address(address: &str) -> Result<()> {
    let addr = address.trim();
    if addr.is_empty() {
        return Err(anyhow!("Server address is empty"));
    }

    // If the user typed a scheme explicitly, it must be http(s).
    let with_scheme = if addr.contains("://") {
        let lc = addr.to_ascii_lowercase();
        if !lc.starts_with("http://") && !lc.starts_with("https://") {
            return Err(anyhow!(
                "Only http:// and https:// are supported (got {})",
                addr.split("://").next().unwrap_or("")
            ));
        }
        addr.to_string()
    } else {
        format!("http://{}", addr)
    };

    // Verify the address is well-formed (valid host present).
    let parsed = Url::parse(&with_scheme)
        .map_err(|e| anyhow!("Invalid server address: {}", e))?;

    parsed
        .host_str()
        .ok_or_else(|| anyhow!("Server address must include a host"))?;

    Ok(())
}

pub async fn resolve_server_origin(address: &str) -> Result<String> {
    Ok(try_resolve_api_endpoint(address).await?.origin())
}

/// Resolve the REST API base URL (`scheme://host:port/api`) for a server address.
pub async fn resolve_api_base_url(address: &str) -> Result<String> {
    Ok(try_resolve_api_endpoint(address).await?.base_url())
}

pub async fn normalize_server_origin_best_effort(config: &mut AgentConfig) {
    let current = config.server_address.trim().to_string();
    if current.is_empty() {
        return;
    }

    let Ok(origin) = resolve_server_origin(&current).await else {
        return;
    };

    if origin == current {
        return;
    }

    info!(
        "Normalized BetterDesk server origin for API/CDAP: {} -> {}",
        current,
        origin
    );
    config.server_address = origin;

    if let Err(err) = config.save() {
        warn!("Failed to persist normalized server origin: {}", err);
    }
}

/// Validate a single step of the server connection.
pub async fn validate_step(address: &str, step_key: &str) -> ValidationResult {
    // AGENT-H3: reject malformed / private addresses before any HTTP call.
    if let Err(e) = validate_address(address) {
        return ValidationResult {
            step: step_key.to_string(),
            success: false,
            message: e.to_string(),
        };
    }

    let result = match step_key {
        "availability" => check_availability(address).await,
        "protocol" => check_protocol(address).await,
        "registration" => check_registration_open(address).await,
        "certificate" => check_certificate(address).await,
        _ => Err(anyhow!("Unknown validation step: {}", step_key)),
    };

    match result {
        Ok(msg) => ValidationResult {
            step: step_key.to_string(),
            success: true,
            message: msg,
        },
        Err(e) => ValidationResult {
            step: step_key.to_string(),
            success: false,
            message: e.to_string(),
        },
    }
}

/// Step 1: Check if the server is reachable.
/// Also probes HTTPS vs HTTP and caches the result.
async fn check_availability(address: &str) -> Result<String> {
    let endpoint = try_resolve_api_endpoint(address).await?;
    let api_url = endpoint.base_url();
    let url = format!("{}/server/stats", api_url);

    let client = build_http_client(8)?;

    let resp = client.get(&url).send().await.map_err(|e| {
        anyhow!("Cannot reach server at {}: {}", address, e)
    })?;

    if resp.status().is_success() {
        let proto = if endpoint.scheme == "https" { " (HTTPS)" } else { "" };
        Ok(format!("Server is reachable{}", proto))
    } else {
        Err(anyhow!("Server returned status {}", resp.status()))
    }
}

/// Step 2: Verify the server speaks BetterDesk protocol.
async fn check_protocol(address: &str) -> Result<String> {
    let api_url = resolve_api_base_url(address).await?;
    let url = format!("{}/server/stats", api_url);

    let client = build_http_client(8)?;

    let resp = client.get(&url).send().await?;
    let body: serde_json::Value = resp.json().await.map_err(|_| {
        anyhow!("Server response is not valid JSON — not a BetterDesk server")
    })?;

    // BetterDesk Go server /api/server/stats returns {"peers_count": N, ...}
    if body.get("peers_count").is_some() || body.get("version").is_some() {
        Ok("BetterDesk protocol confirmed".to_string())
    } else {
        Err(anyhow!("Server does not appear to be a BetterDesk server"))
    }
}

/// Step 3: Check if the server accepts new device registrations.
async fn check_registration_open(address: &str) -> Result<String> {
    let api_url = resolve_api_base_url(address).await?;
    let url = format!("{}/login-options", api_url);

    let client = build_http_client(8)?;

    let resp = client.get(&url).send().await;

    match resp {
        Ok(r) if r.status().is_success() => {
            Ok("Server accepts registrations".to_string())
        }
        Ok(r) if r.status().as_u16() == 403 => {
            Err(anyhow!("Server has closed registration"))
        }
        Ok(r) => {
            // Some BetterDesk deployments do not expose a dedicated probe here.
            info!("login-options returned {}, assuming open", r.status());
            Ok("Server accepts registrations".to_string())
        }
        Err(e) => {
            // Network error already caught by availability check — allow through.
            info!("login-options check failed: {}, assuming open", e);
            Ok("Server accepts registrations".to_string())
        }
    }
}

/// Step 4: Verify the TLS certificate (or accept self-signed with warning).
async fn check_certificate(address: &str) -> Result<String> {
    let api_url = resolve_api_base_url(address).await?;
    let url = format!("{}/server/stats", api_url);

    // First try strict TLS validation.
    let strict_client = Client::builder()
        .timeout(Duration::from_secs(5))
        .build()?;

    match strict_client.get(&url).send().await {
        Ok(_) => return Ok("Valid TLS certificate".to_string()),
        Err(e) => {
            let err_str = e.to_string().to_lowercase();
            if err_str.contains("certificate") || err_str.contains("ssl") || err_str.contains("tls") {
                // Self-signed cert — allow with warning.
                return Ok("Self-signed certificate (accepted)".to_string());
            }

            // If it's HTTP (not HTTPS), no cert to validate.
            if api_url.starts_with("http://") {
                return Ok("Plain HTTP connection (no certificate required)".to_string());
            }

            Err(anyhow!("Certificate validation failed: {}", e))
        }
    }
}

/// Outcome of a registration or enrollment status poll.
#[derive(Debug, Clone, Serialize)]
pub struct EnrollmentStatus {
    /// "approved" | "pending" | "rejected"
    pub status: String,
    pub device_id: String,
    pub message: String,
    /// Server-issued device token (only present when approved).
    #[serde(default)]
    pub device_token: String,
}

/// Register this device with the BetterDesk server.
/// Returns `Ok(EnrollmentStatus)` — callers can distinguish "approved" from
/// "pending" without catching an error, enabling the UI to show a proper
/// "waiting for operator approval" state rather than an error message.
pub async fn register_get_status(config: &mut AgentConfig) -> Result<EnrollmentStatus> {
    // AGENT-H3: reject malformed / private addresses before touching the network.
    validate_address(&config.server_address)?;

    let endpoint = try_resolve_api_endpoint(&config.server_address).await?;
    let api_url = endpoint.base_url();
    let normalized_origin = endpoint.origin();
    let url = format!("{}/devices/register", api_url);

    let sysinfo = SystemSnapshot::collect();
    let device_uid = machine_uid::get().unwrap_or_else(|_| uuid::Uuid::new_v4().to_string());

    let id_hash = {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(device_uid.as_bytes());
        hasher.update(b"|");
        hasher.update(sysinfo.hostname.as_bytes());
        hasher.update(b"|");
        hasher.update(env!("CARGO_PKG_VERSION").as_bytes());
        let result = hasher.finalize();
        format!("BD-{}", base32_encode_upper(&result[..8], 13))
    };

    // Enrollment requires a device identity: support-agent (`os_agent`) devices
    // must declare bundle_id + public_key and prove possession of the key with
    // the X-BD-Enrollment-* headers (Go server 3.5.156+, replay-protected).
    let (identity_key, public_key_b64) = load_or_create_identity()?;
    let bundle_id = enrollment_bundle_id();

    let payload = serde_json::json!({
        "device_id": id_hash,
        "uuid": device_uid,
        "hostname": sysinfo.hostname,
        "version": sysinfo.os_version,
        "platform": format!("{} {}", sysinfo.os, sysinfo.arch),
        "device_type": "os_agent",
        "bundle_id": bundle_id,
        "public_key": public_key_b64,
    });

    // Sign over the raw request path the server will see (query excluded).
    let proof_path = Url::parse(&url)
        .map(|u| u.path().to_string())
        .unwrap_or_else(|_| String::from("/api/devices/register"));

    let client = build_http_client(15)?;
    let mut req = client.post(&url).json(&payload);
    for (name, value) in
        enrollment_proof_headers("POST", &proof_path, &id_hash, &public_key_b64, &identity_key)
    {
        req = req.header(name, value);
    }
    let resp = req.send().await?;
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if !status.is_success() && status.as_u16() != 202 {
        return Err(anyhow!("Registration failed ({}): {}", status, body));
    }

    let enrollment: EnrollmentResponse = serde_json::from_str(&body)
        .map_err(|e| anyhow!("Registration returned invalid JSON: {}", e))?;

    match enrollment.status.as_str() {
        "approved" => {
            let registered_id = if enrollment.device_id.is_empty() {
                id_hash
            } else {
                enrollment.device_id.clone()
            };

            config.server_address = normalized_origin;
            config.device_id = registered_id.clone();
            config.device_name = sysinfo.hostname;
            config.registered = true;
            if !enrollment.device_token.trim().is_empty() {
                config.auth_token = enrollment.device_token.trim().to_string();
            }
            config.save()?;

            info!("Device registered as {}", registered_id);
            Ok(EnrollmentStatus {
                status: "approved".to_string(),
                device_id: registered_id,
                message: String::new(),
                device_token: enrollment.device_token.trim().to_string(),
            })
        }
        "pending" => {
            // Save partial state so we can resume polling after an app restart.
            let registered_id = if enrollment.device_id.is_empty() {
                id_hash
            } else {
                enrollment.device_id.clone()
            };
            config.server_address = normalized_origin;
            config.device_id = registered_id.clone();
            config.device_name = sysinfo.hostname;
            config.registered = false; // not yet — awaiting operator approval
            config.save()?;

            info!("Device {} is pending operator approval", registered_id);
            Ok(EnrollmentStatus {
                status: "pending".to_string(),
                device_id: registered_id,
                message: enrollment.message,
                device_token: String::new(),
            })
        }
        "rejected" => Err(anyhow!(
            "Enrollment was rejected{}",
            if enrollment.message.is_empty() {
                String::new()
            } else {
                format!(": {}", enrollment.message)
            }
        )),
        other => Err(anyhow!("Unexpected enrollment status: {}", other)),
    }
}

/// Poll `GET /api/devices/register/status?device_id=X` to check whether a
/// pending enrollment has been approved or rejected by an operator.
pub async fn poll_enrollment_status(address: &str, device_id: &str) -> Result<EnrollmentStatus> {
    validate_address(address)?;

    let api_url = resolve_api_base_url(address).await?;
    // device_id is a BD-[A-Z2-7]+ string — no URL encoding needed.
    let url = format!("{}/devices/register/status?device_id={}", api_url, device_id);

    // The Go server issues the approved device_token only for proof-signed
    // polls (Ed25519 over the raw request path, same scheme as registration).
    let client = build_http_client(10)?;
    let mut req = client.get(&url);
    if let Ok((identity_key, public_key_b64)) = load_or_create_identity() {
        let proof_path = Url::parse(&url)
            .map(|u| u.path().to_string())
            .unwrap_or_else(|_| String::from("/api/devices/register/status"));
        for (name, value) in
            enrollment_proof_headers("GET", &proof_path, device_id, &public_key_b64, &identity_key)
        {
            req = req.header(name, value);
        }
    } else {
        warn!("device identity unavailable - status poll without enrollment proof");
    }
    let resp = req.send().await?;
    let status_code = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if !status_code.is_success() {
        return Err(anyhow!(
            "Status poll failed ({}): {}",
            status_code,
            body
        ));
    }

    let enrollment: EnrollmentResponse = serde_json::from_str(&body)
        .map_err(|e| anyhow!("Status poll returned invalid JSON: {}", e))?;

    let result_device_id = if enrollment.device_id.is_empty() {
        device_id.to_string()
    } else {
        enrollment.device_id.clone()
    };

    Ok(EnrollmentStatus {
        status: enrollment.status,
        device_id: result_device_id,
        message: enrollment.message,
        device_token: enrollment.device_token.trim().to_string(),
    })
}

/// Register this device with the BetterDesk server.
pub async fn register(config: &mut AgentConfig) -> Result<String> {
    // AGENT-H3: reject malformed / private addresses before touching the network.
    validate_address(&config.server_address)?;

    let endpoint = try_resolve_api_endpoint(&config.server_address).await?;
    let api_url = endpoint.base_url();
    let normalized_origin = endpoint.origin();
    let url = format!("{}/devices/register", api_url);

    let sysinfo = SystemSnapshot::collect();
    let device_uid = machine_uid::get().unwrap_or_else(|_| uuid::Uuid::new_v4().to_string());

    // Keep the operator-facing device ID within the legacy 16-char limit used
    // across the BetterDesk/RustDesk surfaces. The full machine UUID still
    // travels separately in `uuid`, so enrollment keeps a stable high-entropy
    // anchor while the visible ID stays readable in the panel.
    let id_hash = {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(device_uid.as_bytes());
        hasher.update(b"|");
        hasher.update(sysinfo.hostname.as_bytes());
        hasher.update(b"|");
        hasher.update(env!("CARGO_PKG_VERSION").as_bytes());
        let result = hasher.finalize();
        format!("BD-{}", base32_encode_upper(&result[..8], 13))
    };

    // Enrollment requires a device identity for support-agent (`os_agent`)
    // devices: bundle_id + public_key + X-BD-Enrollment-* proof headers.
    let (identity_key, public_key_b64) = load_or_create_identity()?;
    let bundle_id = enrollment_bundle_id();

    let payload = serde_json::json!({
        "device_id": id_hash,
        "uuid": device_uid,
        "hostname": sysinfo.hostname,
        "version": sysinfo.os_version,
        "platform": format!("{} {}", sysinfo.os, sysinfo.arch),
        "device_type": "os_agent",
        "bundle_id": bundle_id,
        "public_key": public_key_b64,
    });

    // Sign over the raw request path the server will see (query excluded).
    let proof_path = Url::parse(&url)
        .map(|u| u.path().to_string())
        .unwrap_or_else(|_| String::from("/api/devices/register"));

    let client = build_http_client(15)?;
    let mut req = client.post(&url).json(&payload);
    for (name, value) in
        enrollment_proof_headers("POST", &proof_path, &id_hash, &public_key_b64, &identity_key)
    {
        req = req.header(name, value);
    }
    let resp = req.send().await?;
    let status = resp.status();
    let body = resp.text().await.unwrap_or_default();

    if !status.is_success() {
        return Err(anyhow!("Registration failed ({}): {}", status, body));
    }

    let enrollment: EnrollmentResponse = serde_json::from_str(&body)
        .map_err(|e| anyhow!("Registration returned invalid JSON: {}", e))?;

    match enrollment.status.as_str() {
        "approved" => {
            let registered_id = if enrollment.device_id.is_empty() {
                id_hash
            } else {
                enrollment.device_id
            };

            config.server_address = normalized_origin;
            config.device_id = registered_id.clone();
            config.device_name = sysinfo.hostname;
            config.registered = true;
            if !enrollment.device_token.trim().is_empty() {
                config.auth_token = enrollment.device_token.trim().to_string();
            }
            config.save()?;

            info!("Device registered as {}", registered_id);
            Ok(registered_id)
        }
        "pending" => Err(anyhow!(
            "Enrollment is pending operator approval{}",
            if enrollment.message.is_empty() {
                String::new()
            } else {
                format!(": {}", enrollment.message)
            }
        )),
        "rejected" => Err(anyhow!(
            "Enrollment was rejected{}",
            if enrollment.message.is_empty() {
                String::new()
            } else {
                format!(": {}", enrollment.message)
            }
        )),
        other => Err(anyhow!("Unexpected enrollment status: {}", other)),
    }
}

/// Sync initial configuration from server after registration.
pub async fn sync_config(config: &AgentConfig) -> Result<()> {
    // AGENT-H3: guard against a tampered config pointing at a private IP.
    validate_address(&config.server_address)?;

    let api_url = resolve_api_base_url(&config.server_address).await?;
    let url = format!("{}/sysinfo", api_url);

    let sysinfo = SystemSnapshot::collect();

    let payload = serde_json::json!({
        "id": config.device_id,
        "hostname": sysinfo.hostname,
        "os": sysinfo.os,
        "version": sysinfo.os_version,
        "platform": format!("{} {}", sysinfo.os, sysinfo.arch),
        "cpu": sysinfo.cpu_name,
        "memory": format!("{} MB", sysinfo.total_memory_mb),
    });

    let client = build_http_client(10)?;

    let resp = client.post(&url).json(&payload).send().await?;

    if resp.status().is_success() {
        info!("Initial sysinfo synced for {}", config.device_id);
        Ok(())
    } else {
        let status = resp.status();
        info!("Sysinfo sync returned {} — continuing anyway", status);
        Ok(())
    }
}

pub(crate) fn base32_encode_upper(bytes: &[u8], output_len: usize) -> String {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    let mut encoded = String::with_capacity(output_len);
    let mut buffer: u16 = 0;
    let mut bits_left: u8 = 0;

    for &byte in bytes {
        buffer = (buffer << 8) | u16::from(byte);
        bits_left += 8;

        while bits_left >= 5 && encoded.len() < output_len {
            let index = ((buffer >> (bits_left - 5)) & 0x1f) as usize;
            encoded.push(ALPHABET[index] as char);
            bits_left -= 5;
        }
    }

    if bits_left > 0 && encoded.len() < output_len {
        let index = ((buffer << (5 - bits_left)) & 0x1f) as usize;
        encoded.push(ALPHABET[index] as char);
    }

    encoded
}

pub async fn discover_lan_servers() -> Result<Vec<DiscoveredLanServer>> {
    let socket = tokio::net::UdpSocket::bind("0.0.0.0:0").await?;
    socket.set_broadcast(true)?;

    let probe = serde_json::json!({
        "type": "betterdesk-discover",
        "version": 1,
    });
    let probe_bytes = serde_json::to_vec(&probe)?;
    let dest: SocketAddr = format!("255.255.255.255:{}", DISCOVERY_PORT).parse()?;
    socket.send_to(&probe_bytes, dest).await?;

    let mut servers = HashMap::<String, DiscoveredLanServer>::new();
    let mut buf = [0u8; DISCOVERY_RECV_BUF_SIZE];
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);

    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            break;
        }

        match tokio::time::timeout(remaining, socket.recv_from(&mut buf)).await {
            Ok(Ok((len, addr))) => {
                let response = match serde_json::from_slice::<DiscoveryAnnounceResponse>(&buf[..len]) {
                    Ok(response) => response,
                    Err(_) => continue,
                };

                if response.msg_type != "betterdesk-announce" {
                    continue;
                }

                let ip = addr.ip().to_string();
                let protocol = if response.server.protocol.is_empty() {
                    "http".to_string()
                } else {
                    response.server.protocol.clone()
                };
                let console_port = if response.server.port > 0 { response.server.port } else { 5000 };
                let api_port = if response.server.api_port > 0 {
                    response.server.api_port
                } else {
                    DEFAULT_API_PORT
                };

                let server = DiscoveredLanServer {
                    name: response.server.name,
                    version: response.server.version,
                    address: ip.clone(),
                    port: console_port,
                    api_port,
                    protocol: protocol.clone(),
                    console_url: format!("{}://{}:{}", protocol, ip, console_port),
                };

                servers.insert(format!("{}:{}", server.address, server.port), server);
            }
            Ok(Err(_)) | Err(_) => break,
        }
    }

    let mut result: Vec<DiscoveredLanServer> = servers.into_values().collect();
    result.sort_by(|left, right| left.name.cmp(&right.name).then(left.address.cmp(&right.address)));
    Ok(result)
}
