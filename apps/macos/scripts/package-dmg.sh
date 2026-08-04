#!/usr/bin/env bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$app_root/../.." && pwd)"
build="$app_root/.build/release"
dist="$repo_root/dist/macos"
app="$dist/Camera Stream.app"
vendor_csshx="$app_root/Vendor/csshX"

if [[ ! -x "$vendor_csshx" ]]; then
  if command -v brew >/dev/null 2>&1 && csshx_path="$(brew --prefix csshx 2>/dev/null)/bin/csshX" && [[ -f "$csshx_path" ]]; then
    mkdir -p "$app_root/Vendor"
    cp "$csshx_path" "$vendor_csshx"
    sed -i.bak '1s|^#!/usr/bin/perl[0-9.]*$|#!/usr/bin/env perl|' "$vendor_csshx"
    rm -f "$vendor_csshx.bak"
    echo "Vendored csshX from Homebrew for bundling."
  else
    echo "Missing $vendor_csshx. Install csshX with Homebrew or add the script to apps/macos/Vendor/ before packaging." >&2
    exit 1
  fi
fi

rm -rf "$app" "$dist/Camera-Stream.dmg" "$dist/Camera-Stream-with-icon.dmg" "$dist-icon"
swift build -c release --package-path "$app_root"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/bin"
cp "$build/CameraStream" "$build/CameraSSHAskpass" "$app/Contents/MacOS/"
cp "$app_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$app_root/Resources/Assets/CameraStream.icns" "$app/Contents/Resources/CameraStream.icns"
cp "$vendor_csshx" "$app/Contents/Resources/bin/csshX"
chmod +x "$app/Contents/Resources/bin/csshX"
if [[ -f "$app_root/Vendor/csshX-LICENSE" ]]; then
  cp "$app_root/Vendor/csshX-LICENSE" "$app/Contents/Resources/bin/csshX-LICENSE"
fi
mkdir -p "$dist"
hdiutil create -volname "Camera Stream" -srcfolder "$app" -ov -format UDZO "$dist/Camera-Stream.dmg"
echo "Created $dist/Camera-Stream.dmg"
