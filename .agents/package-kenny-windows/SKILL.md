---
name: package-kenny-windows
description: >-
  Build a Kenny Windows zip from Mac for lab colleagues. Downloads the
  credential-free Windows app via gh, bundles workspaces and passwords locally,
  and prints the zip path. Use when sharing Kenny Camera Stream on Windows.
---

# Package Kenny Windows zip

## Command

```sh
cd ~/Desktop/reproducible-streaming
./apps/windows/scripts/package-kenny-on-macos.sh
```

Or from the `windows-port` worktree:

```sh
cd ~/.codex/worktrees/016c/CameraStreamApp
./apps/windows/scripts/package-kenny-on-macos.sh
```

Requires `gh auth login`. Reads workspaces from Application Support and credentials from `config/kenny/credentials.local.json`.

## Security

- CI artifact has **no lab secrets**
- Credentials are bundled **only on your Mac**
- Never send credentials to GitHub

## Output

Script prints the absolute path to:

`dist/windows/kenny-CameraStream-Windows.zip`

Share that zip privately (encrypted zip recommended).

## Colleague (Windows)

1. Extract All
2. Run **Install Kenny Camera Stream.bat** (installs to AppData) or **Run Camera Stream.bat** (no install)
3. App files live in the **CameraStream** subfolder; launchers stay at the zip root
4. Connect to lab VPN, pick a workspace, stream
