---
name: app-testing
description: >-
  Manual and scripted functional test plans for the Camera Stream macOS app UI
  and packaging. Use when testing the app, verifying a DMG build, validating
  UI flows, or before release.
---

# Camera Stream — app testing

## Automated smoke test (no network)

Run after every `./apps/macos/scripts/package-dmg.sh`:

```sh
./apps/macos/scripts/smoke-test.sh
```

Checks: bundle structure, executable bits, csshX shebang, DMG checksum, no obvious secrets in bundle.

Also run:

```sh
swift build -c release
```

## UI functional tests (manual, no cameras required)

Run the built app from `dist/Camera Stream.app` or `swift run`.

### FT-01 Sidebar layout

- [ ] Left pane lists workspaces
- [ ] **+** button is at top-right of sidebar
- [ ] **Settings** button with gear icon is at **bottom** of sidebar
- [ ] Settings row highlights when active

### FT-02 Settings navigation

- [ ] Click **Settings** → main (right) pane shows Settings view, not a sheet/modal
- [ ] Settings shows "Bundled tools" status line
- [ ] Click a workspace → returns to workspace editor; settings closes

### FT-03 Workspace editor

- [ ] Select workspace → name, jump host, camera list editable
- [ ] **Add camera** appends a row
- [ ] Delete camera (swipe/delete key) removes row
- [ ] **+** creates "New workspace" and selects it

### FT-04 Credentials UI

- [ ] Settings → password fields are masked (`SecureField`)
- [ ] **Clear all session credentials** empties fields
- [ ] Quit and relaunch → credentials are gone (not persisted)

### FT-05 Streaming controls (offline)

- [ ] **Start streaming** on workspace with cameras → status bar updates (will fail SSH without network; that's OK)
- [ ] **Stop** disables when not streaming
- [ ] Quit app while streaming → encoders stopped (check log)

### FT-06 Cluster shell (offline)

- [ ] **Open cluster shell** with ≥1 camera → Terminal opens or error alert if csshX missing
- [ ] Workspace with 0 cameras → alert "Add at least one camera"
- [ ] Host with invalid characters (e.g. `;rm`) → rejected with error alert

## Integration tests (require network — config/sandbox/)

These need VPN/lab access. Put real configs in `config/sandbox/workspaces.local.json` (gitignored), then:

```sh
./config/sandbox/import-workspaces.sh
```

### IT-01 SSH streaming

- [ ] Import lab workspaces
- [ ] Start streaming → H.264 tiles appear within ~5s per reachable camera
- [ ] Stop → encoders killed on Pis
- [ ] Check `~/Library/Application Support/CameraStream/streaming.log` — no passwords

### IT-02 Jump host

- [ ] Workspace with jump host → streams via local forwarded ports (127.0.0.1)
- [ ] Jump host password prompt appears when keys absent

### IT-03 Cluster shell

- [ ] Open cluster shell → csshX grid connects to all camera hosts

### IT-04 Fresh DMG install

- [ ] Copy DMG to clean user account or VM
- [ ] Install, launch without Homebrew
- [ ] Bundled tools status shows "csshX (bundled)"

## Reporting

Record: macOS version, build date, pass/fail per test ID, log excerpts (redact hosts if sharing externally).

## Future automation (backburner)

Candidate location: `config/sandbox/tests/`

- XCUITest for sidebar/settings navigation (no SSH)
- Scripted SSH mock for StreamController unit tests
- Separate CI job that skips IT-* tests
