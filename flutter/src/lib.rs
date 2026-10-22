use std::os::raw::c_char;
use std::sync::{OnceLock, RwLock, Mutex as StdMutex};

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;
use tokio::sync::{broadcast, Mutex};

static SERVER_CONFIG: OnceLock<ServerConfig> = OnceLock::new();
static PERMANENT_PASSWORD_HASH: OnceLock<RwLock<Option<String>>> = OnceLock::new();
static UNATTENDED_ENABLED: OnceLock<RwLock<bool>> = OnceLock::new();

/// Embedded operator configuration (baked at build time).
static OPERATOR_HOST: OnceLock<RwLock<String>> = OnceLock::new();
static OPERATOR_PORT: OnceLock<RwLock<u16>> = OnceLock::new();

/// Broadcast channel for screen frames to connected operators.
static FRAME_BROADCAST: OnceLock<broadcast::Sender<Vec<u8>>> = OnceLock::new();

/// Connected client count.
static CLIENT_COUNT: OnceLock<Mutex<usize>> = OnceLock::new();

/// Tokio runtime handle for the listener.
static LISTENER_RUNTIME: OnceLock<StdMutex<Option<tokio::runtime::Runtime>>> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub use_https: bool,
    pub api_port: u16,
    pub cdap_port: u16,
}

impl ServerConfig {
    pub fn base_url(&self) -> String {
        let scheme = if self.use_https { "https" } else { "http" };
        if (self.use_https && self.api_port == 443) || (!self.use_https && self.api_port == 80) {
            format!("{}://{}", scheme, self.host)
        } else {
            format!("{}://{}:{}", scheme, self.host, self.api_port)
        }
    }

    pub fn cdap_url(&self) -> String {
        let scheme = if self.use_https { "wss" } else { "ws" };
        if (self.use_https && self.api_port == 443) || (!self.use_https && self.api_port == 80) {
            format!("{}://{}/cdap", scheme, self.host)
        } else {
            format!("{}://{}:{}/cdap", scheme, self.host, self.cdap_port)
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ConnectionStatus {
    pub connected: u8,
    pub latency_ms: i32,
    pub error_code: i32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct UnattendedConfig {
    pub enabled: u8,
    pub port: u16,
    pub has_password: u8,
}

#[no_mangle]
pub extern "C" fn betterdesk_configure_server(
    host: *const c_char,
    use_https: u8,
    api_port: u16,
) {
    let host_str = unsafe {
        if host.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(host).to_string_lossy().into_owned()
        }
    };
    let config = ServerConfig {
        host: host_str,
        use_https: use_https != 0,
        api_port,
        cdap_port: 21122,
    };
    let _ = SERVER_CONFIG.set(config.clone());
    eprintln!("[betterdesk-android] Configured server: {:?}", config);
}

#[no_mangle]
pub extern "C" fn betterdesk_server_base_url() -> *mut c_char {
    let config = match SERVER_CONFIG.get() {
        Some(c) => c,
        None => return std::ptr::null_mut(),
    };
    let url = config.base_url();
    CStringHelper::into_raw(url)
}

#[no_mangle]
pub extern "C" fn betterdesk_server_cdap_url() -> *mut c_char {
    let config = match SERVER_CONFIG.get() {
        Some(c) => c,
        None => return std::ptr::null_mut(),
    };
    let url = config.cdap_url();
    CStringHelper::into_raw(url)
}

#[no_mangle]
pub extern "C" fn betterdesk_connection_status() -> ConnectionStatus {
    ConnectionStatus {
        connected: 0,
        latency_ms: -1,
        error_code: 0,
    }
}

#[no_mangle]
pub extern "C" fn betterdesk_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(std::ffi::CString::from_raw(ptr)) };
    }
}

fn get_password_lock() -> &'static RwLock<Option<String>> {
    PERMANENT_PASSWORD_HASH.get_or_init(|| RwLock::new(None))
}

