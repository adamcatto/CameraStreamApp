# Camera Stream

Camera Stream is a cross-platform monorepo for controlling Raspberry Pi camera
workspaces over SSH and viewing their live H.264 feeds. It includes native
macOS and Windows clients plus a browser client backed by a loopback-only local
gateway.

| Client | UI and playback | SSH transport |
| --- | --- | --- |
| macOS | SwiftUI + AVFoundation | OpenSSH, with bundled `csshX` for cluster shells |
| Windows | WPF/.NET 8 + LibVLC | Windows OpenSSH and Windows Terminal |
| Web | Vanilla TypeScript + browser video + xterm.js | Local Node gateway using SSH2 and bundled FFmpeg |

All three clients support direct camera connections and jump hosts. A jump-host
session authenticates the jump host first, then attempts each camera
independently. Unreachable cameras are reported and skipped while every
reachable camera continues streaming.

While streaming, every client exposes a per-camera capture panel (shutter, gain,
brightness, contrast, saturation, sharpness, EV, and frame rate). Because the Pi
camera stack takes these only as launch arguments, applying a change relaunches
that one camera's encoder and reconnects its tile; the other feeds keep playing.
Defaults reproduce the original hardcoded pipeline, and the optional per-camera
`settings` object is documented in `packages/config-schema`.

## Repository layout

```text
apps/
  macos/                    Swift package, resources, and DMG tooling
  windows/                  WPF solution, installers, and ZIP tooling
  web/                      Browser UI and loopback SSH/streaming gateway
packages/
  config-schema/            Canonical cross-platform workspace JSON schema
config/
  sandbox/                  Safe examples and gitignored local lab configs
  profiles/                 Private profile templates and gitignored credentials
.github/workflows/          Platform-specific continuous integration
dist/                       Generated packages (gitignored)
```

Platform implementations intentionally do not share runtime code: Swift,
C#/.NET, and Node have different networking and media primitives. They do share
the serialized workspace contract in `packages/config-schema` so workspaces can
be imported and exported between clients.

## Run the web client

Requirements: Node.js 20.19 or newer. OpenSSH is not required for the web app;
its gateway uses an SSH library directly. FFmpeg is installed as a local npm
dependency.

```sh
npm install
npm run web:dev
```

Open `http://127.0.0.1:4173`. The server binds only to loopback. Keep the
terminal process running while using the app.

For a production-mode local build:

```sh
npm run web:build
npm run web:start
```

The web client is intentionally a local application rather than a static hosted
site: browsers cannot open SSH connections or raw camera TCP streams directly.
The local gateway establishes camera and jump-host connections, converts the
Annex-B H.264 stream to fragmented MP4, and serves it to the browser on the same
computer. Its cluster shell uses the already-authenticated per-camera SSH
sessions.

See [apps/web/README.md](apps/web/README.md) for runtime details.

## Build native clients

### macOS

Requires macOS 14+, Swift 6, `/usr/bin/ssh`, and `/usr/bin/perl`.

```sh
swift build --package-path apps/macos
swift build -c release --package-path apps/macos
./apps/macos/scripts/package-dmg.sh
./apps/macos/scripts/smoke-test.sh
```

The DMG is written to `dist/macos/Camera-Stream.dmg`. See
[apps/macos/README.md](apps/macos/README.md).

### Windows

Requires Windows 10/11 and the Windows OpenSSH client. The packaged app is
self-contained and does not require a separate .NET installation.

```powershell
Set-Location apps/windows
.\package-windows.ps1
```

The ZIP is written to `dist/windows/CameraStream-Windows.zip`. See
[apps/windows/README.md](apps/windows/README.md).

## Workspace configuration

The common format includes a workspace name, optional `user@jump-host`, and a
list of camera names, hosts, usernames, and base stream ports. The apps start
camera encoders at the configured base port plus the camera's zero-based
position, matching the original macOS behavior.

For local macOS testing:

```sh
cp config/sandbox/workspaces.example.json config/sandbox/workspaces.local.json
# Edit the local file with your camera hosts.
./config/sandbox/import-workspaces.sh
```

The web app can import this JSON directly. Windows can use the same file through
its workspace store or private packaging flow.

The web client's in-memory credential importer accepts JSON, YAML, CSV, TSV,
and XLSX. It matches account or workspace columns against existing workspaces
without persisting passwords. See [apps/web/README.md](apps/web/README.md#credential-imports)
for accepted layouts.

## Security

- Standard packages and committed examples contain no lab IPs or credentials.
- Passwords are kept only for the current application/browser session.
- Native clients use permission-restricted temporary credential files and
  remove them after sessions stop.
- The web client does not persist passwords; its gateway binds to
  `127.0.0.1`, rejects cross-origin API and terminal requests, and never writes
  passwords to logs.
- Private profile packages can embed hosts and passwords. Share those artifacts
  only through an approved private channel.

Native logs are stored at:

- macOS: `~/Library/Application Support/CameraStream/streaming.log`
- Windows: `%LOCALAPPDATA%\CameraStream\streaming.log`

The web connection log is held in gateway memory and is visible from the status
bar while a session is active.
