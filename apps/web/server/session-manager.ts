import { randomUUID } from "node:crypto";
import net from "node:net";
import { Client, type ClientChannel, type ConnectConfig } from "ssh2";
import {
  type CaptureSettings,
  defaultCaptureSettings,
  libcameraArguments,
  raspividArguments,
  sanitizeCaptureSettings,
} from "./capture-settings.js";
import type { CameraEndpoint, CameraWorkspace, SessionRequest } from "./models.js";
import { parseSshTarget } from "./models.js";

const stopCommand = "pkill -x libcamera-vid 2>/dev/null; pkill -x rpicam-vid 2>/dev/null; pkill -x raspivid 2>/dev/null; true";
const nameCommand = "boxid=$(printenv BOXID 2>/dev/null || true); if [ -n \"$boxid\" ]; then printf '%s' \"$boxid\"; else hostname; fi";

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

interface CameraRuntime extends CameraStatus {
  endpoint: CameraEndpoint;
  ssh: Client;
}

interface RuntimeSession {
  id: string;
  workspace: CameraWorkspace;
  jump: Client | null;
  cameras: Map<string, CameraRuntime>;
  unavailable: SessionStatus["unavailable"];
  logs: string[];
  streaming: boolean;
}

export class SessionManager {
  private readonly sessions = new Map<string, RuntimeSession>();

  async create(request: SessionRequest): Promise<SessionStatus> {
    const session: RuntimeSession = {
      id: randomUUID(),
      workspace: request.workspace,
      jump: null,
      cameras: new Map(),
      unavailable: [],
      logs: [],
      streaming: request.startEncoders !== false,
    };
    this.sessions.set(session.id, session);

    try {
      if (request.workspace.jumpHost) {
        this.log(session, `Connecting to jump host ${request.workspace.jumpHost}…`);
        const target = parseSshTarget(request.workspace.jumpHost);
        const password = request.credentials[request.workspace.jumpHost];
        if (!password) throw new Error(`Password is missing for jump host ${request.workspace.jumpHost}.`);
        session.jump = await connectSsh({
          host: target.host,
          port: target.port,
          username: target.username,
          password,
        });
        this.log(session, `Authenticated SSH connection established to jump host ${request.workspace.jumpHost}.`);
      }

      const results = await Promise.allSettled(request.workspace.cameras.map((camera, index) =>
        this.connectCamera(session, camera, index, request.credentials, request.startEncoders !== false),
      ));

      results.forEach((result, index) => {
        if (result.status === "rejected") {
          const camera = request.workspace.cameras[index];
          if (!camera) return;
          const reason = safeMessage(result.reason);
          session.unavailable.push({ id: camera.id, name: camera.name, reason });
          this.log(session, `${camera.name} (${camera.username}@${camera.host}) unavailable: ${reason}`);
        }
      });

      if (session.cameras.size === 0) {
        throw new Error(session.jump
          ? "Jump host connected, but no cameras accepted SSH connections."
          : "No cameras accepted SSH connections.");
      }

      this.log(session, `${session.cameras.size}/${request.workspace.cameras.length} cameras connected.`);
      return this.status(session.id);
    } catch (error) {
      await this.stop(session.id);
      throw error;
    }
  }

  status(id: string): SessionStatus {
    const session = this.requireSession(id);
    return {
      id: session.id,
      workspaceName: session.workspace.name,
      jumpHost: session.workspace.jumpHost ?? null,
      streaming: session.streaming,
      cameras: [...session.cameras.values()].map(({ id: cameraId, name, host, remotePort, settings }) => ({
        id: cameraId,
        name,
        host,
        remotePort,
        settings,
      })),
      unavailable: session.unavailable,
      logs: session.logs,
    };
  }

  getCamera(sessionId: string, cameraId: string): CameraRuntime {
    const camera = this.requireSession(sessionId).cameras.get(cameraId);
    if (!camera) throw new Error("Camera is not available in this session.");
    return camera;
  }