fn get_enabled_lock() -> &'static RwLock<bool> {
    UNATTENDED_ENABLED.get_or_init(|| RwLock::new(false))
}

#[no_mangle]
pub extern "C" fn betterdesk_set_permanent_password(
    password: *const c_char,
) {
    let pw = unsafe {
        if password.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(password).to_string_lossy().into_owned()
        }
    };

    let enabled_lock = get_enabled_lock();
    let pw_lock = get_password_lock();

    if pw.is_empty() {
        *enabled_lock.write().unwrap() = false;
        *pw_lock.write().unwrap() = None;
        eprintln!("[betterdesk-android] Permanent password cleared");
        return;
    }

    let salt: [u8; 16] = {
        let mut s = [0u8; 16];
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        for (i, b) in s.iter_mut().enumerate().take(16) {
            *b = ((n >> (i * 4)) & 0xFF) as u8;
        }
        s
    };

    let hash = pbkdf2_hash(&pw, &salt);
    *enabled_lock.write().unwrap() = true;
    *pw_lock.write().unwrap() = Some(format!("{}:{}", hex_encode(&salt), hash));
    eprintln!("[betterdesk-android] Permanent password set");
}

#[no_mangle]
pub extern "C" fn betterdesk_verify_password(
    candidate: *const c_char,
) -> u8 {
    let cand = unsafe {
        if candidate.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(candidate).to_string_lossy().into_owned()
        }
    };

    let enabled = *get_enabled_lock().read().unwrap();
    if !enabled { return 0; }

    let stored = get_password_lock().read().unwrap();
    let stored = match stored.as_ref() {
        Some(s) => s,
        None => return 0,
    };

    let parts: Vec<&str> = stored.splitn(2, ':').collect();
    if parts.len() != 2 { return 0; }

    let salt = match hex_decode(parts[0]) {
        Some(s) => s,
        None => return 0,
    };
    let expected_hash = parts[1];

    let candidate_hash = pbkdf2_hash(&cand, &salt);
    if candidate_hash == expected_hash { 1 } else { 0 }
}

#[no_mangle]
pub extern "C" fn betterdesk_unattended_config() -> UnattendedConfig {
    let enabled = *get_enabled_lock().read().unwrap();
    let has_password = get_password_lock().read().unwrap().is_some();
    UnattendedConfig {
        enabled: if enabled { 1 } else { 0 },
        port: 21122,
        has_password: if has_password { 1 } else { 0 },
    }
}

/// Set the embedded operator configuration (called once at startup from Flutter).
#[no_mangle]
pub extern "C" fn betterdesk_set_embedded_config(
    host: *const c_char,
    port: u16,
    password_hash: *const c_char,
) {
    let host_str = unsafe {
        if host.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(host).to_string_lossy().into_owned()
        }
    };
    let hash_str = unsafe {
        if password_hash.is_null() { String::new() } else {
            std::ffi::CStr::from_ptr(password_hash).to_string_lossy().into_owned()
        }
    };

    *OPERATOR_HOST.get_or_init(|| RwLock::new(String::new())).write().unwrap() = host_str.clone();
    *OPERATOR_PORT.get_or_init(|| RwLock::new(21122)).write().unwrap() = port;

    if !hash_str.is_empty() {
        *get_enabled_lock().write().unwrap() = true;
        *PERMANENT_PASSWORD_HASH.get_or_init(|| RwLock::new(None)).write().unwrap() = Some(hash_str);
        eprintln!("[betterdesk-android] Embedded operator config set: {}:{} password_hash=present", host_str, port);
    } else {
        eprintln!("[betterdesk-android] Embedded operator config set: {}:{} no password", host_str, port);
    }
}

/// Query embedded operator configuration.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct EmbeddedOperatorConfig {
    pub host_len: i32,
    pub port: u16,
    pub has_password: u8,
    pub use_https: u8,
}

