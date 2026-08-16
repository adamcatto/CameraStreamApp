import "./styles.css";
import { applyCameraSettings, createSession, getSession, stopSession, streamUrl } from "./api";
import { captureFields, defaultCaptureSettings, sanitizeCaptureSettings, type CaptureSettings } from "./capture-settings";
import { importCredentialFile, type CredentialImportResult } from "./credential-import";
import { exampleWorkspace, normalizeWorkspaces, type CameraStatus, type CameraWorkspace, type SessionStatus } from "./models";
import { disposeTerminals, mountTerminals } from "./terminal";

type View = "workspace" | "settings" | "stream";
type PendingIntent = "stream" | "shell";

const storageKey = "camera-stream.workspaces.v1";
const app = document.querySelector<HTMLDivElement>("#app")!;
let workspaces = loadWorkspaces();
let selectedId = workspaces[0]?.id ?? "";
let view: View = "workspace";
let session: SessionStatus | null = null;
let credentials: Record<string, string> = {};
let status = "Ready";
let busy = false;
let credentialIntent: PendingIntent | null = null;
let terminalOpen = false;
let credentialImportSummary: (Omit<CredentialImportResult, "credentials"> & { filename: string }) | null = null;
let settingsCameraId: string | null = null;
let settingsDraft: CaptureSettings | null = null;
const revealedAccounts = new Set<string>();

render();

app.addEventListener("click", async (event) => {
  const button = (event.target as HTMLElement).closest<HTMLElement>("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  try {
    if (action === "select-workspace") {
      selectedId = button.dataset.id ?? selectedId;
      view = session?.streaming ? "stream" : "workspace";
      render();
    } else if (action === "add-workspace") {
      const workspace: CameraWorkspace = { id: crypto.randomUUID(), name: "New workspace", jumpHost: null, cameras: [] };
      workspaces.push(workspace);
      selectedId = workspace.id;
      view = "workspace";
      saveWorkspaces();
      render();
    } else if (action === "rename-workspace") {
      const workspace = workspaces.find((item) => item.id === button.dataset.id);
      if (!workspace) return;
      const name = window.prompt("Workspace name", workspace.name)?.trim();
      if (name) {
        workspace.name = name;
        saveWorkspaces();
        render();
      }
    } else if (action === "delete-workspace") {
      await deleteWorkspace(button.dataset.id ?? "");
    } else if (action === "settings") {
      view = "settings";
      render();
    } else if (action === "workspace") {
      view = session?.streaming ? "stream" : "workspace";
      render();
    } else if (action === "add-camera") {
      const workspace = selectedWorkspace();
      if (!workspace) return;
      workspace.cameras.push({
        id: crypto.randomUUID(),
        name: `Camera ${workspace.cameras.length + 1}`,
        host: "",
        username: "pi",
        port: 8888,
      });
      saveWorkspaces();
      render();
    } else if (action === "remove-camera") {
      const workspace = selectedWorkspace();
      if (!workspace) return;
      workspace.cameras = workspace.cameras.filter((camera) => camera.id !== button.dataset.id);
      saveWorkspaces();
      render();
    } else if (action === "start") {
      await requestIntent("stream");
    } else if (action === "stop") {
      await stopActiveSession();
    } else if (action === "shell") {
      if (session) openTerminal();
      else await requestIntent("shell");
    } else if (action === "cancel-credentials") {
      credentialIntent = null;
      render();
    } else if (action === "submit-credentials") {
      await submitCredentials();
    } else if (action === "open-settings") {
      openCameraSettings(button.dataset.id ?? "");
    } else if (action === "close-settings") {
      settingsCameraId = null;
      settingsDraft = null;
      render();
    } else if (action === "reset-settings") {
      settingsDraft = { ...defaultCaptureSettings };
      render();
    } else if (action === "apply-settings") {
      await applyActiveSettings();
    } else if (action === "close-terminal") {
      terminalOpen = false;
      disposeTerminals();
      render();
    } else if (action === "clear-credentials") {
      credentials = {};
      revealedAccounts.clear();
      credentialImportSummary = null;
      status = "Session credentials cleared";
      render();
    } else if (action === "import-credentials") {
      document.querySelector<HTMLInputElement>("#credential-import")?.click();
    } else if (action === "toggle-password") {
      const account = button.dataset.account ?? "";
      if (revealedAccounts.has(account)) revealedAccounts.delete(account);
      else revealedAccounts.add(account);
      render();
    } else if (action === "export") {
      exportWorkspaces();
    } else if (action === "import") {
      document.querySelector<HTMLInputElement>("#workspace-import")?.click();
    } else if (action === "show-logs") {
      await showLogs();
    }
  } catch (error) {
    status = error instanceof Error ? `Error: ${error.message}` : "Unexpected error";
    busy = false;
    render();
  }
});

