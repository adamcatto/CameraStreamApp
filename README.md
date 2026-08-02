# Camera Stream

Native macOS SwiftUI app for managing Raspberry Pi camera workspaces, streaming H.264 feeds in-window, and opening csshX cluster shells.

## Requirements

- macOS 14+
- Built-in OpenSSH (`/usr/bin/ssh`) and Perl (`/usr/bin/perl`)

No Homebrew or external dependencies are required at runtime. The DMG bundles `csshX` and `CameraSSHAskpass`.

## Build and package

```sh
swift build              # debug
swift build -c release   # release
./package-dmg.sh         # dist/Camera-Stream.dmg
./scripts/smoke-test.sh  # verify bundle after packaging
```

## Install (fresh Mac)

1. Open `dist/Camera-Stream.dmg` and drag **Camera Stream** to Applications.
2. Launch the app (right-click → Open if Gatekeeper blocks the unsigned build).
3. Configure workspaces with your camera hosts, then **Start streaming** or **Open cluster shell**.

Network access to the cameras and SSH credentials (keys or session passwords) are still required and are never bundled in the installer.

## Security

- Session passwords live in memory only and are cleared on quit.
- Temporary credential files are mode `0600` and deleted after streaming stops.
- Passwords are not written to workspace JSON, Keychain, or logs.
- SSH uses `-F /dev/null` and disables ControlMaster to avoid stale credential reuse.
- The committed repo contains no lab IP addresses or credentials. Use `sandbox/` for local configs.

For distribution outside your organization, sign and notarize the app before sharing.

## Project layout

```
Sources/CameraStream/     SwiftUI app and streaming logic
Sources/CameraSSHAskpass/ SSH_ASKPASS helper
Vendor/csshX              Bundled cluster shell (vendored at build time)
Assets/                   App icon
scripts/                  Build verification
sandbox/                  Local-only test configs (gitignored)
.agents/                  Agent skills and project context
```

## Local lab configuration

Copy the example and add your workspace definitions:

```sh
cp sandbox/workspaces.example.json sandbox/workspaces.local.json
# edit sandbox/workspaces.local.json with your camera hosts
./sandbox/import-workspaces.sh
```

This imports into `~/Library/Application Support/CameraStream/workspaces.json` for app testing.

## Windows port

A native Windows build lives in the `windows/` directory on the `windows-port` branch. It targets WPF on .NET 8 and uses LibVLC for H.264 playback. See [windows/README.md](windows/README.md) for build and install instructions.

## Logs

`~/Library/Application Support/CameraStream/streaming.log` — SSH diagnostics only; no passwords.