#[no_mangle]
pub extern "C" fn betterdesk_get_embedded_config() -> EmbeddedOperatorConfig {
    let host = OPERATOR_HOST.get().map(|l| l.read().unwrap().clone()).unwrap_or_default();
    let port = OPERATOR_PORT.get().map(|l| l.read().unwrap().clone()).unwrap_or(21122);
    let has_password = PERMANENT_PASSWORD_HASH.get().map(|l| l.read().unwrap().is_some()).unwrap_or(false);

    EmbeddedOperatorConfig {
        host_len: host.len() as i32,
        port,
        has_password: if has_password { 1 } else { 0 },
        use_https: 1,
    }
}

/// Get the embedded operator host as a C string.
#[no_mangle]
pub extern "C" fn betterdesk_get_operator_host() -> *mut c_char {
    let host = OPERATOR_HOST.get().map(|l| l.read().unwrap().clone()).unwrap_or_default();
    CStringHelper::into_raw(host)
}

/// Get the embedded operator port.
#[no_mangle]
pub extern "C" fn betterdesk_get_operator_port() -> u16 {
    OPERATOR_PORT.get().map(|l| l.read().unwrap().clone()).unwrap_or(21122)
}

/// Check if embedded password hash is configured.
#[no_mangle]
pub extern "C" fn betterdesk_has_embedded_password() -> u8 {
    PERMANENT_PASSWORD_HASH.get().map(|l| l.read().unwrap().is_some()).unwrap_or(false) as u8
}

#[no_mangle]
pub extern "C" fn betterdesk_start_listener() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (tx, _) = broadcast::channel::<Vec<u8>>(16);
    let _ = FRAME_BROADCAST.set(tx);
    let _ = CLIENT_COUNT.set(Mutex::new(0));

    rt.spawn(async move {
        let listener = match TcpListener::bind("0.0.0.0:21122").await {
            Ok(l) => l,
            Err(e) => {
                eprintln!("[betterdesk-android] Failed to bind port 21122: {}", e);
                return;
            }
        };
        eprintln!("[betterdesk-android] TCP listener active on port 21122");

        loop {
            match listener.accept().await {
                Ok((socket, addr)) => {
                    eprintln!("[betterdesk-android] Connection from {}", addr);
                    let mut rx = FRAME_BROADCAST
                        .get()
                        .expect("frame broadcast")
                        .subscribe();
                    let client_count = CLIENT_COUNT
                        .get()
                        .expect("client count")
                        .clone();
                    tokio::spawn(async move {
                        let _guard = client_count.lock().await;
                        drop(_guard);
                        let _ = rx.recv().await;
                    });
                }
                Err(e) => {
                    eprintln!("[betterdesk-android] Accept error: {}", e);
                }
            }
        }
    });

    let _ = LISTENER_RUNTIME.set(StdMutex::new(Some(rt)));
    eprintln!("[betterdesk-android] Listener runtime started");
}

#[no_mangle]
pub extern "C" fn betterdesk_stop_listener() {
    if let Some(rt) = LISTENER_RUNTIME.get().and_then(|m| m.lock().unwrap().take()) {
        drop(rt);
    }
    eprintln!("[betterdesk-android] Listener stopped");
}

#[no_mangle]
pub extern "C" fn betterdesk_capture_frame() -> *mut c_char {
    let json = r#"{"frame":null,"width":0,"height":0}"#;
    CStringHelper::into_raw(json.to_string())
}

#[no_mangle]
pub extern "C" fn betterdesk_inject_touch(
    x: f64,
    y: f64,
    down: u8,
) {
    eprintln!("[betterdesk-android] Inject touch: x={}, y={}, down={}", x, y, down);
}

#[no_mangle]
pub extern "C" fn betterdesk_inject_key(
    key_code: i32,
    down: u8,
) {
    eprintln!("[betterdesk-android] Inject key: code={}, down={}", key_code, down);
}

struct CStringHelper;

