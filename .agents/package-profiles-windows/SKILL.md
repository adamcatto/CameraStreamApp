---
name: package-profiles-windows
description: >-
  Build a Profiles Windows zip from Mac for private sharing. Downloads the
  credential-free Windows app via gh, bundles workspaces and passwords locally,
  and prints the zip path. Use when sharing Profiles Camera Stream on Windows.
---

# Package Profiles Windows zip

## Command

```sh
cd ~/Desktop/reproducible-streaming
./apps/windows/scripts/package-profiles-on-macos.sh
```

Or from the `windows-port` worktree:

```sh
cd ~/.codex/worktrees/016c/CameraStreamApp
./apps/windows/scripts/package-profiles-on-macos.sh
```

Requires `gh auth login`. Reads workspaces from Application Support and credentials from `config/profiles/credentials.local.json`.

## Security

- CI artifact has **no lab secrets**
- Credentials are bundled **only on your Mac**
- Never send credentials to GitHub

## Output

Script prints the absolute path to:

`dist/windows/profiles-CameraStream-Windows.zip`

Share that zip privately (encrypted zip recommended).

## Colleague (Windows)

1. Extract All
2. Run **Install Profiles Camera Stream.bat** (installs to AppData) or **Run Camera Stream.bat** (no install)
3. App files live in the **CameraStream** subfolder; launchers stay at the zip root
4. Connect to lab VPN, pick a workspace, stream
