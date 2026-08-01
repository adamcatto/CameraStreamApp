---
name: build-and-package
description: >-
  Build, package, and verify the Camera Stream DMG for macOS. Use when creating
  a release build, updating package-dmg.sh, or troubleshooting bundling csshX.
---

# Build and package

## Release DMG

```sh
cd CameraStreamApp
./package-dmg.sh
./scripts/smoke-test.sh
```

Output: `dist/Camera Stream.app`, `dist/Camera-Stream.dmg`

## csshX vendoring

`Vendor/csshX` must exist before packaging. If missing, `package-dmg.sh` copies from Homebrew (`brew install csshx`) and patches the Perl shebang to `#!/usr/bin/env perl`.

Commit `Vendor/csshX` and `Vendor/csshX-LICENSE` so CI/build machines don't need Homebrew.

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

- [ ] `./scripts/smoke-test.sh` passes
- [ ] No secrets or internal IPs in committed source
- [ ] For external sharing: code-sign and notarize (unsigned DMG triggers Gatekeeper)
- [ ] Document right-click → Open for first launch

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing csshX at runtime | Rebuild DMG; check `Resources/bin/csshX` is executable |
| "bad interpreter" for csshX | Shebang must be `#!/usr/bin/env perl` |
| Gatekeeper blocks app | Sign/notarize or user right-clicks → Open |