impl CStringHelper {
    fn into_raw(s: String) -> *mut c_char {
        use std::ffi::CString;
        match CString::new(s) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

fn pbkdf2_hash(password: &str, salt: &[u8]) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    password.hash(&mut hasher);
    salt.hash(&mut hasher);
    format!("{:064x}", hasher.finish())
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
        .collect::<Result<Vec<u8>, _>>()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_omits_default_https_port() {
        betterdesk_configure_server("panel.telcom.stream".as_ptr() as *const c_char, 1, 443);
    }

    #[test]
    fn password_set_and_verify() {
        betterdesk_set_permanent_password("operator123".as_ptr() as *const c_char);
        assert_eq!(betterdesk_verify_password("operator123".as_ptr() as *const c_char), 1);
        assert_eq!(betterdesk_verify_password("wrong".as_ptr() as *const c_char), 0);
        betterdesk_set_permanent_password(std::ptr::null_mut());
        assert_eq!(betterdesk_verify_password("operator123".as_ptr() as *const c_char), 0);
    }
}

// ── server-reachability agent dial-out (device → panel relay) ────────────
// Enabled on Android targets; gate keeps host builds (no NDK C toolchain)
// compiling without the TLS stack.

#[cfg(target_os = "android")]
mod agent_relay {
    use crate::*;
    use tokio::sync::mpsc;
    use tokio_tungstenite::tungstenite::Message;
    use futures_util::{SinkExt, StreamExt};

type AgentWs = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

struct AgentConfig {
    device_id: String,
    base_url: String,
    token: String,
}

static AGENT_CONFIG: OnceLock<RwLock<Option<AgentConfig>>> = OnceLock::new();
static AGENT_STREAMING: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);
static AGENT_WANTS_DIAL: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);
static AGENT_TX: OnceLock<StdMutex<Option<mpsc::UnboundedSender<Message>>>> = OnceLock::new();
static AGENT_EVENTS: OnceLock<StdMutex<std::collections::VecDeque<String>>> = OnceLock::new();

fn agent_event_queue() -> &'static StdMutex<std::collections::VecDeque<String>> {
    AGENT_EVENTS.get_or_init(|| StdMutex::new(std::collections::VecDeque::new()))
}

fn push_agent_event(json: String) {
    let mut q = agent_event_queue().lock().unwrap();
    if q.len() < 512 {
        q.push_back(json);
    }
}

fn agent_ws_url() -> Option<String> {
    let cfg = AGENT_CONFIG.get_or_init(|| RwLock::new(None)).read().unwrap();
    let cfg = cfg.as_ref()?;
    let ws_base = if cfg.base_url.starts_with("https://") {
        format!("wss://{}", &cfg.base_url["https://".len()..])
    } else if cfg.base_url.starts_with("http://") {
        format!("ws://{}", &cfg.base_url["http://".len()..])
    } else {
        format!("wss://{}", cfg.base_url.trim_start_matches('/'))
    };
    let base = ws_base.trim_end_matches('/');
    Some(format!(
        "{}/ws/remote-agent/{}?token={}",
        base, cfg.device_id, cfg.token
    ))
}

#[no_mangle]
pub extern "C" fn betterdesk_set_agent_config(
    device_id: *const c_char,
    base_url: *const c_char,
    token: *const c_char,
) {
    let grab = |p: *const c_char| -> String {
        unsafe {
            if p.is_null() { String::new() } else {
                std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
            }
        }
    };
    let cfg = AgentConfig {
        device_id: grab(device_id),
        base_url: grab(base_url),
        token: grab(token),
    };
    *AGENT_CONFIG.get_or_init(|| RwLock::new(None)).write().unwrap() = Some(cfg);
}

#[no_mangle]
pub extern "C" fn betterdesk_agent_connect() {
    if AGENT_WANTS_DIAL.swap(1, std::sync::atomic::Ordering::SeqCst) == 1 {
        return; // dialer task already looping
    }
    let _ = AGENT_TX.get_or_init(|| StdMutex::new(None));
    std::thread::spawn(|| {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(2)
            .build()
            .unwrap();
        rt.block_on(agent_dial_loop());
    });
}

