# macOS client

The native macOS app uses SwiftUI for workspace management, AVFoundation for
Annex-B H.264 playback, OpenSSH for camera control and jump forwarding, and the
bundled `csshX` script for cluster terminals.

```sh
swift build --package-path apps/macos
./apps/macos/scripts/package-dmg.sh
./apps/macos/scripts/smoke-test.sh
```

Generated app bundles and DMGs are written under `dist/macos/`. The Profiles DMG
builder is `apps/macos/scripts/package-profiles-dmg.sh`; it reads private inputs
from `config/profiles` and `config/sandbox` unless explicit paths are supplied.
