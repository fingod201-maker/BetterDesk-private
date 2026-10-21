package agent

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// EnrollmentPayload represents the proof-signed enrollment request.
// Matches the Rust client's bd-enrollment-v1 format.
type EnrollmentRequest struct {
	DeviceID   string `json:"device_id"`
	UUID       string `json:"uuid"`
	BundleID   string `json:"bundle_id"`
	PublicKey  string `json:"public_key"`
	DeviceType string `json:"device_type"`
	Hostname   string `json:"hostname"`
	Version    string `json:"version"`
	Platform   string `json:"platform"`
}

// EnrollmentResponse matches the server's response.
type EnrollmentResponse struct {
	Status       string `json:"status"`        // "pending", "approved", "rejected"
	DeviceID     string `json:"device_id"`
	DeviceToken  string `json:"device_token"`
	Message      string `json:"message"`
	PollInterval int    `json:"poll_interval"` // seconds
}

// StatusResponse for polling.
type StatusResponse struct {
	Status      string `json:"status"`
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
	Message     string `json:"message"`
}

// enrollmentKeyPath returns the path to the Ed25519 private key file.
func (a *Agent) enrollmentKeyPath() string {
	if a.cfg.DataDir == "" {
		return ""
	}
	return filepath.Join(a.cfg.DataDir, "enrollment_key")
}

// loadOrCreateEnrollmentKey loads the Ed25519 private key or generates a new one.
func (a *Agent) loadOrCreateEnrollmentKey() (ed25519.PrivateKey, error) {
	keyPath := a.enrollmentKeyPath()
	if keyPath == "" {
		return nil, fmt.Errorf("data_dir not set")
	}

	data, err := os.ReadFile(keyPath)
	if err == nil && len(data) == ed25519.PrivateKeySize {
		return ed25519.PrivateKey(data), nil
	}

	// Generate new key
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(keyPath), 0700); err != nil {
		return nil, err
	}

	// Save with restricted permissions
	if err := os.WriteFile(keyPath, priv, 0600); err != nil {
		return nil, err
	}

	return priv, nil
}

// canonicalPublicKey returns the base64(std) encoding of the 32-byte raw public key.
func canonicalPublicKey(pub ed25519.PublicKey) string {
	return base64.StdEncoding.EncodeToString(pub)
}

// base32EncodeUpper encodes bytes to upper-case base32 (no padding).
func base32EncodeUpper(data []byte) string {
	enc := base32.StdEncoding.WithPadding(base32.NoPadding)
	return strings.ToUpper(enc.EncodeToString(data))
}

// enrollmentProofHeaders builds the X-BD-Enrollment-* headers.
func enrollmentProofHeaders(method, path, deviceID, pubKeyB64 string, priv ed25519.PrivateKey) (map[string]string, error) {
	ts := time.Now().UTC().Format(time.RFC3339)
	nonce := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	nonceStr := base64.RawURLEncoding.EncodeToString(nonce)

	// Payload: bd-enrollment-v1\n<method>\n<path>\n<device_id>\n<pubkey>\n<ts>\n<nonce>
	payload := fmt.Sprintf("bd-enrollment-v1\n%s\n%s\n%s\n%s\n%s\n%s",
		method, path, deviceID, pubKeyB64, ts, nonceStr)

	sig := ed25519.Sign(priv, []byte(payload))
	sigB64 := base64.StdEncoding.EncodeToString(sig)

	return map[string]string{
		"X-BD-Enrollment-Timestamp": ts,
		"X-BD-Enrollment-Nonce":     nonceStr,
		"X-BD-Enrollment-Signature": sigB64,
	}, nil
}