#[no_mangle]
pub extern "C" fn betterdesk_agent_disconnect() {
    AGENT_WANTS_DIAL.store(0, std::sync::atomic::Ordering::SeqCst);
    if let Some(sfx) = AGENT_TX.get().and_then(|m| m.lock().unwrap().take()) {
        let _ = sfx.send(Message::Close(None));
    }
    AGENT_STREAMING.store(0, std::sync::atomic::Ordering::SeqCst);
}

#[no_mangle]
pub extern "C" fn betterdesk_is_streaming() -> u8 {
    AGENT_STREAMING.load(std::sync::atomic::Ordering::SeqCst)
}

/// Feed one JPEG frame (bytes from the MediaProjection capture pump).
#[no_mangle]
pub extern "C" fn betterdesk_feed_frame(data: *const u8, len: usize) -> u8 {
    if AGENT_STREAMING.load(std::sync::atomic::Ordering::SeqCst) == 0 {
        return 0;
    }
    if data.is_null() || len == 0 || len > 2 * 1024 * 1024 {
        return 0;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    let guard = AGENT_TX.get();
    if let Some(sfx) = guard.and_then(|m| m.lock().unwrap().clone()) {
        let _ = sfx.send(Message::binary(bytes.to_vec()));
        1
    } else {
        0
    }
}

/// Pop one pending input event as JSON text. Returns length, or -1 when empty,
/// or -2 when the buffer was too small.
#[no_mangle]
pub extern "C" fn betterdesk_pop_event(buf: *mut u8, cap: usize) -> i32 {
    let ev = {
        let mut q = agent_event_queue().lock().unwrap();
        q.pop_front()
    };
    let ev = match ev {
        Some(e) => e,
        None => return -1,
    };
    let bytes = ev.as_bytes();
    if buf.is_null() || cap < bytes.len() + 1 {
        // push it back so it is not lost
        agent_event_queue().lock().unwrap().push_front(ev);
        return -2;
    }
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, bytes.len()) };
    unsafe { *buf.add(bytes.len()) = 0 };
    bytes.len() as i32
}

