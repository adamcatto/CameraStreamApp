import { spawn } from "node:child_process";
import { createReadStream, existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import ffmpegPath from "ffmpeg-static";
import { WebSocketServer, type WebSocket } from "ws";
import { sanitizeCaptureSettings } from "./capture-settings.js";
import { validateSessionRequest } from "./models.js";
import { SessionManager } from "./session-manager.js";

const appRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const production = process.argv.includes("--production") || process.env.NODE_ENV === "production";
const port = Number(process.env.CAMERA_STREAM_WEB_PORT || 4173);
const host = "127.0.0.1";
const manager = new SessionManager();
const terminalServer = new WebSocketServer({ noServer: true });

let viteMiddleware: ((request: IncomingMessage, response: ServerResponse, next: (error?: unknown) => void) => void) | null = null;

const server = createServer(async (request, response) => {
  try {
    if (request.url?.startsWith("/api/")) {
      await handleApi(request, response);
      return;
    }
    if (viteMiddleware) {
      viteMiddleware(request, response, (error) => {
        if (error) sendError(response, error);
        else if (!response.writableEnded) sendJson(response, 404, { error: "Not found." });
      });
      return;
    }
    await serveStatic(request, response);
  } catch (error) {
    sendError(response, error);
  }
});

server.on("upgrade", (request, socket, head) => {
  const match = request.url?.match(/^\/api\/sessions\/([^/]+)\/cameras\/([^/]+)\/terminal$/);
  if (!match) {
    if (production || request.url?.startsWith("/api/")) socket.destroy();
    return;
  }
  if (!sameOrigin(request)) {
    socket.destroy();
    return;
  }
  terminalServer.handleUpgrade(request, socket, head, (webSocket) => {
    terminalServer.emit("connection", webSocket, request, decodeURIComponent(match[1]!), decodeURIComponent(match[2]!));
  });
});

terminalServer.on("connection", async (webSocket: WebSocket, _request: IncomingMessage, sessionId: string, cameraId: string) => {
  try {
    const shell = await manager.openShell(sessionId, cameraId);
    shell.on("data", (data: Buffer) => {
      if (webSocket.readyState === webSocket.OPEN) webSocket.send(data);
    });
    shell.stderr.on("data", (data: Buffer) => {
      if (webSocket.readyState === webSocket.OPEN) webSocket.send(data);
    });
    shell.once("close", () => webSocket.close());
    shell.once("error", () => webSocket.close());
    webSocket.on("message", (raw) => {
      try {
        const message = JSON.parse(raw.toString()) as { type?: string; data?: string; cols?: number; rows?: number };
        if (message.type === "input" && typeof message.data === "string") shell.write(message.data);
        if (message.type === "resize" && message.cols && message.rows) shell.setWindow(message.rows, message.cols, 0, 0);
      } catch {
        // Ignore malformed terminal messages.
      }
    });
    webSocket.once("close", () => shell.end("exit\n"));
  } catch (error) {
    webSocket.send(`\r\nUnable to open terminal: ${safeMessage(error)}\r\n`);
    webSocket.close();
  }
});

await configureFrontend();
server.listen(port, host, () => {
  console.info(`Camera Stream web app: http://${host}:${port}`);
});

async function configureFrontend(): Promise<void> {
  if (production) return;
  const { createServer: createViteServer } = await import("vite");
  const vite = await createViteServer({
    root: appRoot,
    appType: "spa",
    server: { middlewareMode: true, ws: { server } },
  });
  viteMiddleware = vite.middlewares;
}

async function handleApi(request: IncomingMessage, response: ServerResponse): Promise<void> {
  if (!sameOrigin(request)) {
    sendJson(response, 403, { error: "Requests must come from this local Camera Stream app." });
    return;
  }

  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? `${host}:${port}`}`);
  if (request.method === "GET" && url.pathname === "/api/health") {
    sendJson(response, 200, { ok: true, ffmpeg: Boolean(ffmpegPath) });
    return;
  }
  if (request.method === "POST" && url.pathname === "/api/sessions") {
    const body = await readJsonBody(request);
    const session = await manager.create(validateSessionRequest(body));
    sendJson(response, 201, session);
    return;
  }

  const sessionMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)$/);
  if (sessionMatch && request.method === "GET") {
    sendJson(response, 200, manager.status(decodeURIComponent(sessionMatch[1]!)));
    return;
  }
  if (sessionMatch && request.method === "DELETE") {
    await manager.stop(decodeURIComponent(sessionMatch[1]!));
    response.writeHead(204).end();
    return;
  }

  const streamMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)\/cameras\/([^/]+)\/stream\.mp4$/);
  if (streamMatch && request.method === "GET") {
    await streamCamera(response, decodeURIComponent(streamMatch[1]!), decodeURIComponent(streamMatch[2]!));
    return;
  }

  const settingsMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)\/cameras\/([^/]+)\/settings$/);
  if (settingsMatch && request.method === "PUT") {
    const body = await readJsonBody(request);
    const settings = await manager.applySettings(
      decodeURIComponent(settingsMatch[1]!),
      decodeURIComponent(settingsMatch[2]!),
      sanitizeCaptureSettings(body),
    );
    sendJson(response, 200, { settings });
    return;
  }
  sendJson(response, 404, { error: "Not found." });
}

async function streamCamera(response: ServerResponse, sessionId: string, cameraId: string): Promise<void> {
  if (!ffmpegPath) throw new Error("The bundled FFmpeg executable is unavailable.");
  const source = await manager.openVideoSource(sessionId, cameraId);
  const ffmpeg = spawn(ffmpegPath, [
    "-hide_banner", "-loglevel", "error",
    "-fflags", "+genpts+nobuffer",
    "-r", "30", "-f", "h264", "-i", "pipe:0",
    "-an", "-c:v", "copy",
    "-movflags", "frag_keyframe+empty_moov+default_base_moof",
    "-frag_duration", "500000",
    "-f", "mp4", "pipe:1",
  ], { stdio: ["pipe", "pipe", "pipe"] });

  let ffmpegError = "";
  ffmpeg.stderr.on("data", (chunk: Buffer) => {
    ffmpegError = (ffmpegError + chunk.toString("utf8")).slice(-4_000);
  });
  ffmpeg.once("error", (error) => {
    if (!response.headersSent) sendError(response, error);
    else response.destroy(error);
  });
  ffmpeg.once("close", (code) => {
    if (code && !response.writableEnded) response.destroy(new Error(ffmpegError.trim() || `FFmpeg exited with status ${code}.`));
  });

  response.writeHead(200, {
    "Content-Type": "video/mp4",
    "Cache-Control": "no-store, no-cache, must-revalidate",
    "X-Content-Type-Options": "nosniff",
  });
  source.pipe(ffmpeg.stdin);
  ffmpeg.stdout.pipe(response);

  response.once("close", () => {
    if ("destroy" in source && typeof source.destroy === "function") source.destroy();
    if (!ffmpeg.killed) ffmpeg.kill();
  });
}

async function readJsonBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    length += buffer.length;
    if (length > 1_000_000) throw new Error("Request body is too large.");
    chunks.push(buffer);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("Request body must contain valid JSON.");
  }
}

async function serveStatic(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const distRoot = join(appRoot, "dist");
  const url = new URL(request.url ?? "/", `http://${request.headers.host ?? `${host}:${port}`}`);
  const requested = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, "");
  let file = join(distRoot, requested === "/" ? "index.html" : requested);
  try {
    const info = await stat(file);
    if (info.isDirectory()) file = join(file, "index.html");
  } catch {
    file = join(distRoot, "index.html");
  }
  if (!existsSync(file) || !file.startsWith(distRoot)) {
    sendJson(response, 404, { error: "Not found." });
    return;
  }
  response.writeHead(200, {
    "Content-Type": mimeType(file),
    "Cache-Control": extname(file) === ".html" ? "no-cache" : "public, max-age=31536000, immutable",
    "X-Content-Type-Options": "nosniff",
  });
  createReadStream(file).pipe(response);
}

function sameOrigin(request: IncomingMessage): boolean {
  const origin = request.headers.origin;
  if (!origin) return true;
  try {
    return new URL(origin).host === request.headers.host;
  } catch {
    return false;
  }
}

function sendJson(response: ServerResponse, status: number, body: unknown): void {
  if (response.writableEnded) return;
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}

function sendError(response: ServerResponse, error: unknown): void {
  if (response.writableEnded) return;
  const message = safeMessage(error);
  const status = /not found/i.test(message) ? 404 : /invalid|required|missing|add at least/i.test(message) ? 400 : 502;
  sendJson(response, status, { error: message });
}

function safeMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Unexpected server error.";
}

function mimeType(file: string): string {
  return ({
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json; charset=utf-8",
  } as Record<string, string>)[extname(file)] ?? "application/octet-stream";
}

async function shutdown(): Promise<void> {
  server.close();
  await manager.stopAll();
  process.exit(0);
}

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