app.addEventListener("input", (event) => {
  const input = event.target as HTMLInputElement;
  const field = input.dataset.field;
  if (!field) return;
  if (field === "setting") {
    handleSettingInput(input);
    return;
  }
  const workspace = selectedWorkspace();
  if (!workspace) return;

  if (field === "workspace-name") workspace.name = input.value;
  if (field === "jump-host") workspace.jumpHost = input.value.trim() || null;
  if (field.startsWith("camera-")) {
    const camera = workspace.cameras.find((item) => item.id === input.dataset.id);
    if (!camera) return;
    if (field === "camera-name") camera.name = input.value;
    if (field === "camera-host") camera.host = input.value.trim();
    if (field === "camera-username") camera.username = input.value.trim();
    if (field === "camera-port") camera.port = Math.max(1, Math.min(65535, Number(input.value) || 8888));
  }
  if (field === "credential") credentials[input.dataset.account ?? ""] = input.value;
  saveWorkspaces();
});

app.addEventListener("change", async (event) => {
  const input = event.target as HTMLInputElement;
  if (!input.files?.[0]) return;
  if (input.id === "credential-import") {
    const file = input.files[0];
    try {
      const result = await importCredentialFile(file, workspaces);
      const { credentials: importedCredentials, ...summary } = result;
      credentials = { ...credentials, ...importedCredentials };
      credentialImportSummary = { ...summary, filename: file.name };
      status = result.importedAccounts.length
        ? `Imported ${result.importedAccounts.length} session credentials from ${file.name}`
        : `No matching credentials found in ${file.name}`;
    } catch (error) {
      credentialImportSummary = null;
      status = `Credential import failed: ${error instanceof Error ? error.message : "invalid file"}`;
    }
    input.value = "";
    render();
    return;
  }
  if (input.id !== "workspace-import") return;
  try {
    workspaces = normalizeWorkspaces(JSON.parse(await input.files[0].text()));
    if (workspaces.length === 0) throw new Error("Workspace file is empty.");
    selectedId = workspaces[0]!.id;
    view = "workspace";
    saveWorkspaces();
    status = `Imported ${workspaces.length} workspaces`;
  } catch (error) {
    status = `Import failed: ${error instanceof Error ? error.message : "invalid file"}`;
  }
  input.value = "";
  render();
});

window.addEventListener("beforeunload", () => {
  if (session) void fetch(`/api/sessions/${encodeURIComponent(session.id)}`, { method: "DELETE", keepalive: true });
});

function render(): void {
  const workspace = selectedWorkspace();
  const isStreaming = Boolean(session?.streaming);
  app.innerHTML = `
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand-row">
          <div class="app-mark" aria-hidden="true"><span></span></div>
          <strong>Camera Stream</strong>
          <button class="icon-button add-workspace" data-action="add-workspace" aria-label="Add workspace" title="Add workspace">+</button>
        </div>
        <nav class="workspace-list" aria-label="Workspaces">
          ${workspaces.map((item) => `
            <div class="workspace-row ${item.id === selectedId && view !== "settings" ? "selected" : ""}">
              <button class="workspace-select" data-action="select-workspace" data-id="${attribute(item.id)}">
                <span class="camera-dot" aria-hidden="true"></span><span>${html(item.name || "Untitled workspace")}</span>
              </button>
              <button class="row-action" data-action="rename-workspace" data-id="${attribute(item.id)}" title="Rename">✎</button>
              <button class="row-action danger-icon" data-action="delete-workspace" data-id="${attribute(item.id)}" title="Delete">−</button>
            </div>`).join("")}
        </nav>
        <div class="sidebar-tools">
          <button data-action="import">Import workspaces</button>
          <button data-action="export">Export workspaces</button>
        </div>
        <button class="settings-button ${view === "settings" ? "selected" : ""}" data-action="settings"><span>⚙</span> Settings</button>
      </aside>
      <main class="content">
        ${renderHeader(workspace, isStreaming)}
        <section class="content-body">
          ${view === "settings" ? renderSettings() : !workspace ? renderEmpty() : isStreaming || view === "stream" ? renderStreams() : renderEditor(workspace)}
        </section>
        <footer class="status-bar">
          <span class="status-light ${busy ? "working" : isStreaming ? "live" : ""}"></span>
          <span id="status-text">${html(status)}</span>
          ${session ? `<button data-action="show-logs">Connection log</button>` : ""}
          <span class="local-badge">Local gateway</span>
        </footer>
      </main>
    </div>
    <input id="workspace-import" type="file" accept="application/json,.json" hidden />
    <input id="credential-import" type="file" accept=".json,.yaml,.yml,.csv,.tsv,.xlsx,application/json,text/csv,text/tab-separated-values,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" hidden />
    ${credentialIntent && workspace ? renderCredentialModal(workspace) : ""}
    ${terminalOpen && session ? renderTerminalModal(session) : ""}
  `;

  if (terminalOpen && session) queueMicrotask(() => mountTerminals(session!));
}

