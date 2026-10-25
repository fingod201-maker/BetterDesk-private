import { Component, createSignal, For, Show, onMount, onCleanup } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import { t } from "../lib/i18n";
import { frontendLog } from "../lib/logger";

interface DiscoveredLanServer {
  name: string;
  version: string;
  address: string;
  port: number;
  api_port: number;
  protocol: string;
  console_url: string;
}

interface PermissionStatus {
  key: string;
  granted: boolean;
  detail: string;
}

interface RemotePermissionReport {
  screen_capture: boolean;
  accessibility: boolean;
  firewall: boolean;
  autostart: boolean;
  details: PermissionStatus[];
}

interface PermissionTask {
  key: string;
  label: string;
  status: "pending" | "running" | "ok" | "error";
  error?: string;
}

interface SetupProps {
  onComplete: () => void;
}

const SetupWizard: Component<SetupProps> = (props) => {
  const [address, setAddress] = createSignal("");
  const [addressError, setAddressError] = createSignal("");
  const [discovering, setDiscovering] = createSignal(false);
  const [discoveryError, setDiscoveryError] = createSignal("");
  const [discoveredServers, setDiscoveredServers] = createSignal<DiscoveredLanServer[]>([]);

  const [report, setReport] = createSignal<RemotePermissionReport | null>(null);
  const [checking, setChecking] = createSignal(false);

  const [tasks, setTasks] = createSignal<PermissionTask[]>([
    { key: "validate", label: t("setup.task_validate"), status: "pending" },
    { key: "register", label: t("setup.task_register"), status: "pending" },
    { key: "permissions", label: t("setup.task_permissions"), status: "pending" },
    { key: "firewall", label: t("setup.task_firewall"), status: "pending" },
    { key: "autostart", label: t("setup.task_autostart"), status: "pending" },
    { key: "sidecar", label: t("setup.task_sidecar"), status: "pending" },
  ]);

  const [applying, setApplying] = createSignal(false);
  const [applyError, setApplyError] = createSignal("");
  const [done, setDone] = createSignal(false);
  let pollingInterval: ReturnType<typeof setInterval> | undefined;

  onCleanup(() => {
    if (pollingInterval !== undefined) clearInterval(pollingInterval);
  });

  onMount(() => {
    frontendLog("info", "setup", "Setup wizard mounted — single permission step");
    void discoverServers();
    void refreshPermissions();
  });

  const validateAddress = (): boolean => {
    let addr = address().trim();
    if (!addr) {
      setAddressError(t("setup.error_empty"));
      return false;
    }
    addr = addr.replace(/\/+$/, "");
    setAddress(addr);

    const pattern = /^(https?:\/\/)?[a-zA-Z0-9][a-zA-Z0-9._-]*(?::\d{1,5})?$/;
    if (!pattern.test(addr)) {
      setAddressError(t("setup.error_format"));
      return false;
    }
    setAddressError("");
    return true;
  };

  const discoverServers = async () => {
    setDiscovering(true);
    setDiscoveryError("");
    try {
      const servers = await invoke<DiscoveredLanServer[]>("discover_lan_servers");
      setDiscoveredServers(servers);
      if (!address() && servers.length === 1) {
        setAddress(servers[0].console_url);
      }
    } catch (error) {
      frontendLog("warn", "setup.discovery", "LAN discovery failed", error);
      setDiscoveryError(String(error));
    }
    setDiscovering(false);
  };

  const refreshPermissions = async () => {
    setChecking(true);
    try {
      const snapshot = await invoke<RemotePermissionReport>("check_remote_permissions");
      setReport(snapshot);
    } catch (error) {
      frontendLog("warn", "setup.permissions", "Permission probe failed", error);
    }
    setChecking(false);
  };

  const setTaskStatus = (key: string, status: PermissionTask["status"], error?: string) => {
    setTasks(
      tasks().map((task) => (task.key === key ? { ...task, status, error } : task))
    );
  };

  const resetTasks = () => {
    setTasks([
      { key: "validate", label: t("setup.task_validate"), status: "pending" },
      { key: "register", label: t("setup.task_register"), status: "pending" },
      { key: "permissions", label: t("setup.task_permissions"), status: "pending" },
      { key: "firewall", label: t("setup.task_firewall"), status: "pending" },
      { key: "autostart", label: t("setup.task_autostart"), status: "pending" },
      { key: "sidecar", label: t("setup.task_sidecar"), status: "pending" },
    ]);
  };

  const applyRemoteAccess = async () => {
    if (!validateAddress()) return;

    setApplying(true);
    setApplyError("");
    setDone(false);
    resetTasks();

    try {
      // ── Task 1: Validate server (all 4 sub-checks) ──
      setTaskStatus("validate", "running");
      for (const stepKey of ["availability", "protocol", "registration", "certificate"]) {
        await invoke("validate_server_step", { address: address().trim(), stepKey });
      }
      setTaskStatus("validate", "ok");

      // ── Task 2: Register device ──
      setTaskStatus("register", "running");
      const result = await invoke<{ status: string; device_id: string; message: string }>(
        "register_device",
        { address: address().trim() }
      );

      if (result.status === "pending") {
        // Managed-enrollment mode — poll for operator approval.
        const deviceId = result.device_id;
        pollingInterval = setInterval(async () => {
          try {
            const poll = await invoke<{ status: string; device_id: string; message: string }>(
              "poll_enrollment_status",
              { address: address().trim(), deviceId }
            );
            if (poll.status === "approved") {
              clearInterval(pollingInterval);
              pollingInterval = undefined;
              setTaskStatus("register", "ok");
              await finalizeRemoteAccess();
            } else if (poll.status === "rejected") {
              clearInterval(pollingInterval);
              pollingInterval = undefined;
              setApplying(false);
              setTaskStatus("register", "error", poll.message || t("setup.approval_rejected"));
              setApplyError(
                `${t("setup.approval_rejected")}${poll.message ? ": " + poll.message : ""}`
              );
            }
          } catch {
            // Network glitch — keep polling silently.
          }
        }, 5000);
        return;
      }

      if (result.status !== "approved") {
        throw new Error(result.message || t("setup.register_failed"));
      }
      setTaskStatus("register", "ok");

      await finalizeRemoteAccess();
    } catch (e) {
      setApplying(false);
      setApplyError(String(e));
      setTaskStatus("validate", "error", String(e));
    }
  };

  const finalizeRemoteAccess = async () => {
    try {
      // ── Task 3: Apply remote permissions + OS consent prompts ──
      setTaskStatus("permissions", "running");
      await invoke("apply_remote_permissions", {
        address: address().trim(),
        allowScreenCapture: true,
        allowUnattended: true,
      });
      setTaskStatus("permissions", "ok");
      await refreshPermissions();

      // ── Task 4: Firewall (single elevation prompt) ──
      setTaskStatus("firewall", "running");
      await invoke("configure_firewall", { address: address().trim() });
      setTaskStatus("firewall", "ok");

      // ── Task 5: Autostart ──
      setTaskStatus("autostart", "running");
      await invoke("set_os_autostart", { enabled: true });
      setTaskStatus("autostart", "ok");

      // ── Task 6: Sidecar is started by apply_remote_permissions ──
      setTaskStatus("sidecar", "ok");

      await refreshPermissions();
      setApplying(false);
      setDone(true);
    } catch (e) {
      setApplying(false);
      setApplyError(String(e));
      const running = tasks().find((task) => task.status === "running");
      if (running) setTaskStatus(running.key, "error", String(e));
    }
  };

  const retry = () => {
    setApplyError("");
    void applyRemoteAccess();
  };

  const permissionRows = () => {
    const snapshot = report();
    if (!snapshot) return [];
    return snapshot.details.filter(
      (detail) =>
        detail.key === "screen_capture" ||
        detail.key === "accessibility" ||
        detail.key === "firewall" ||
        detail.key === "autostart"
    );
  };

  const permissionIcon = (granted: boolean) =>
    granted ? "check_circle" : "radio_button_unchecked";

  return (
    <div class="setup-root">
      <div class="setup-card">
        <div class="setup-header">
          <span class="material-symbols-rounded setup-icon">verified_user</span>
          <h1>{t("setup.permission_title")}</h1>
          <p class="setup-subtitle">{t("setup.permission_subtitle")}</p>
        </div>

        {/* Server address + LAN discovery */}
        <div class="setup-body">
          <div class="setup-discovery-header">
            <div>
              <div class="form-label">{t("setup.lan_discovery_title")}</div>
              <div class="form-hint">{t("setup.lan_discovery_hint")}</div>
            </div>
            <button
              class="btn btn-secondary btn-sm"
              onClick={discoverServers}
              disabled={discovering()}
            >
              <span class="material-symbols-rounded">travel_explore</span>
              {discovering() ? t("setup.searching_lan") : t("setup.search_lan")}
            </button>
          </div>

          <Show when={discoveredServers().length > 0}>
            <div class="setup-discovery-list">
              <For each={discoveredServers()}>
                {(server) => (
                  <button
                    class={`setup-discovery-card ${address() === server.console_url ? "selected" : ""}`}
                    onClick={() => {
                      setAddress(server.console_url);
                      setAddressError("");
                    }}
                  >
                    <div class="setup-discovery-name">{server.name}</div>
                    <div class="setup-discovery-meta">{server.console_url}</div>
                    <Show when={server.version}>
                      <div class="setup-discovery-version">v{server.version}</div>
                    </Show>
                  </button>
                )}
              </For>
            </div>
          </Show>

          <Show when={!discovering() && discoveredServers().length === 0 && !discoveryError()}>
            <div class="form-hint">{t("setup.lan_discovery_empty")}</div>
          </Show>

          <Show when={discoveryError()}>
            <div class="form-error">{discoveryError()}</div>
          </Show>

          <label class="form-label">{t("setup.server_address")}</label>
          <input
            type="text"
            class={`form-input ${addressError() ? "error" : ""}`}
            placeholder={t("setup.server_placeholder")}
            value={address()}
            onInput={(e) => {
              setAddress(e.currentTarget.value);
              setAddressError("");
            }}
            onKeyDown={(e) => e.key === "Enter" && applyRemoteAccess()}
          />
          <Show when={addressError()}>
            <div class="form-error">{addressError()}</div>
          </Show>
        </div>

        {/* Required permissions (informational, granted in one tap) */}
        <div class="permission-section">
          <h2 class="permission-section-title">{t("setup.permissions_title")}</h2>
          <p class="permission-section-hint">{t("setup.permissions_hint")}</p>

          <Show
            when={!checking() && report()}
            fallback={
              <div class="permission-checking">
                <span class="material-symbols-rounded spin">sync</span>
                {t("setup.checking_permissions")}
              </div>
            }
          >
            <div class="permission-list">
              <For each={permissionRows()}>
                {(permission) => (
                  <div class={`permission-status ${permission.granted ? "granted" : "missing"}`}>
                    <span class="material-symbols-rounded">
                      {permissionIcon(permission.granted)}
                    </span>
                    <div class="permission-status-text">
                      <strong>{t(`setup.perm_${permission.key}`)}</strong>
                      <span>{permission.detail}</span>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </Show>

          <p class="permission-note">
            <span class="material-symbols-rounded">info</span>
            {t("setup.permission_os_note")}
          </p>
        </div>

        {/* Action button */}
        <div class="setup-actions">
          <Show when={!applying() && !done()}>
            <button
              class="btn btn-primary btn-enable"
              onClick={applyRemoteAccess}
              disabled={!address() || !!addressError()}
            >
              <span class="material-symbols-rounded">verified_user</span>
              {t("setup.enable_remote_access")}
            </button>
          </Show>
          <Show when={applying() && !done()}>
            <button class="btn btn-primary btn-enable" disabled>
              <span class="material-symbols-rounded spin">sync</span>
              {t("setup.applying_permissions")}
            </button>
          </Show>
          <Show when={done()}>
            <button class="btn btn-primary btn-enable" onClick={props.onComplete}>
              <span class="material-symbols-rounded">check_circle</span>
              {t("setup.finish")}
            </button>
          </Show>
        </div>

        {/* Error */}
        <Show when={applyError()}>
          <div class="setup-error">
            <span class="material-symbols-rounded">error</span>
            <p>{applyError()}</p>
            <button class="btn btn-secondary" onClick={retry}>
              {t("setup.retry")}
            </button>
          </div>
        </Show>
      </div>

      {/* Progress overlay (slides in when applying) */}
      <Show when={applying()}>
        <div class="progress-overlay">
          <div class="progress-card">
            <h3>{t("setup.progress_title")}</h3>
            <div class="progress-tasks">
              <For each={tasks()}>
                {(task) => (
                  <div
                    class={`progress-task ${task.status === "ok" ? "done" : task.status === "running" ? "active" : task.status === "error" ? "error" : ""}`}
                  >
                    <span
                      class={`progress-icon ${task.status === "ok" ? "done" : task.status === "running" ? "active" : task.status === "error" ? "error" : ""}`}
                    >
                      {task.status === "ok"
                        ? "check_circle"
                        : task.status === "running"
                          ? "sync"
                          : task.status === "error"
                            ? "error_outline"
                            : "radio_button_unchecked"}
                    </span>
                    <div class="progress-info">
                      <div class="progress-label">{task.label}</div>
                      <Show when={task.error}>
                        <div class="progress-err">{task.error}</div>
                      </Show>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </div>
        </div>
      </Show>
    </div>
  );
};

export default SetupWizard;
