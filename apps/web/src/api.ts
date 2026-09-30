import type { CaptureSettings } from "./capture-settings";
import type { CameraWorkspace, SessionStatus } from "./models";

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({})) as { error?: string };
    throw new Error(body.error || `Request failed (${response.status}).`);
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

export interface BundledProfile {
  workspaces: unknown[];
  credentials: Record<string, string>;
}

export async function getBundledProfile(): Promise<BundledProfile | null> {
  const response = await fetch("/api/profile");
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Bundled profile request failed (${response.status}).`);
  return response.json() as Promise<BundledProfile>;
}

export function createSession(workspace: CameraWorkspace, credentials: Record<string, string>, startEncoders: boolean): Promise<SessionStatus> {
  return request<SessionStatus>("/api/sessions", {
    method: "POST",
    body: JSON.stringify({ workspace, credentials, startEncoders }),
  });
}

export function stopSession(id: string): Promise<void> {
  return request<void>(`/api/sessions/${encodeURIComponent(id)}`, { method: "DELETE" });
}

export function getSession(id: string): Promise<SessionStatus> {
  return request<SessionStatus>(`/api/sessions/${encodeURIComponent(id)}`);
}

export function streamUrl(sessionId: string, cameraId: string): string {
  return `/api/sessions/${encodeURIComponent(sessionId)}/cameras/${encodeURIComponent(cameraId)}/stream.mp4`;
}

export function applyCameraSettings(
  sessionId: string,
  cameraId: string,
  settings: CaptureSettings,
): Promise<{ settings: CaptureSettings }> {
  return request<{ settings: CaptureSettings }>(
    `/api/sessions/${encodeURIComponent(sessionId)}/cameras/${encodeURIComponent(cameraId)}/settings`,
    { method: "PUT", body: JSON.stringify(settings) },
  );
}