async fn agent_dial_loop() {
    let mut backoff_secs: u64 = 3;
    loop {
        if AGENT_WANTS_DIAL.load(std::sync::atomic::Ordering::SeqCst) == 0 {
            return;
        }
        let url = match agent_ws_url() {
            Some(u) => u,
            None => return, // no config: stop until re-configured
        };
        match tokio_tungstenite::connect_async(&url).await {
            Ok((ws, _resp)) => {
                push_agent_event(serde_json::json!({"type": "dialer", "event": "connected", "url": url}).to_string());
                eprintln!("[betterdesk-android] agent relay connected: {}", url);
                backoff_secs = 3;
                agent_session(ws).await;
            }
            Err(e) => {
                push_agent_event(serde_json::json!({"type": "dialer", "event": "failed", "url": url, "error": format!("{}", e)}).to_string());
                eprintln!("[betterdesk-android] agent relay connect failed: {}", e);
            }
        }
        AGENT_STREAMING.store(0, std::sync::atomic::Ordering::SeqCst);
        tokio::time::sleep(std::time::Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(60);
    }
}

async fn agent_session(ws: AgentWs) {
    let (mut sink, mut stream) = ws.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let pong_tx = tx.clone();

    // Route captured frames of THIS session into our channel. Clearing any
    // stale sender first guarantees feed_frame() failures point at the dead
    // socket, not the previous session's channel.
    if let Ok(mut g) = AGENT_TX.get_or_init(|| StdMutex::new(None)).lock() {
        *g = Some(tx);
    }

    let _ = sink.send(Message::text(
        serde_json::json!({ "type": "agent-ready", "device_id": agent_device_id() }).to_string(),
    )).await;

    // Writer: sends queued frames and periodically pings the relay so the
    // connection survives NAT/CGNAT idle drops while we stand by (each ping
    // also flushes tungstenite's auto-generated Pong frames). Terminates when
    // the channel closes (the session teardown drops ping-tx) or a send fails.
    let writer = async {
        loop {
            tokio::select! {
                msg = rx.recv() => {
                    match msg {
                        None => break,
                        Some(m) => {
                            if sink.send(m).await.is_err() {
                                break;
                            }
                        }
                    }
                }
                _ = tokio::time::sleep(std::time::Duration::from_secs(15)) => {
                    if sink.send(Message::Ping(Vec::new())).await.is_err() {
                        break;
                    }
                }
            }
        }
    };

    let reader = async {
        while let Some(msg) = stream.next().await {
            match msg {
                Ok(Message::Text(txt)) => handle_agent_text(&txt),
                Ok(Message::Ping(p)) => {
                    let _ = pong_tx.send(Message::Pong(p));
                }
                Ok(Message::Close(_)) | Err(_) => break,
                _ => {}
            }
        }
    };

    // select!: whichever side ends first tears the session down. This is the
    // critical fix — the relay closes the agent after 90 s of idle; with
    // join!() the writer could await the channel forever because the only
    // sender lived inside AGENT_TX and was only cleared after join.
    tokio::select! {
        _ = reader => {}
        _ = writer => {}
    }

    if let Ok(mut g) = AGENT_TX.get_or_init(|| StdMutex::new(None)).lock() {
        *g = None;
    }
}

fn agent_device_id() -> String {
    AGENT_CONFIG
        .get()
        .map(|l| l.read().unwrap().as_ref().map(|c| c.device_id.clone()))
        .flatten()
        .unwrap_or_default()
}

fn handle_agent_text(txt: &str) {
    let v: serde_json::Value = match serde_json::from_str(txt) {
        Ok(v) => v,
        Err(_) => return,
    };
    match v.get("type").and_then(|t| t.as_str()).unwrap_or("") {
        "start" => {
            AGENT_STREAMING.store(1, std::sync::atomic::Ordering::SeqCst);
            eprintln!("[betterdesk-android] agent stream START");
        }
        "stop" => {
            AGENT_STREAMING.store(0, std::sync::atomic::Ordering::SeqCst);
            eprintln!("[betterdesk-android] agent stream STOP");
        }
        t if !t.is_empty() => {
            push_agent_event(v.to_string());
        }
        _ => {}
    }
}

    // ── enrollment identity (Ed25519) ──────────────────────────────────────
    // The BetterDesk server treats os_agent registrations as support-agent
    // enrollments: they must prove possession of an installation key by
    // signing the canonical enrollment payload
    //   "bd-enrollment-v1\n<method>\n<path>\n<device_id>\n<pubkey>\n<ts>\n<nonce>"
    // The seed is generated and stored by the app (Android Keystore-backed
    // storage); Rust only derives the public key and signs.

    fn b64_decode(data: &str) -> Option<Vec<u8>> {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD.decode(data.trim()).ok()
    }

    fn b64_encode(data: &[u8]) -> String {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD.encode(data)
    }

    /// Base64 (std) of the 32-byte Ed25519 public key for the given seed.
    fn enrollment_public_key(seed_b64: &str) -> Option<String> {
        use ed25519_dalek::SigningKey;
        let seed = b64_decode(seed_b64)?;
        if seed.len() != 32 {
            return None;
        }
        let mut fixed = [0u8; 32];
        fixed.copy_from_slice(&seed);
        let signing = SigningKey::from_bytes(&fixed);
        Some(b64_encode(signing.verifying_key().as_bytes()))
    }

    /// Base64 (std) Ed25519 signature over the UTF-8 payload.
    fn enrollment_sign(seed_b64: &str, payload: &str) -> Option<String> {
        use ed25519_dalek::{Signer, SigningKey};
        let seed = b64_decode(seed_b64)?;
        if seed.len() != 32 {
            return None;
        }
        let mut fixed = [0u8; 32];
        fixed.copy_from_slice(&seed);
        let signing = SigningKey::from_bytes(&fixed);
        let sig = signing.sign(payload.as_bytes());
        Some(b64_encode(&sig.to_bytes()))
    }

    // ── JNI exports (called from Kotlin AgentRelayBridge) ─────────────────

    use jni::objects::{JByteArray, JClass, JString};
    use jni::sys::{jboolean, jint, jstring};
    use jni::JNIEnv;

    fn cstring_from_java(env: &mut JNIEnv<'_>, s: &JString) -> std::ffi::CString {
        std::ffi::CString::new(
            env.get_string(s)
                .map(|x| x.to_string_lossy().into_owned())
                .unwrap_or_default(),
        )
        .unwrap_or_default()
    }

    /// Hand a Rust string back to Java (null when the value is empty).
    fn java_string(env: &mut JNIEnv<'_>, value: String) -> jstring {
        if value.is_empty() {
            return std::ptr::null_mut();
        }
        match env.new_string(value) {
            Ok(v) => v.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeEnrollmentPublicKey(
        mut env: JNIEnv,
        _cls: JClass,
        seed: JString,
    ) -> jstring {
        let seed_c = cstring_from_java(&mut env, &seed);
        let seed_str = seed_c.to_str().unwrap_or("").to_string();
        let out = enrollment_public_key(&seed_str).unwrap_or_default();
        java_string(&mut env, out)
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeEnrollmentSign(
        mut env: JNIEnv,
        _cls: JClass,
        seed: JString,
        payload: JString,
    ) -> jstring {
        let seed_c = cstring_from_java(&mut env, &seed);
        let payload_c = cstring_from_java(&mut env, &payload);
        let out = enrollment_sign(
            seed_c.to_str().unwrap_or(""),
            payload_c.to_str().unwrap_or(""),
        )
        .unwrap_or_default();
        java_string(&mut env, out)
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeSetAgentConfig(
        mut env: JNIEnv,
        _cls: JClass,
        jid: JString,
        jbase: JString,
        jtoken: JString,
    ) {
        let id = cstring_from_java(&mut env, &jid);
        let base = cstring_from_java(&mut env, &jbase);
        let token = cstring_from_java(&mut env, &jtoken);
        betterdesk_set_agent_config(id.as_ptr(), base.as_ptr(), token.as_ptr());
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeConnect(
        _env: JNIEnv,
        _cls: JClass,
    ) {
        betterdesk_agent_connect();
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeDisconnect(
        _env: JNIEnv,
        _cls: JClass,
    ) {
        betterdesk_agent_disconnect();
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeIsStreaming(
        _env: JNIEnv,
        _cls: JClass,
    ) -> jboolean {
        betterdesk_is_streaming() as jboolean
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativeFeedFrame(
        mut env: JNIEnv,
        _cls: JClass,
        frame: JByteArray,
    ) -> jboolean {
        let len = env.get_array_length(&frame).unwrap_or(0) as usize;
        if len == 0 {
            return 0;
        }
        let mut buf = vec![0i8; len];
        let ok = env.get_byte_array_region(&frame, 0, &mut buf).is_ok();
        if !ok {
            return 0;
        }
        let bytes = std::mem::transmute::<&[i8], &[u8]>(&buf[..]);
        betterdesk_feed_frame(bytes.as_ptr(), len) as jboolean
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_com_carriez_flutter_1hbb_AgentRelayBridge_nativePopEvent<'local>(
        mut env: JNIEnv<'local>,
        _cls: JClass,
    ) -> JString<'local> {
        let mut buf = vec![0u8; 8192];
        loop {
            let len = betterdesk_pop_event(buf.as_mut_ptr(), buf.len());
            if len == -1 {
                return env.new_string("").unwrap();
            }
            if len == -2 {
                buf.resize(buf.len() * 2, 0);
                continue;
            }
            let text = String::from_utf8_lossy(&buf[..len as usize]).into_owned();
            return env.new_string(text).unwrap();
        }
    }

    /// JNI `jint` unused marker helper (kept for future use) - silences lints.
    #[allow(dead_code)]
    fn _len_marker(_: jint) {}
}
