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
