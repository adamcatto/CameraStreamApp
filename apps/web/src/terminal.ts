import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";
import type { SessionStatus } from "./models";

interface ActiveTerminal {
  terminal: Terminal;
  fit: FitAddon;
  socket: WebSocket;
}

let active: ActiveTerminal[] = [];
let resizeObserver: ResizeObserver | null = null;

export function mountTerminals(session: SessionStatus): void {
  disposeTerminals();
  const grid = document.querySelector<HTMLElement>("#terminal-grid");
  if (!grid) return;

  for (const camera of session.cameras) {
    const pane = document.createElement("section");
    pane.className = "terminal-pane";
    pane.innerHTML = `<header>${escapeHtml(camera.name)}<span>${escapeHtml(camera.host)}</span></header><div class="terminal-surface"></div>`;
    grid.append(pane);
    const surface = pane.querySelector<HTMLElement>(".terminal-surface")!;
    const terminal = new Terminal({
      cursorBlink: true,
      convertEol: true,
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
      fontSize: 12,
      theme: { background: "#101419", foreground: "#dce4eb", cursor: "#68a4d5" },
    });
    const fit = new FitAddon();
    terminal.loadAddon(fit);
    terminal.open(surface);
    fit.fit();

    const protocol = location.protocol === "https:" ? "wss" : "ws";
    const path = `/api/sessions/${encodeURIComponent(session.id)}/cameras/${encodeURIComponent(camera.id)}/terminal`;
    const socket = new WebSocket(`${protocol}://${location.host}${path}`);
    socket.binaryType = "arraybuffer";
    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({ type: "resize", cols: terminal.cols, rows: terminal.rows }));
      terminal.focus();
    });
    socket.addEventListener("message", (event) => {
      terminal.write(typeof event.data === "string" ? event.data : new Uint8Array(event.data));
    });
    socket.addEventListener("close", () => terminal.write("\r\n\x1b[90mConnection closed.\x1b[0m\r\n"));
    terminal.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: "input", data }));
    });
    active.push({ terminal, fit, socket });
  }

  resizeObserver = new ResizeObserver(() => {
    for (const item of active) {
      item.fit.fit();
      if (item.socket.readyState === WebSocket.OPEN) {
        item.socket.send(JSON.stringify({ type: "resize", cols: item.terminal.cols, rows: item.terminal.rows }));
      }
    }
  });
  resizeObserver.observe(grid);
}

export function disposeTerminals(): void {
  resizeObserver?.disconnect();
  resizeObserver = null;
  for (const item of active) {
    item.socket.close();
    item.terminal.dispose();
  }
  active = [];
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", "\"": "&quot;",
  })[character] ?? character);
}