function renderHeader(workspace: CameraWorkspace | undefined, isStreaming: boolean): string {
  const title = view === "settings" ? "Settings" : isStreaming ? "Live cameras" : workspace?.name || "Camera Stream";
  return `
    <header class="toolbar">
      <div>
        <h1>${html(title)}</h1>
        ${workspace && view !== "settings" ? `<p>${workspace.cameras.length} ${workspace.cameras.length === 1 ? "camera" : "cameras"}${workspace.jumpHost ? ` · via ${html(workspace.jumpHost)}` : " · direct connection"}</p>` : `<p>Browser client and session preferences</p>`}
      </div>
      <div class="toolbar-actions">
        ${view === "settings" ? `<button data-action="workspace" ${!workspace ? "disabled" : ""}>Done</button>` : `
          <button data-action="shell" ${busy || !workspace?.cameras.length ? "disabled" : ""}>Open cluster shell</button>
          <button class="primary" data-action="start" ${busy || isStreaming || !workspace?.cameras.length ? "disabled" : ""}>${busy ? "Connecting…" : "Start streaming"}</button>
          <button class="danger" data-action="stop" ${!session || busy ? "disabled" : ""}>Stop</button>
        `}
      </div>
    </header>`;
}

function renderEditor(workspace: CameraWorkspace): string {
  return `
    <div class="editor">
      <div class="form-section identity-fields">
        <label>Workspace name<input data-field="workspace-name" value="${attribute(workspace.name)}" placeholder="Workspace name" /></label>
        <label>Jump host <span>optional</span><input data-field="jump-host" value="${attribute(workspace.jumpHost ?? "")}" placeholder="user@jump.example" /></label>
      </div>
      <div class="section-heading"><div><h2>Cameras</h2><p>Each camera runs its own encoder and SSH connection.</p></div><button data-action="add-camera">+ Add camera</button></div>
      <div class="camera-table">
        <div class="camera-table-head"><span>Camera name</span><span>IP address or host</span><span>Username</span><span>Base port</span><span></span></div>
        ${workspace.cameras.length ? workspace.cameras.map((camera) => `
          <div class="camera-table-row">
            <input data-field="camera-name" data-id="${attribute(camera.id)}" value="${attribute(camera.name)}" aria-label="Camera name" />
            <input data-field="camera-host" data-id="${attribute(camera.id)}" value="${attribute(camera.host)}" placeholder="192.0.2.10" aria-label="Camera host" />
            <input data-field="camera-username" data-id="${attribute(camera.id)}" value="${attribute(camera.username)}" aria-label="SSH username" />
            <input data-field="camera-port" data-id="${attribute(camera.id)}" value="${camera.port}" type="number" min="1" max="65535" aria-label="Base stream port" />
            <button class="remove-camera" data-action="remove-camera" data-id="${attribute(camera.id)}" aria-label="Remove ${attribute(camera.name)}">−</button>
          </div>`).join("") : `<div class="empty-table"><div class="empty-camera-icon">◎</div><strong>No cameras yet</strong><span>Add a Raspberry Pi camera to this workspace.</span></div>`}
      </div>
      <div class="connection-note"><span>↗</span><div><strong>Connection route</strong><p>${workspace.jumpHost ? `Browser → local gateway → ${html(workspace.jumpHost)} → each reachable camera` : "Browser → local gateway → each camera directly"}</p></div></div>
    </div>`;
}

