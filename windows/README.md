# Camera Stream for Windows

This is a native Windows port of the macOS SwiftUI Camera Stream app. It uses WPF on .NET 8, LibVLC for H.264 playback, and the Windows OpenSSH client (`ssh.exe`).

## What is implemented

- Workspace editor (name, jump host, camera list)
- Live streaming with `tcp/h264://` playback through LibVLC
- SSH control of remote Raspberry Pi cameras
- Verified two-stage jump-host SSH: authenticate the jump host first, then probe each camera independently through it
- Per-camera SSH and H.264 forwarding, so unreachable cameras are skipped without blocking available streams
- `SSH_ASKPASS` helper using a bundled PowerShell script
- Session credential management
- Cluster shell via Windows Terminal (`wt.exe`) with a separate-window fallback
- Self-contained publish and zip packaging
- Kenny lab bundle packaging

## Prerequisites (build machine)

- Windows 10/11 or a machine with the .NET 8 SDK
- `ssh.exe` (included with Windows 10 1809+ and Windows 11)
- PowerShell 7+ for the Kenny bundler

## Build

From a PowerShell prompt in `windows/`:

```powershell
# Standard build
.\package-windows.ps1

# Kenny bundle build
.\package-kenny-windows.ps1
```

The output zips are written to `dist/windows/`.

CI on GitHub Actions runs `package-windows.ps1` (including the smoke test) on every push to `windows-port`. Download the built zip from the workflow run's **Artifacts** tab.

## Install

1. Extract the zip.
2. Run `Install Camera Stream.bat` (or `Install Kenny Camera Stream.bat`).
3. The batch file copies the app to `%LOCALAPPDATA%\CameraStream` and launches it.

## Project layout

```
windows/
  CameraStream.Windows/       WPF application
    Models/                    JSON workspace/camera models
    ViewModels/                MVVM view models
    Views/                     XAML views and controls
    Services/                  SSH, streaming, workspace/credential stores
    Assets/                    Icon and SSH askpass scripts
  kenny/                       Kenny installer and sharing notes
  scripts/                     Kenny credential bundler
  package-windows.ps1
  package-kenny-windows.ps1
```

## Notes

- Workspaces and settings are stored in `%LOCALAPPDATA%\CameraStream\`.
- Streaming logs are written to `%LOCALAPPDATA%\CameraStream\streaming.log`.
- Jump-host sessions, per-camera SSH results, and skipped cameras are recorded in the streaming log; passwords are never logged.
- `CameraSSHAskpass.cmd` / `CameraSSHAskpass.ps1` act as the Windows equivalent of the macOS `CameraSSHAskpass` helper. They read the temporary credential JSON created for each streaming session.
- Unlike the macOS app, this port does not depend on `csshX`; cluster shell uses Windows Terminal split panes or separate `ssh` windows.
