export interface CameraEndpoint {
  id: string;
  name: string;
  host: string;
  username: string;
  port: number;
}

export interface CameraWorkspace {
  id: string;
  name: string;
  cameras: CameraEndpoint[];
  jumpHost?: string | null;
}

export interface SshTarget {
  account: string;
  host: string;
  port: number;
  username: string;
}

export interface SessionRequest {
  workspace: CameraWorkspace;
  credentials: Record<string, string>;
  startEncoders?: boolean;
}

const hostnamePattern = /^[A-Za-z0-9._:-]+$/;
const usernamePattern = /^[A-Za-z0-9._-]+$/;

export function parseSshTarget(value: string, fallbackUsername?: string): SshTarget {
  const trimmed = value.trim();
  const at = trimmed.lastIndexOf("@");
  const username = at >= 0 ? trimmed.slice(0, at) : fallbackUsername ?? "";
  let hostPart = at >= 0 ? trimmed.slice(at + 1) : trimmed;
  let port = 22;

  if (hostPart.startsWith("[")) {
    const closing = hostPart.indexOf("]");
    if (closing < 0) throw new Error("Invalid bracketed SSH host.");
    const suffix = hostPart.slice(closing + 1);
    if (suffix) {
      if (!suffix.startsWith(":")) throw new Error("Invalid SSH host port.");
      port = Number(suffix.slice(1));
    }
    hostPart = hostPart.slice(1, closing);
  } else {
    const colon = hostPart.lastIndexOf(":");
    if (colon > 0 && hostPart.indexOf(":") === colon) {
      const possiblePort = hostPart.slice(colon + 1);
      if (/^\d+$/.test(possiblePort)) {
        port = Number(possiblePort);
        hostPart = hostPart.slice(0, colon);
      }
    }
  }

  if (!usernamePattern.test(username)) throw new Error("SSH usernames may contain only letters, numbers, dots, underscores, and hyphens.");
  if (!hostnamePattern.test(hostPart)) throw new Error("SSH host contains unsupported characters.");
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("SSH port must be between 1 and 65535.");

  return { account: trimmed, host: hostPart, port, username };
}

export function validateSessionRequest(value: unknown): SessionRequest {
  if (!value || typeof value !== "object") throw new Error("Request body must be an object.");
  const candidate = value as Partial<SessionRequest>;
  const workspace = candidate.workspace;
  if (!workspace || typeof workspace !== "object") throw new Error("Workspace is required.");
  if (typeof workspace.id !== "string" || typeof workspace.name !== "string" || !workspace.name.trim()) {
    throw new Error("Workspace id and name are required.");
  }
  if (!Array.isArray(workspace.cameras) || workspace.cameras.length === 0) {
    throw new Error("Add at least one camera.");
  }

  for (const camera of workspace.cameras) {
    if (!camera || typeof camera !== "object") throw new Error("Each camera must be an object.");
    if (typeof camera.id !== "string" || typeof camera.name !== "string" || !camera.name.trim()) {
      throw new Error("Each camera needs an id and name.");
    }
    if (typeof camera.host !== "string" || !hostnamePattern.test(camera.host)) {
      throw new Error(`${camera.name || "Camera"} has an invalid host.`);
    }
    if (typeof camera.username !== "string" || !usernamePattern.test(camera.username)) {
      throw new Error(`${camera.name || "Camera"} has an invalid username.`);
    }
  }

  if (workspace.jumpHost) parseSshTarget(workspace.jumpHost);
  if (!candidate.credentials || typeof candidate.credentials !== "object" || Array.isArray(candidate.credentials)) {
    throw new Error("Credentials are required.");
  }

  const credentials: Record<string, string> = {};
  for (const [account, password] of Object.entries(candidate.credentials)) {
    if (typeof password === "string" && password.length > 0) credentials[account] = password;
  }

  return {
    workspace: {
      ...workspace,
      name: workspace.name.trim(),
      cameras: workspace.cameras.map((camera) => ({
        id: camera.id,
        name: camera.name.trim(),
        host: camera.host.trim(),
        username: camera.username.trim(),
        port: Number.isInteger(camera.port) && camera.port > 0 && camera.port <= 65535 ? camera.port : 8888,
      })),
      jumpHost: workspace.jumpHost?.trim() || null,
    },
    credentials,
    startEncoders: candidate.startEncoders !== false,
  };
}