function renderStreams(): string {
  if (!session) return `<div class="center-message"><div class="spinner"></div><h2>Preparing camera connections</h2><p>The gateway is authenticating and starting reachable encoders.</p></div>`;
  const activeSession = session;
  return `
    <div class="stream-page">
      <div class="stream-summary"><span class="live-pill"><i></i> LIVE</span><span>${activeSession.cameras.length}/${activeSession.cameras.length + activeSession.unavailable.length} cameras connected${activeSession.jumpHost ? ` through ${html(activeSession.jumpHost)}` : ""}</span></div>
      <div class="stream-grid">
        ${activeSession.cameras.map((camera) => `
          <article class="stream-card">
            <video id="video-${attribute(camera.id)}" src="${attribute(streamUrl(activeSession.id, camera.id))}" autoplay muted playsinline></video>
            <div class="stream-label">
              <div><strong>${html(camera.name)}</strong><span>${html(camera.host)}:${camera.remotePort}</span></div>
              <div class="stream-actions">
                <span class="connected">Connected</span>
                <button class="stream-adjust ${settingsCameraId === camera.id ? "active" : ""}" data-action="open-settings" data-id="${attribute(camera.id)}" title="Adjust capture settings" aria-label="Adjust capture settings for ${attribute(camera.name)}">⚙ Adjust</button>
              </div>
            </div>
            ${settingsCameraId === camera.id ? renderCapturePanel(camera) : ""}
          </article>`).join("")}
      </div>
      ${activeSession.unavailable.length ? `<section class="unavailable"><h2>Unavailable cameras</h2>${activeSession.unavailable.map((camera) => `<div><span>${html(camera.name)}</span><small>${html(camera.reason)}</small></div>`).join("")}</section>` : ""}
    </div>`;
}

function renderCapturePanel(camera: CameraStatus): string {
  const draft = settingsDraft ?? sanitizeCaptureSettings(camera.settings);
  return `
    <div class="capture-panel" data-settings-panel="${attribute(camera.id)}">
      <div class="capture-panel-head"><strong>Capture settings</strong><button class="capture-close" data-action="close-settings" aria-label="Close capture settings">✕</button></div>
      <div class="capture-fields">
        ${captureFields.map((cfield) => {
          const value = draft[cfield.key];
          return `<div class="capture-field">
            <span class="capture-field-name">${html(cfield.label)}${cfield.hint ? ` <em>${html(cfield.hint)}</em>` : ""}</span>
            <span class="capture-field-controls">
              <input type="range" data-field="setting" data-key="${cfield.key}" min="${cfield.min}" max="${cfield.max}" step="${cfield.step}" value="${value}" aria-label="${html(cfield.label)}" />
              <input type="number" class="capture-number" data-field="setting" data-key="${cfield.key}" min="${cfield.min}" max="${cfield.max}" step="${cfield.step}" value="${value}" aria-label="${html(cfield.label)} value" />
              <span class="capture-value" data-value="${cfield.key}">${html(formatSettingValue(cfield.key, value))}</span>
            </span>
          </div>`;
        }).join("")}
      </div>
      <div class="capture-panel-actions">
        <button data-action="reset-settings" ${busy ? "disabled" : ""}>Reset to defaults</button>
        <button class="primary" data-action="apply-settings" ${busy ? "disabled" : ""}>${busy ? "Applying…" : "Apply"}</button>
      </div>
      <p class="capture-note">Applying relaunches this camera's encoder, so its video reconnects for a moment.</p>
    </div>`;
}

function openCameraSettings(cameraId: string): void {
  if (!session) return;
  if (settingsCameraId === cameraId) {
    settingsCameraId = null;
    settingsDraft = null;
    render();
    return;
  }
  const camera = session.cameras.find((item) => item.id === cameraId);
  if (!camera) return;
  settingsCameraId = cameraId;
  settingsDraft = sanitizeCaptureSettings(camera.settings);
  render();
}