// enrollWithProof performs proof-signed enrollment via REST API.
// Returns device_token on success (status "approved").
func (a *Agent) enrollWithProof() (string, string, error) {
	priv, err := a.loadOrCreateEnrollmentKey()
	if err != nil {
		return "", "", err
	}
	pub := priv.Public().(ed25519.PublicKey)
	pubB64 := base64.StdEncoding.EncodeToString(pub)

	// Build device identity
	hostname, _ := os.Hostname()
	deviceUID := hostname // fallback
	// Deterministic device ID
	h := sha256.Sum256([]byte(deviceUID + "|" + hostname + "|" + a.version))
	deviceID := "BD-" + base32EncodeUpper(h[:8])

	// Use configured device_id if set, otherwise use generated
	if a.cfg.DeviceID != "" {
		deviceID = a.cfg.DeviceID
	}

	bundleID := "com.betterdesk.agent"

	req := EnrollmentRequest{
		DeviceID:   deviceID,
		UUID:       deviceUID,
		BundleID:   bundleID,
		PublicKey:  pubB64,
		DeviceType: "os_agent",
		Hostname:   hostname,
		Version:    a.version,
		Platform:   runtime.GOOS + " " + runtime.GOARCH,
	}

	body, err := json.Marshal(req)
	if err != nil {
		return "", "", err
	}

	// Enrollment REST API base URL: https://api.telcom.stream (no path)
	// The CDAP URL is wss://cdap.telcom.stream/cdap -> REST API is https://api.telcom.stream
	serverAddr := a.cfg.Server
	if strings.HasPrefix(a.cfg.Server, "wss://cdap.") || strings.HasPrefix(a.cfg.Server, "ws://cdap.") {
		// cdap.telcom.stream/cdap -> api.telcom.stream (no path)
		serverAddr = strings.Replace(a.cfg.Server, "cdap.", "api.", 1)
		serverAddr = strings.Replace(serverAddr, "wss://", "https://", 1)
		serverAddr = strings.Replace(serverAddr, "ws://", "http://", 1)
		// Strip path (/cdap)
		if u, err := url.Parse(serverAddr); err == nil {
			serverAddr = u.Scheme + "://" + u.Host
		}
	} else if strings.HasPrefix(a.cfg.Server, "wss://panel.") || strings.HasPrefix(a.cfg.Server, "ws://panel.") {
		u, _ := url.Parse(a.cfg.Server)
		serverAddr = "https://" + u.Host
	} else if strings.HasPrefix(a.cfg.Server, "wss://") || strings.HasPrefix(a.cfg.Server, "ws://") {
		u, _ := url.Parse(a.cfg.Server)
		serverAddr = "https://" + u.Host
	} else if !strings.HasPrefix(a.cfg.Server, "http://") && !strings.HasPrefix(a.cfg.Server, "https://") {
		serverAddr = "https://" + a.cfg.Server
	}

	// Ensure no trailing slash
	serverAddr = strings.TrimRight(serverAddr, "/")

	fullURL := serverAddr + "/api/devices/register"
	log.Printf("[enroll] POST %s", fullURL)
	headers, err := enrollmentProofHeaders("POST", "/api/devices/register", deviceID, pubB64, priv)
	if err != nil {
		return "", "", err
	}

	client := &http.Client{Timeout: 15 * time.Second}
	httpReq, err := http.NewRequest("POST", fullURL, bytes.NewReader(body))
	if err != nil {
		return "", "", err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		httpReq.Header.Set(k, v)
	}

	resp, err := client.Do(httpReq)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	var enroll EnrollmentResponse
	if err := json.Unmarshal(respBody, &enroll); err != nil {
		return "", "", fmt.Errorf("invalid enrollment response: %w (body: %s)", err, string(respBody))
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		return "", "", fmt.Errorf("enrollment failed (%d): %s", resp.StatusCode, string(respBody))
	}

	if enroll.Status == "approved" {
		return enroll.DeviceToken, enroll.DeviceID, nil
	}

	// Managed mode: poll status with proof
	pollURL := serverAddr + "/api/devices/register/status?device_id=" + deviceID
	interval := enroll.PollInterval
	if interval <= 0 {
		interval = 5
	}

	for {
		select {
		case <-a.ctx.Done():
			return "", "", a.ctx.Err()
		case <-time.After(time.Duration(interval) * time.Second):
		}

		statusHeaders, err := enrollmentProofHeaders("GET", "/api/devices/register/status?device_id="+deviceID, deviceID, pubB64, priv)
		if err != nil {
			return "", "", err
		}

		statusReq, _ := http.NewRequest("GET", pollURL, nil)
		for k, v := range statusHeaders {
			statusReq.Header.Set(k, v)
		}

		statusResp, err := client.Do(statusReq)
		if err != nil {
			log.Printf("[enroll] status poll failed: %v", err)
			continue
		}
		statusBody, _ := io.ReadAll(statusResp.Body)
		statusResp.Body.Close()

		var status StatusResponse
		if err := json.Unmarshal(statusBody, &status); err != nil {
			continue
		}

		if status.Status == "approved" {
			return status.DeviceToken, status.DeviceID, nil
		}
		if status.Status == "rejected" {
			return "", "", fmt.Errorf("enrollment rejected: %s", status.Message)
		}
		// pending -> continue polling
	}
}