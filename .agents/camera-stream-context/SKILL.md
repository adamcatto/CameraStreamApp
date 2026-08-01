---
name: camera-stream-context
description: >-
  Project context for the Camera Stream macOS SwiftUI app: architecture,
  security model, build/packaging, and conventions. Use when working in
  CameraStreamApp or when onboarding to this codebase.
---

# Camera Stream — project context

## What this is

Native macOS SwiftUI app (`Sources/CameraStream/`) that:

- Manages named **workspaces** (camera host lists + optional SSH jump host)
- Starts H.264 encoders on Raspberry Pis via SSH
- Displays streams in-window via AVFoundation (`H264StreamView.swift`)
- Opens bundled **csshX** cluster shells via Terminal (`ClusterShell.swift`)

Companion binary: `CameraSSHAskpass` — SSH_ASKPASS helper for session passwords.

## Architecture

| File | Role |
|------|------|
| `CameraStreamApp.swift` | App entry, environment objects |
| `ContentView.swift` | NavigationSplitView: sidebar + detail (workspace editor, stream grid, settings) |
| `Models.swift` | `CameraWorkspace`, `WorkspaceStore`, `CredentialStore`, `SessionCredentials` |
| `StreamController.swift` | SSH launch, tunnels, logging |
| `BundledTools.swift` | Resolve `Contents/Resources/bin/csshX` |
| `ClusterShell.swift` | Launch csshX in Terminal |
| `H264StreamView.swift` | TCP H.264 decode/display |

Persistence: `~/Library/Application Support/CameraStream/workspaces.json`

## Security model (do not weaken)

- Passwords: in-memory only (`CredentialStore`); cleared on quit
- Temp credential JSON: mode 0600, deleted after streaming stops
- Never log passwords; `streaming.log` is SSH stderr only
- SSH: `-F /dev/null`, `ControlMaster=no`, `StrictHostKeyChecking=accept-new`
- Settings passwords use `SecureField`, not plain `TextField`
- No lab IPs or credentials in committed source — use `sandbox/workspaces.local.json`
- Cluster shell: validate host/username charset before shell invocation

## Build and package

```sh
cd CameraStreamApp
swift build -c release
./package-dmg.sh          # → dist/Camera-Stream.dmg
./scripts/smoke-test.sh
```

Bundled in DMG: `CameraStream`, `CameraSSHAskpass`, `csshX`, icon.

## Conventions

- Minimize scope; match existing SwiftUI patterns
- macOS 14+ target (`Package.swift`)
- Do not add Homebrew runtime dependencies to the app
- Lab-specific config belongs in `sandbox/` (gitignored)