  async openVideoSource(sessionId: string, cameraId: string): Promise<NodeJS.ReadWriteStream> {
    const session = this.requireSession(sessionId);
    const camera = this.getCamera(sessionId, cameraId);
    if (!session.streaming) throw new Error("This is a shell-only session.");

    let lastError: unknown;
    for (let attempt = 0; attempt < 12; attempt += 1) {
      try {
        const stream = session.jump
          ? await forwardOut(session.jump, camera.endpoint.host, camera.remotePort)
          : await connectTcp(camera.endpoint.host, camera.remotePort);
        this.log(session, `Video stream connected for ${camera.name}.`);
        return stream;
      } catch (error) {
        lastError = error;
        await delay(500);
      }
    }
    throw new Error(`Encoder stream did not become available: ${safeMessage(lastError)}`);
  }

  /**
   * Relaunch a single camera's encoder with new capture settings. The Pi camera
   * stack has no live control channel, so applying settings kills and restarts
   * that camera's encoder only; the browser reconnects its video element after.
   */
  async applySettings(sessionId: string, cameraId: string, settings: CaptureSettings): Promise<CaptureSettings> {
    const session = this.requireSession(sessionId);
    const camera = this.getCamera(sessionId, cameraId);
    if (!session.streaming) throw new Error("This is a shell-only session.");
    const sanitized = sanitizeCaptureSettings(settings);
    await execute(camera.ssh, launchCommand(camera.remotePort, sanitized), 10_000);
    camera.settings = sanitized;
    this.log(session, `Applied capture settings to ${camera.name}; encoder relaunched on port ${camera.remotePort}.`);
    return sanitized;
  }

  async openShell(sessionId: string, cameraId: string, columns = 100, rows = 30): Promise<ClientChannel> {
    const camera = this.getCamera(sessionId, cameraId);
    return new Promise((resolve, reject) => {
      camera.ssh.shell({ term: "xterm-256color", cols: columns, rows }, (error, channel) => {
        if (error) reject(error);
        else resolve(channel);
      });
    });
  }

  async stop(id: string): Promise<void> {
    const session = this.sessions.get(id);
    if (!session) return;
    this.sessions.delete(id);

    await Promise.allSettled([...session.cameras.values()].map(async (camera) => {
      if (session.streaming) {
        try {
          await execute(camera.ssh, stopCommand, 8_000);
        } catch (error) {
          this.log(session, `Could not stop ${camera.name}: ${safeMessage(error)}`);
        }
      }
      camera.ssh.end();
    }));
    session.jump?.end();
  }

  async stopAll(): Promise<void> {
    await Promise.allSettled([...this.sessions.keys()].map((id) => this.stop(id)));
  }

  private async connectCamera(
    session: RuntimeSession,
    camera: CameraEndpoint,
    index: number,
    credentials: Record<string, string>,
    startEncoder: boolean,
  ): Promise<void> {
    const account = `${camera.username}@${camera.host}`;
    const password = credentials[account];
    if (!password) throw new Error(`Password is missing for ${account}.`);

    this.log(session, `Connecting to ${camera.name} (${account})${session.jump ? " through jump host" : ""}…`);
    const socket = session.jump ? await forwardOut(session.jump, camera.host, 22) : undefined;
    const ssh = await connectSsh({
      host: camera.host,
      port: 22,
      username: camera.username,
      password,
      sock: socket,
    });

    try {
      const configuredBasePort = Number.isInteger(camera.port) ? camera.port : 8888;
      const remotePort = configuredBasePort + index;
      if (remotePort > 65_535) throw new Error(`Stream port ${remotePort} is outside the valid TCP port range.`);
      let resolvedName = camera.name;
      try {
        const discovered = (await execute(ssh, nameCommand, 6_000)).trim();
        if (discovered) resolvedName = discovered;
      } catch {
        // A hostname is helpful but not required to stream.
      }

      const settings = camera.settings ? sanitizeCaptureSettings(camera.settings) : { ...defaultCaptureSettings };
      if (startEncoder) {
        await execute(ssh, launchCommand(remotePort, settings), 10_000);
        this.log(session, `Encoder started on ${resolvedName} at port ${remotePort}.`);
      } else {
        this.log(session, `Shell connection ready for ${resolvedName}.`);
      }

      session.cameras.set(camera.id, {
        id: camera.id,
        name: resolvedName,
        host: camera.host,
        remotePort,
        settings,
        endpoint: camera,
        ssh,
      });
    } catch (error) {
      ssh.end();
      throw error;
    }
  }