function handleSettingInput(input: HTMLInputElement): void {
  if (!settingsDraft) return;
  const key = input.dataset.key as keyof CaptureSettings | undefined;
  if (!key) return;
  const cfield = captureFields.find((item) => item.key === key);
  if (!cfield) return;
  let value = Number(input.value);
  if (!Number.isFinite(value)) return;
  value = Math.min(cfield.max, Math.max(cfield.min, value));
  if (key === "shutterMicroseconds" || key === "framerate") value = Math.round(value);
  settingsDraft[key] = value;
  syncSettingInputs(key, value, input);
}

function syncSettingInputs(key: keyof CaptureSettings, value: number, source: HTMLInputElement): void {
  if (!settingsCameraId) return;
  const scope = document.querySelector(`[data-settings-panel="${settingsCameraId}"]`);
  if (!scope) return;
  scope.querySelectorAll<HTMLInputElement>(`input[data-key="${key}"]`).forEach((element) => {
    if (element !== source && element.value !== String(value)) element.value = String(value);
  });
  const label = scope.querySelector(`[data-value="${key}"]`);
  if (label) label.textContent = formatSettingValue(key, value);
}

function formatSettingValue(key: keyof CaptureSettings, value: number): string {
  if (key === "shutterMicroseconds") return value === 0 ? "auto" : `${value}`;
  if (key === "framerate") return `${value}`;
  return value.toFixed(2);
}

async function applyActiveSettings(): Promise<void> {
  if (!session || !settingsCameraId || !settingsDraft) return;
  const activeSession = session;
  const cameraId = settingsCameraId;
  const draft = sanitizeCaptureSettings(settingsDraft);
  // Apply without a full re-render so only the adjusted camera reconnects; the
  // other live streams keep playing.
  const applyButton = document.querySelector<HTMLButtonElement>(`[data-settings-panel="${cameraId}"] [data-action="apply-settings"]`);
  if (applyButton) {
    applyButton.disabled = true;
    applyButton.textContent = "Applying…";
  }
  setStatus("Applying capture settings…");
  try {
    const { settings } = await applyCameraSettings(activeSession.id, cameraId, draft);
    const camera = activeSession.cameras.find((item) => item.id === cameraId);
    if (camera) camera.settings = settings;
    if (settingsCameraId === cameraId) settingsDraft = settings;
    reloadCameraVideo(activeSession.id, cameraId);
    setStatus("Capture settings applied");
  } catch (error) {
    setStatus(`Error: ${error instanceof Error ? error.message : "could not apply settings"}`);
  } finally {
    if (applyButton) {
      applyButton.disabled = false;
      applyButton.textContent = "Apply";
    }
  }
}

function setStatus(message: string): void {
  status = message;
  const element = document.querySelector("#status-text");
  if (element) element.textContent = message;
}

function reloadCameraVideo(sessionId: string, cameraId: string): void {
  const video = document.querySelector<HTMLVideoElement>(`#video-${cameraId}`);
  if (!video) return;
  // A fresh query string forces the browser to reopen the stream and the
  // gateway to reconnect to the relaunched encoder.
  video.src = `${streamUrl(sessionId, cameraId)}?t=${Date.now()}`;
  video.load();
}

function renderSettings(): string {
  const accounts = uniqueAccounts();
  return `
    <div class="settings-page">
      <section><div class="settings-heading"><h2>Session credentials</h2><button data-action="import-credentials">Import credentials…</button></div><p>Passwords remain in browser memory and are discarded when this tab closes. Import JSON, YAML, CSV, TSV, or XLSX files; values are matched to workspace names or SSH accounts.</p>
        ${renderCredentialImportSummary()}
        <div class="credential-list">
          ${accounts.length ? accounts.map(({ label, account }) => `
            <label><span><strong>${html(label)}</strong><small>${html(account)}</small></span><span class="password-control"><input data-field="credential" data-account="${attribute(account)}" type="${revealedAccounts.has(account) ? "text" : "password"}" value="${attribute(credentials[account] ?? "")}" placeholder="Password" autocomplete="off" /><button data-action="toggle-password" data-account="${attribute(account)}" aria-label="Show or hide password">${revealedAccounts.has(account) ? "Hide" : "Show"}</button></span></label>`).join("") : `<div class="settings-empty">Add a workspace camera to manage its credentials.</div>`}
        </div>
        <button class="danger" data-action="clear-credentials" ${accounts.length ? "" : "disabled"}>Clear all session credentials</button>
      </section>
      <section><h2>Data and privacy</h2><p>Workspace names and hosts are stored in this browser profile. Passwords are never placed in local storage or the connection log.</p><div class="settings-actions"><button data-action="import">Import JSON</button><button data-action="export">Export JSON</button></div></section>
      <section><h2>Streaming runtime</h2><p>The local gateway uses SSH2 for camera control and its bundled FFmpeg executable to convert Annex-B H.264 into fragmented MP4 for the browser.</p><span class="runtime-ok">● Gateway connected on this computer</span></section>
    </div>`;
}

