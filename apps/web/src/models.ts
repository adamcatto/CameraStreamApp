import type { CaptureSettings } from "./capture-settings";

export interface CameraEndpoint {
  id: string;
  name: string;
  host: string;
  username: string;
  port: number;
  settings?: CaptureSettings;
}

export interface CameraWorkspace {
  id: string;
  name: string;
  cameras: CameraEndpoint[];
  jumpHost: string | null;
}

export interface CameraStatus {
  id: string;
  name: string;
  host: string;
  remotePort: number;
  settings: CaptureSettings;
}

export interface SessionStatus {
  id: string;
  workspaceName: string;
  jumpHost: string | null;
  streaming: boolean;
  cameras: CameraStatus[];
  unavailable: Array<{ id: string; name: string; reason: string }>;
  logs: string[];
}

export function exampleWorkspace(): CameraWorkspace {
  return {
    id: crypto.randomUUID(),
    name: "Example workspace",
    jumpHost: null,
    cameras: [{
      id: crypto.randomUUID(),
      name: "Camera 1",
      host: "192.0.2.10",
      username: "pi",
      port: 8888,
    }],
  };
}

export function normalizeWorkspaces(value: unknown): CameraWorkspace[] {
  if (!Array.isArray(value)) throw new Error("Workspace file must contain a JSON array.");
  return value.map((item, workspaceIndex) => {
    if (!item || typeof item !== "object") throw new Error(`Workspace ${workspaceIndex + 1} is invalid.`);
    const raw = item as Partial<CameraWorkspace>;
    if (typeof raw.name !== "string" || !raw.name.trim()) throw new Error(`Workspace ${workspaceIndex + 1} needs a name.`);
    if (!Array.isArray(raw.cameras)) throw new Error(`${raw.name} needs a cameras array.`);
    return {
      id: typeof raw.id === "string" ? raw.id : crypto.randomUUID(),
      name: raw.name.trim(),
      jumpHost: typeof raw.jumpHost === "string" && raw.jumpHost.trim() ? raw.jumpHost.trim() : null,
      cameras: raw.cameras.map((camera, cameraIndex) => {
        if (!camera || typeof camera !== "object") throw new Error(`Camera ${cameraIndex + 1} in ${raw.name} is invalid.`);
        const endpoint = camera as Partial<CameraEndpoint>;
        return {
          id: typeof endpoint.id === "string" ? endpoint.id : crypto.randomUUID(),
          name: typeof endpoint.name === "string" && endpoint.name.trim() ? endpoint.name.trim() : `Camera ${cameraIndex + 1}`,
          host: typeof endpoint.host === "string" ? endpoint.host.trim() : "",
          username: typeof endpoint.username === "string" && endpoint.username.trim() ? endpoint.username.trim() : "pi",
          port: Number.isInteger(endpoint.port) && Number(endpoint.port) > 0 ? Number(endpoint.port) : 8888,
        };
      }),
    };
  });
}
