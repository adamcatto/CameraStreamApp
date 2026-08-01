#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
build="$root/.build/release"
app="$root/dist/Camera Stream.app"
vendor_csshx="$root/Vendor/csshX"

if [[ ! -x "$vendor_csshx" ]]; then
  if command -v brew >/dev/null 2>&1 && csshx_path="$(brew --prefix csshx 2>/dev/null)/bin/csshX" && [[ -f "$csshx_path" ]]; then
    mkdir -p "$root/Vendor"
    cp "$csshx_path" "$vendor_csshx"
    sed -i.bak '1s|^#!/usr/bin/perl[0-9.]*$|#!/usr/bin/env perl|' "$vendor_csshx"
    rm -f "$vendor_csshx.bak"
    echo "Vendored csshX from Homebrew for bundling."
  else
    echo "Missing $vendor_csshx. Install csshX with Homebrew or add the script to Vendor/ before packaging." >&2
    exit 1
  fi
fi

rm -rf "$app" "$root/dist/Camera-Stream.dmg" "$root/dist/Camera-Stream-with-icon.dmg" "$root/dist-icon"
swift build -c release --package-path "$root"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/bin"
cp "$build/CameraStream" "$build/CameraSSHAskpass" "$app/Contents/MacOS/"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/Assets/CameraStream.icns" "$app/Contents/Resources/CameraStream.icns"
cp "$vendor_csshx" "$app/Contents/Resources/bin/csshX"
chmod +x "$app/Contents/Resources/bin/csshX"
if [[ -f "$root/Vendor/csshX-LICENSE" ]]; then
  cp "$root/Vendor/csshX-LICENSE" "$app/Contents/Resources/bin/csshX-LICENSE"
fi
mkdir -p "$root/dist"
hdiutil create -volname "Camera Stream" -srcfolder "$app" -ov -format UDZO "$root/dist/Camera-Stream.dmg"
echo "Created $root/dist/Camera-Stream.dmg"