  private requireSession(id: string): RuntimeSession {
    const session = this.sessions.get(id);
    if (!session) throw new Error("Streaming session was not found.");
    return session;
  }

  private log(session: RuntimeSession, message: string): void {
    const entry = `${new Date().toISOString()} ${message}`;
    session.logs.push(entry);
    if (session.logs.length > 200) session.logs.shift();
    console.info(`[camera-stream ${session.id.slice(0, 8)}] ${message}`);
  }
}

function connectSsh(config: ConnectConfig): Promise<Client> {
  return new Promise((resolve, reject) => {
    const client = new Client();
    const timeout = setTimeout(() => {
      client.destroy();
      reject(new Error("SSH connection timed out."));
    }, 10_000);
    let settled = false;

    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      client.destroy();
      reject(error);
    };

    client.once("ready", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(client);
    });
    client.once("error", fail);
    client.on("keyboard-interactive", (_name, _instructions, _language, prompts, finish) => {
      finish(prompts.map(() => config.password ?? ""));
    });
    client.connect({
      ...config,
      readyTimeout: 9_000,
      keepaliveInterval: 15_000,
      keepaliveCountMax: 3,
      tryKeyboard: true,
    });
  });
}

function forwardOut(jump: Client, host: string, port: number): Promise<ClientChannel> {
  return new Promise((resolve, reject) => {
    jump.forwardOut("127.0.0.1", 0, host, port, (error, stream) => {
      if (error) reject(error);
      else resolve(stream);
    });
  });
}

function connectTcp(host: string, port: number): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    socket.setTimeout(5_000);
    socket.once("connect", () => {
      socket.setTimeout(0);
      resolve(socket);
    });
    socket.once("timeout", () => socket.destroy(new Error("TCP connection timed out.")));
    socket.once("error", reject);
  });
}

function execute(client: Client, command: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Remote command timed out.")), timeoutMs);
    client.exec(command, (error, stream) => {
      if (error) {
        clearTimeout(timer);
        reject(error);
        return;
      }
      let stdout = "";
      let stderr = "";
      stream.on("data", (chunk: Buffer) => { stdout += chunk.toString("utf8"); });
      stream.stderr.on("data", (chunk: Buffer) => { stderr += chunk.toString("utf8"); });
      stream.once("close", (code: number | undefined) => {
        clearTimeout(timer);
        if (code === 0 || code === undefined) resolve(stdout);
        else reject(new Error(stderr.trim() || `Remote command exited with status ${code}.`));
      });
      stream.once("error", (streamError: Error) => {
        clearTimeout(timer);
        reject(streamError);
      });
    });
  });
}

function launchCommand(port: number, settings: CaptureSettings): string {
  return `${stopCommand}; `
    + "if command -v rpicam-vid >/dev/null 2>&1; then c=$(command -v rpicam-vid); "
    + "elif command -v libcamera-vid >/dev/null 2>&1; then c=$(command -v libcamera-vid); "
    + "elif command -v raspivid >/dev/null 2>&1; then c=$(command -v raspivid); else exit 127; fi; "
    + `if [ "\${c##*/}" = raspivid ]; then nohup "$c" ${raspividArguments(settings)} -o tcp://0.0.0.0:${port} -t 0 >/tmp/camera-stream.log 2>&1 & `
    + `else nohup "$c" ${libcameraArguments(settings)} -o tcp://0.0.0.0:${port} -t 0 >/tmp/camera-stream.log 2>&1 & fi; `
    + "printf '__CAMERA_STREAM_ENCODER_STARTED__\\n'";
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function safeMessage(error: unknown): string {
  if (error instanceof Error) return error.message.replace(/password=[^\s]+/gi, "password=[redacted]");
  return "Unknown connection error.";
}
