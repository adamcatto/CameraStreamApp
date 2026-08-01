#!/usr/bin/env bash
# Build a lab-specific DMG with IVSA / MotionCage / MouseMingle workspaces pre-bundled.
# Workspaces are read from Application Support or sandbox/workspaces.local.json (never committed).
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
build="$root/.build/release"
app="$root/dist/Camera Stream.app"
vendor_csshx="$root/Vendor/csshX"
staging="$root/dist/kenny-dmg-staging"
dmg="$root/dist/kenny-Camera-Stream.dmg"
workspaces_source="${1:-}"
credentials_source="${2:-}"

if [[ -z "$workspaces_source" ]]; then
  if [[ -f "$HOME/Library/Application Support/CameraStream/workspaces.json" ]]; then
    workspaces_source="$HOME/Library/Application Support/CameraStream/workspaces.json"
  elif [[ -f "$root/sandbox/workspaces.local.json" ]]; then
    workspaces_source="$root/sandbox/workspaces.local.json"
  fi
fi

if [[ -z "$credentials_source" ]]; then
  if [[ -f "$root/kenny/credentials.local.json" ]]; then
    credentials_source="$root/kenny/credentials.local.json"
  elif [[ -f "$root/sandbox/credentials.local.json" ]]; then
    credentials_source="$root/sandbox/credentials.local.json"
  fi
fi

if [[ -z "$workspaces_source" || ! -f "$workspaces_source" ]]; then
  cat >&2 <<'EOF'
No workspace file found to bundle.

Provide paths:
  ./package-kenny-dmg.sh [workspaces.json] [credentials.json]

Or ensure one of these exists:
  ~/Library/Application Support/CameraStream/workspaces.json
  sandbox/workspaces.local.json
EOF
  exit 1
fi

if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
  echo "No credentials file found. Generating kenny/credentials.local.json template..." >&2
  "$root/kenny/generate-credentials-template.sh" "$workspaces_source" "$root/kenny/credentials.local.json"
  cat >&2 <<'EOF'

Add passwords to kenny/credentials.local.json, then run ./package-kenny-dmg.sh again.
EOF
  exit 1
fi

if ! python3 -m json.tool "$workspaces_source" >/dev/null 2>&1; then
  echo "Workspace file is not valid JSON: $workspaces_source" >&2
  exit 1
fi

if ! python3 -m json.tool "$credentials_source" >/dev/null 2>&1; then
  echo "Credentials file is not valid JSON: $credentials_source" >&2
  exit 1
fi

mkdir -p "$root/dist"

if python3 - "$workspaces_source" "$credentials_source" "$root/dist/kenny-credentials.bundle.json" <<'PY'
import json, sys
workspaces = json.load(open(sys.argv[1]))
raw = json.load(open(sys.argv[2]))
by_name = {}
if isinstance(raw, list):
    for entry in raw:
        by_name[entry["workspaceName"]] = entry
elif isinstance(raw, dict):
    if "workspaces" in raw:
        for name, entry in raw["workspaces"].items():
            by_name[name] = {"workspaceName": name, **entry}
    else:
        by_name = {"__accounts__": raw}
else:
    raise SystemExit("Credentials file must be a JSON array or object.")

if "__accounts__" in by_name:
    account_credentials = by_name["__accounts__"]
    if not account_credentials or any(not str(password).strip() for password in account_credentials.values()):
        raise SystemExit("Account credentials file has missing passwords.")
    json.dump(account_credentials, open(sys.argv[3], "w"), indent=2)
    raise SystemExit(0)

account_credentials = {}
for workspace in workspaces:
    name = workspace["name"]
    entry = by_name.get(name)
    if not entry:
        raise SystemExit(f"Missing credentials entry for workspace: {name}")
    camera_password = str(entry.get("cameraPassword", "")).strip()
    if not camera_password:
        raise SystemExit(f"Missing cameraPassword for workspace: {name}")
    for camera in workspace.get("cameras", []):
        username = camera.get("username", "pi")
        host = camera.get("host", "")
        if host:
            account_credentials[f"{username}@{host}"] = camera_password
    jump_host = workspace.get("jumpHost")
    if jump_host:
        jump_password = str(entry.get("jumpPassword", "")).strip()
        if not jump_password:
            raise SystemExit(f"Missing jumpPassword for workspace: {name}")
        account_credentials[jump_host] = jump_password

if not account_credentials:
    raise SystemExit("No account credentials were generated.")
json.dump(account_credentials, open(sys.argv[3], "w"), indent=2)
PY
then
  :
else
  exit 1
fi

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

rm -rf "$app" "$staging" "$dmg" "$root/dist/Camera-Stream.dmg" "$root/dist/Camera-Stream-with-icon.dmg" "$root/dist-icon"
swift build -c release --package-path "$root"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/bin"
cp "$build/CameraStream" "$build/CameraSSHAskpass" "$app/Contents/MacOS/"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/Assets/CameraStream.icns" "$app/Contents/Resources/CameraStream.icns"
cp "$workspaces_source" "$app/Contents/Resources/kenny-workspaces.json"
cp "$root/dist/kenny-credentials.bundle.json" "$app/Contents/Resources/kenny-credentials.json"
chmod 600 "$app/Contents/Resources/kenny-credentials.json"
rm -f "$root/dist/kenny-credentials.bundle.json"
cp "$vendor_csshx" "$app/Contents/Resources/bin/csshX"
chmod +x "$app/Contents/Resources/bin/csshX"
if [[ -f "$root/Vendor/csshX-LICENSE" ]]; then
  cp "$root/Vendor/csshX-LICENSE" "$app/Contents/Resources/bin/csshX-LICENSE"
fi

mkdir -p "$staging"
cp -R "$app" "$staging/"
cp "$root/kenny/Install Kenny Camera Stream.command" "$staging/"
chmod +x "$staging/Install Kenny Camera Stream.command"
ln -sf /Applications "$staging/Applications"

mkdir -p "$root/dist"
hdiutil create -volname "Kenny Camera Stream" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Created $dmg"
echo "Bundled workspaces from: $workspaces_source"
echo "Bundled credentials from: $credentials_source"
echo "Share this DMG privately — it contains lab IPs and passwords."
echo "Colleagues double-click \"Install Kenny Camera Stream.command\"."