function renderEmpty(): string {
  return `<div class="center-message"><div class="empty-camera-icon">◎</div><h2>Select a workspace</h2><p>Choose one from the sidebar or create a new workspace.</p></div>`;
}

function renderCredentialModal(workspace: CameraWorkspace): string {
  const cameraAccounts = workspace.cameras.map((camera) => `${camera.username}@${camera.host}`);
  const hasCameraPasswords = cameraAccounts.every((account) => Boolean(credentials[account]));
  const hasJumpPassword = !workspace.jumpHost || Boolean(credentials[workspace.jumpHost]);
  return `
    <div class="modal-backdrop" role="presentation">
      <section class="modal credentials-modal" role="dialog" aria-modal="true" aria-labelledby="credentials-title">
        <div class="modal-icon">⌁</div><h2 id="credentials-title">Credentials for ${html(workspace.name)}</h2>
        <p>Passwords are used only for this local session and discarded when the tab closes.</p>
        <button class="file-import-button" data-action="import-credentials">Import JSON, YAML, CSV, TSV, or XLSX…</button>
        ${renderCredentialImportSummary()}
        <label>Shared camera password<input id="camera-password" type="password" placeholder="${hasCameraPasswords ? "Already set — leave blank to keep" : "Required"}" autocomplete="off" /></label>
        ${workspace.jumpHost ? `<label>Jump host password <span>${html(workspace.jumpHost)}</span><input id="jump-password" type="password" placeholder="${hasJumpPassword ? "Already set — leave blank to keep" : "Required"}" autocomplete="off" /></label>` : ""}
        <div class="modal-actions"><button data-action="cancel-credentials">Cancel</button><button class="primary" data-action="submit-credentials">${credentialIntent === "shell" ? "Open shell" : "Start"}</button></div>
      </section>
    </div>`;
}

function renderCredentialImportSummary(): string {
  if (!credentialImportSummary) return "";
  const unmatched = credentialImportSummary.unmatchedEntries;
  return `<div class="import-summary ${credentialImportSummary.importedAccounts.length ? "success" : "warning"}">
    <strong>${credentialImportSummary.importedAccounts.length} credentials matched</strong>
    <span>${html(credentialImportSummary.filename)} · ${credentialImportSummary.processedRows} rows processed${unmatched.length ? ` · ${unmatched.length} unmatched` : ""}</span>
    ${unmatched.length ? `<small>${unmatched.slice(0, 3).map(html).join(" · ")}${unmatched.length > 3 ? ` · +${unmatched.length - 3} more` : ""}</small>` : ""}
  </div>`;
}

function renderTerminalModal(activeSession: SessionStatus): string {
  return `
    <div class="terminal-overlay" role="dialog" aria-modal="true" aria-label="Cluster shell">
      <header><div><strong>Cluster shell</strong><span>${activeSession.cameras.length} connected cameras</span></div><button data-action="close-terminal">Done</button></header>
      <div id="terminal-grid" class="terminal-grid"></div>
    </div>`;
}

async function requestIntent(intent: PendingIntent): Promise<void> {
  const workspace = selectedWorkspace();
  if (!workspace || workspace.cameras.length === 0) return;
  const missing = requiredAccounts(workspace).filter((account) => !credentials[account]);
  if (missing.length) {
    credentialIntent = intent;
    render();
    queueMicrotask(() => document.querySelector<HTMLInputElement>("#camera-password")?.focus());
    return;
  }
  await beginSession(intent);
}

async function submitCredentials(): Promise<void> {
  const workspace = selectedWorkspace();
  const intent = credentialIntent;
  if (!workspace || !intent) return;
  const cameraPassword = document.querySelector<HTMLInputElement>("#camera-password")?.value ?? "";
  const jumpPassword = document.querySelector<HTMLInputElement>("#jump-password")?.value ?? "";
  if (cameraPassword) {
    for (const camera of workspace.cameras) credentials[`${camera.username}@${camera.host}`] = cameraPassword;
  }
  if (workspace.jumpHost && jumpPassword) credentials[workspace.jumpHost] = jumpPassword;
  const missing = requiredAccounts(workspace).filter((account) => !credentials[account]);
  if (missing.length) {
    status = `Password required for ${missing[0]}`;
    render();
    return;
  }
  credentialIntent = null;
  await beginSession(intent);
}

