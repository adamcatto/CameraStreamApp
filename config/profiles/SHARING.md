# Sharing the Profiles Camera Stream DMG

The Profiles build (`profiles-Camera-Stream.dmg`) includes selected workspaces **and passwords**. Treat it like a credential — share it privately, never commit it to git, and never upload it to a public link.

## Build the DMG (your Mac)

```sh
cd CameraStreamApp
./apps/macos/scripts/package-profiles-dmg.sh
```

Output: `dist/profiles-Camera-Stream.dmg`

Credentials are read from `config/profiles/credentials.local.json` (gitignored). Workspaces come from Application Support or `config/sandbox/workspaces.local.json`.

### Windows zip (build from your Mac)

```sh
cd CameraStreamApp
git checkout windows-port   # or pull latest windows-port
./apps/windows/scripts/package-profiles-on-macos.sh
```

Output: `dist/windows/profiles-CameraStream-Windows.zip`

This script bundles the same profile workspaces and credentials as the DMG **entirely on your Mac**. It downloads the latest credential-free `CameraStream-Windows` artifact from GitHub Actions, then adds `profiles-workspaces.json`, `profiles-credentials.json`, and **Install Profiles Camera Stream.bat** locally. **Credentials never leave your machine** — they are not sent to GitHub.

Requires [GitHub CLI](https://cli.github.com/) (`brew install gh`, then `gh auth login`) to download the Windows app artifact.

> **Previous approach (removed):** An earlier version of this script base64-encoded workspaces and credentials and passed them to GitHub Actions `workflow_dispatch`. That sent secrets to GitHub and has been removed. Always use the current local-only script.

Send the resulting zip privately to Windows users — they extract it and run **Install Profiles Camera Stream.bat**.

---

## On your Mac — share the file

### 1. Locate the file

```sh
open dist
```

You want **`profiles-Camera-Stream.dmg`**.

### 2. Pick a private sharing method

| Method | Good for | Steps |
|--------|----------|--------|
| **AirDrop** | Same room / nearby | Right-click the DMG → **Share** → **AirDrop** → select colleague |
| **Private shared drive** | Authorized users | Upload to a **restricted** folder (not public). Send the link only to them |
| **Encrypted zip + separate password** | Email or Slack | See below |
| **USB drive** | In-person handoff | Copy DMG to drive, hand it over |

**Avoid:** GitHub, public Google Drive links, unencrypted email attachments, Slack channels lots of people can see.

### 3. (Recommended) Encrypted zip

If you use email or chat:

```sh
cd dist
zip -e profiles-Camera-Stream.zip profiles-Camera-Stream.dmg
```

Set a strong zip password when prompted. Send the **zip** in chat/email and the **password** separately (phone, Signal, in person).

---

## On your colleague's Mac — install

### 4. Get the file

Download from the shared drive, accept AirDrop, or copy from USB.

If it is a zip, double-click and enter the password you sent separately.

### 5. Open the DMG

Double-click **`profiles-Camera-Stream.dmg`**.

### 6. Install (one click)

Double-click **`Install Profiles Camera Stream.command`**.

If macOS blocks it: **System Settings → Privacy & Security → Open Anyway**, or right-click the installer → **Open**.

The installer will:

- Copy **Camera Stream** to `/Applications`
- Clear quarantine flags
- Launch the app

### 7. First launch

They should see the bundled workspaces with credentials already loaded.

If Gatekeeper blocks the app: right-click **Camera Stream** in Applications → **Open** (first time only).

### 8. Start using it

1. Select a workspace.
2. Click **Start streaming** or **Open cluster shell**
3. Connect to the VPN or network that can reach the cameras.

No password entry should be required if the bundled credentials work.

---

## Checklist

**You:**

- [ ] Share `profiles-Camera-Stream.dmg` (or encrypted zip) privately
- [ ] Do **not** upload to GitHub or a public link
- [ ] Send zip password separately if you encrypted

**Colleague:**

- [ ] Open DMG → run **Install Profiles Camera Stream.command**
- [ ] Right-click → **Open** if Gatekeeper warns
- [ ] Connect to the required VPN/network
- [ ] Pick a workspace and stream

---

## Simplest path

- **Nearby:** AirDrop the DMG
- **Remote:** Encrypted zip + password sent over a second channel
