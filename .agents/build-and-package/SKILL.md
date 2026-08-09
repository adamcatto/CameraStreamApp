---
name: build-and-package
description: >-
  Build, package, and verify the Camera Stream DMG for macOS. Use when creating
  a release build, updating the macOS packaging scripts, or troubleshooting bundled csshX.
---

# Build and package

## Release DMG

```sh
cd CameraStreamApp
./apps/macos/scripts/package-dmg.sh
./apps/macos/scripts/smoke-test.sh
```

Output: `dist/Camera Stream.app`, `dist/Camera-Stream.dmg`

For a Profiles Windows zip from Mac, see `.agents/package-profiles-windows/SKILL.md`.

## csshX vendoring

`apps/macos/Vendor/csshX` must exist before packaging. If missing, the package script copies from Homebrew (`brew install csshx`) and patches the Perl shebang to `#!/usr/bin/env perl`.

Commit `apps/macos/Vendor/csshX` and `apps/macos/Vendor/csshX-LICENSE` so CI/build machines don't need Homebrew.

## App bundle layout

```
Camera Stream.app/Contents/
  MacOS/CameraStream
  MacOS/CameraSSHAskpass
  Resources/CameraStream.icns
  Resources/bin/csshX
  Resources/bin/csshX-LICENSE
  Info.plist
```

## Distribution checklist

- [ ] `./apps/macos/scripts/smoke-test.sh` passes
- [ ] No secrets or internal IPs in committed source
- [ ] For external sharing: code-sign and notarize (unsigned DMG triggers Gatekeeper)
- [ ] Document right-click → Open for first launch

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing csshX at runtime | Rebuild DMG; check `Resources/bin/csshX` is executable |
| "bad interpreter" for csshX | Shebang must be `#!/usr/bin/env perl` |
| Gatekeeper blocks app | Sign/notarize or user right-clicks → Open |
