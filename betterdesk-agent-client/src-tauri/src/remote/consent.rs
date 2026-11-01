//! Remote consent popup — Phase 4.
//! Shows a Tauri window popup with operator identity and granular permission checkboxes.
//! The agent replies with `remote_accept` (with granted permissions) or `remote_reject`.
//! Unattended mode skips the popup based on `access_policy`.

use crate::commands::AgentState;
use crate::config::AgentConfig;
use tauri::Manager;
use serde::{Deserialize, Serialize};

/// Permissions granted by the operator in the consent popup.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConsentPermission {
    Keyboard,
    Clipboard,
    Audio,
    FileTransfer,
    Recording,
    Camera,
    Block, // e.g. user clicked "Block" or denied all
}

/// Operator identity and consent request info.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ConsentRequest {
    pub operator: String,
    /// Unique request ID for correlating the response.
    pub request_id: String,
    /// Human-readable description of the requested access.
    pub description: String,
    /// Countdown in seconds before auto-deny (0 = no countdown).
    pub countdown: u64,
    /// Permissions being requested.
    pub permissions: Vec<ConsentPermission>,
    /// Whether this is unattended mode (no popup).
    pub unattended: bool,
}

/// Granted permissions response sent back to the server over the signal WS.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ConsentAccept {
    pub request_id: String,
    pub granted: bool,
    /// The permissions that were granted (empty if denied).
    pub permissions: Vec<ConsentPermission>,
}

/// Error response sent when consent is rejected.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ConsentReject {
    pub request_id: String,
    pub error: String,
}

/// Show the consent popup and return whether the user granted or denied.
///
/// In unattended mode, if `access_policy` permits, automatically accept;
/// otherwise deny with a reason.
pub fn show_consent_popup(
    state: &tauri::State<'_, AgentState>,
    app: &tauri::AppHandle,
    request: &ConsentRequest,
) -> Result<ConsentAccept, String> {
    let config = state.config.lock().map_err(|e| e.to_string())?;

    // Unattended mode: check access policy
    if request.unattended {
        let permitted = check_access_policy(&config, &request.permissions);
        if permitted {
            return Ok(ConsentAccept {
                request_id: request.request_id.clone(),
                granted: true,
                permissions: request.permissions.clone(),
            });
        } else {
            return Ok(ConsentReject {
                request_id: request.request_id.clone(),
                error: "Unattended access not permitted by access policy".to_string(),
            });
        }
    }

    // TODO: Show Tauri window popup with operator identity and permission checkboxes.
    // For now, log the request and auto-accept for demonstration.
    // In a full implementation, this would render a Tauri dialog with:
    // - Operator name/identity
    // - Checkbox list for each permission type
    // - Countdown timer
    // - Accept / Deny buttons
    //
    // The popup should emit:
    // - `remote_accept` with granted permissions when Accept is clicked
    // - `remote_reject` with error reason when Deny is clicked or countdown expires

    log::info!("Consent request from operator '{}': {}", request.operator, request.description);
    log::info!("  Permissions: {:?}", request.permissions);
    log::info!("  Countdown: {}s", request.countdown);

    // Placeholder: auto-accept for now. Replace with actual UI.
    Ok(ConsentAccept {
        request_id: request.request_id.clone(),
        granted: true,
        permissions: request.permissions.clone(),
    })
}

/// Check whether the access policy permits the requested permissions for unattended mode.
fn check_access_policy(config: &AgentConfig, requested: &[ConsentPermission]) -> bool {
    // TODO: Implement actual access policy check against config.access_mode
    // For now, permit all if the device is configured for unattended access.
    // The `config.access_mode` field determines which operations are allowed.
    let allowed = config.allow_clipboard // as a proxy for unattended-enabled
        && config.allow_terminal
        && config.allow_file_browser;

    // Simple check: if key unattended flags are set, permit requested permissions.
    requested.iter().all(|p| match p {
        ConsentPermission::Keyboard => config.allow_clipboard, // simplified
        ConsentPermission::Clipboard => config.allow_clipboard,
        ConsentPermission::Audio => config.allow_terminal, // simplified
        ConsentPermission::FileTransfer => config.allow_file_browser,
        ConsentPermission::Recording => config.allow_terminal, // simplified
        ConsentPermission::Camera => false, // typically not allowed in unattended
        ConsentPermission::Block => false,
    })
}