# Camera Stream

Native macOS and Windows apps for managing Raspberry Pi camera workspaces, starting remote camera encoders over SSH, and viewing H.264 streams in-window.

- **macOS:** SwiftUI, AVFoundation, and the bundled `csshX` cluster shell
- **Windows:** WPF on .NET 8 with LibVLC playback and Windows Terminal cluster shells
- **Jump hosts:** Both apps support cameras reached through an SSH jump host. The Windows app verifies the jump host first, checks each camera independently, and streams every camera it can reach.

## Requirements

### macOS

- macOS 14+
- Built-in OpenSSH (`/usr/bin/ssh`) and Perl (`/usr/bin/perl`)

No Homebrew or external runtime dependencies are required. The DMG bundles `csshX` and `CameraSSHAskpass`.

### Windows

- Windows 10 or Windows 11
- Windows OpenSSH client (`ssh.exe`)

The Windows ZIP is self-contained and does not require a separate .NET installation. LibVLC and the native SSH askpass helper are included.

## Build and package

### macOS

```sh
swift build              # debug
swift build -c release   # release
./package-dmg.sh         # dist/Camera-Stream.dmg
./scripts/smoke-test.sh  # verify bundle after packaging
```

### Windows

From PowerShell on Windows:

```powershell
cd windows
.\package-windows.ps1
```

This creates `dist/windows/CameraStream-Windows.zip`. CI also builds the Windows ZIP on pushes to `windows-port`. See [windows/README.md](windows/README.md) for detailed build and packaging instructions.

## Install

### macOS

1. Open `dist/Camera-Stream.dmg` and drag **Camera Stream** to Applications.
2. Launch the app (right-click → Open if Gatekeeper blocks the unsigned build).
3. Configure workspaces with your camera hosts, then **Start streaming** or **Open cluster shell**.

### Windows

1. Extract `CameraStream-Windows.zip`.
2. Run `Install Camera Stream.bat`, or run the portable app with `Run Camera Stream.bat`.
3. Configure a workspace and its camera, jump-host, and SSH credentials, then select **Start streaming**.

The standard macOS and Windows packages do not contain camera hosts or credentials. Private Kenny lab packages can bundle workspace definitions and passwords for internal distribution and must be shared securely.

## Security

- Session passwords live in memory only and are cleared on quit.
- Temporary credential files are restricted to the current user and deleted after streaming stops.
- Passwords are not written to workspace JSON, Keychain, or logs.
- SSH uses `-F /dev/null` and disables ControlMaster to avoid stale credential reuse.
- The committed repository contains no lab IP addresses or credentials. Use the gitignored local configuration files for lab-specific values.

For distribution outside your organization, sign and notarize the app before sharing.

## Project layout

```
Sources/CameraStream/     SwiftUI app and streaming logic
Sources/CameraSSHAskpass/ SSH_ASKPASS helper
Vendor/csshX              Bundled cluster shell (vendored at build time)
Assets/                   App icon
windows/                  Native WPF/.NET 8 Windows application and packaging
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

This imports into `~/Library/Application Support/CameraStream/workspaces.json` for macOS app testing. On Windows, workspaces are stored under `%LOCALAPPDATA%\CameraStream\`.

## Logs

- **macOS:** `~/Library/Application Support/CameraStream/streaming.log`
- **Windows:** `%LOCALAPPDATA%\CameraStream\streaming.log`

Logs include SSH connection and camera availability diagnostics but never passwords.
