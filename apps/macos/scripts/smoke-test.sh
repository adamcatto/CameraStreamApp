#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
app="$repo_root/dist/macos/Camera Stream.app"
dmg="$repo_root/dist/macos/Camera-Stream.dmg"
fail=0

check() {
  if "$@"; then echo "PASS: $*"
  else echo "FAIL: $*" >&2; fail=1; fi
}

echo "=== Camera Stream smoke test ==="

check test -d "$app"
check test -x "$app/Contents/MacOS/CameraStream"
check test -x "$app/Contents/MacOS/CameraSSHAskpass"
check test -x "$app/Contents/Resources/bin/csshX"
check grep -q '^#!/usr/bin/env perl' "$app/Contents/Resources/bin/csshX"

if [[ -f "$dmg" ]]; then
  check hdiutil verify "$dmg"
else
  echo "SKIP: DMG not found at $dmg"
fi

# Ensure no obvious secrets in the bundle
if grep -RqiE 'password\s*=\s*["'"'"'][^"'"'"']+["'"'"']|BEGIN (RSA|OPENSSH) PRIVATE' "$app/Contents" 2>/dev/null; then
  echo "FAIL: possible secret material in app bundle" >&2
  fail=1
else
  echo "PASS: no obvious secrets in app bundle"
fi

if (( fail )); then
  echo "Smoke test FAILED"
  exit 1
fi
echo "Smoke test PASSED"