async function beginSession(intent: PendingIntent): Promise<void> {
  const workspace = selectedWorkspace();
  if (!workspace) return;
  if (session) await stopSession(session.id).catch(() => undefined);
  session = null;
  settingsCameraId = null;
  settingsDraft = null;
  busy = true;
  status = workspace.jumpHost ? `Connecting to jump host ${workspace.jumpHost}…` : `Connecting to ${workspace.cameras.length} cameras…`;
  if (intent === "stream") view = "stream";
  render();
  try {
    session = await createSession(workspace, credentials, intent === "stream");
    busy = false;
    status = `${session.cameras.length}/${workspace.cameras.length} cameras connected${workspace.jumpHost ? ` via ${workspace.jumpHost}` : ""}`;
    if (intent === "stream") view = "stream";
    render();
    if (intent === "shell") openTerminal();
  } catch (error) {
    session = null;
    busy = false;
    view = "workspace";
    status = `Error: ${error instanceof Error ? error.message : "connection failed"}`;
    render();
  }
}

async function stopActiveSession(): Promise<void> {
  if (!session) return;
  const closing = session;
  session = null;
  settingsCameraId = null;
  settingsDraft = null;
  busy = true;
  status = "Stopping camera encoders…";
  terminalOpen = false;
  disposeTerminals();
  render();
  await stopSession(closing.id).catch(() => undefined);
  busy = false;
  view = "workspace";
  status = "Stopped";
  render();
}

function openTerminal(): void {
  if (!session) return;
  terminalOpen = true;
  render();
}

async function deleteWorkspace(id: string): Promise<void> {
  const workspace = workspaces.find((item) => item.id === id);
  if (!workspace || !window.confirm(`Delete “${workspace.name}”? This cannot be undone.`)) return;
  if (session && id === selectedId) await stopActiveSession();
  workspaces = workspaces.filter((item) => item.id !== id);
  selectedId = workspaces[0]?.id ?? "";
  saveWorkspaces();
  render();
}

async function showLogs(): Promise<void> {
  if (!session) return;
  const current = session;
  const refreshed = await getSession(current.id).catch(() => current);
  if (session?.id === current.id) session = refreshed;
  window.alert(refreshed.logs.length ? refreshed.logs.join("\n") : "No connection log entries yet.");
}

function exportWorkspaces(): void {
  const blob = new Blob([JSON.stringify(workspaces, null, 2)], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "camera-stream-workspaces.json";
  link.click();
  URL.revokeObjectURL(link.href);
  status = `Exported ${workspaces.length} workspaces`;
  render();
}

function selectedWorkspace(): CameraWorkspace | undefined {
  return workspaces.find((workspace) => workspace.id === selectedId);
}

function requiredAccounts(workspace: CameraWorkspace): string[] {
  return [...workspace.cameras.map((camera) => `${camera.username}@${camera.host}`), ...(workspace.jumpHost ? [workspace.jumpHost] : [])];
}

function uniqueAccounts(): Array<{ label: string; account: string }> {
  const result = new Map<string, string>();
  for (const workspace of workspaces) {
    for (const camera of workspace.cameras) result.set(`${camera.username}@${camera.host}`, `${workspace.name} · ${camera.name}`);
    if (workspace.jumpHost) result.set(workspace.jumpHost, `${workspace.name} · Jump host`);
  }
  return [...result].map(([account, label]) => ({ account, label }));
}

function loadWorkspaces(): CameraWorkspace[] {
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved) {
      const loaded = normalizeWorkspaces(JSON.parse(saved));
      if (loaded.length) return loaded;
    }
  } catch {
    // Fall back to a safe example if local data is malformed.
  }
  return [exampleWorkspace()];
}

function saveWorkspaces(): void {
  localStorage.setItem(storageKey, JSON.stringify(workspaces));
}

function html(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", "\"": "&quot;" })[character] ?? character);
}

function attribute(value: string): string {
  return html(value).replace(/`/g, "&#96;");
}
