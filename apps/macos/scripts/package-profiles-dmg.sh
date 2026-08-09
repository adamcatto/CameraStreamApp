#!/usr/bin/env bash
# Build a personal-profile DMG with selected workspaces pre-bundled.
# Workspaces are read from Application Support or config/sandbox/workspaces.local.json (never committed).
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$app_root/../.." && pwd)"
build="$app_root/.build/release"
dist="$repo_root/dist/macos"
app="$dist/Camera Stream.app"
vendor_csshx="$app_root/Vendor/csshX"
staging="$dist/profiles-dmg-staging"
dmg="$dist/profiles-Camera-Stream.dmg"
workspaces_source="${1:-}"
credentials_source="${2:-}"

if [[ -z "$workspaces_source" ]]; then
  if [[ -f "$HOME/Library/Application Support/CameraStream/workspaces.json" ]]; then
    workspaces_source="$HOME/Library/Application Support/CameraStream/workspaces.json"
  elif [[ -f "$repo_root/config/sandbox/workspaces.local.json" ]]; then
    workspaces_source="$repo_root/config/sandbox/workspaces.local.json"
  fi
fi

if [[ -z "$credentials_source" ]]; then
  if [[ -f "$repo_root/config/profiles/credentials.local.json" ]]; then
    credentials_source="$repo_root/config/profiles/credentials.local.json"
  elif [[ -f "$repo_root/config/sandbox/credentials.local.json" ]]; then
    credentials_source="$repo_root/config/sandbox/credentials.local.json"
  fi
fi

if [[ -z "$workspaces_source" || ! -f "$workspaces_source" ]]; then
  cat >&2 <<'EOF'
No workspace file found to bundle.

Provide paths:
  ./apps/macos/scripts/package-profiles-dmg.sh [workspaces.json] [credentials.json]

Or ensure one of these exists:
  ~/Library/Application Support/CameraStream/workspaces.json
  config/sandbox/workspaces.local.json
EOF
  exit 1
fi

if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
  echo "No credentials file found. Generating config/profiles/credentials.local.json template..." >&2
  "$repo_root/config/profiles/generate-credentials-template.sh" "$workspaces_source" "$repo_root/config/profiles/credentials.local.json"
  cat >&2 <<'EOF'

Add passwords to config/profiles/credentials.local.json, then run this script again.
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

mkdir -p "$dist"

if python3 - "$workspaces_source" "$credentials_source" "$dist/profiles-credentials.bundle.json" <<'PY'
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

rm -rf "$app" "$staging" "$dmg" "$dist/Camera-Stream.dmg" "$dist/Camera-Stream-with-icon.dmg" "$dist-icon"
swift build -c release --package-path "$app_root"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/bin"
cp "$build/CameraStream" "$build/CameraSSHAskpass" "$app/Contents/MacOS/"
cp "$app_root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$app_root/Resources/Assets/CameraStream.icns" "$app/Contents/Resources/CameraStream.icns"
cp "$workspaces_source" "$app/Contents/Resources/profiles-workspaces.json"
cp "$dist/profiles-credentials.bundle.json" "$app/Contents/Resources/profiles-credentials.json"
chmod 600 "$app/Contents/Resources/profiles-credentials.json"
rm -f "$dist/profiles-credentials.bundle.json"
cp "$vendor_csshx" "$app/Contents/Resources/bin/csshX"
chmod +x "$app/Contents/Resources/bin/csshX"
if [[ -f "$app_root/Vendor/csshX-LICENSE" ]]; then
  cp "$app_root/Vendor/csshX-LICENSE" "$app/Contents/Resources/bin/csshX-LICENSE"
fi

mkdir -p "$staging"
cp -R "$app" "$staging/"
cp "$repo_root/config/profiles/Install Profiles Camera Stream.command" "$staging/"
chmod +x "$staging/Install Profiles Camera Stream.command"
ln -sf /Applications "$staging/Applications"

mkdir -p "$dist"
hdiutil create -volname "Profiles Camera Stream" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Created $dmg"
echo "Bundled workspaces from: $workspaces_source"
echo "Bundled credentials from: $credentials_source"
echo "Share this DMG privately — it contains workspace hosts and passwords."
echo "Users double-click \"Install Profiles Camera Stream.command\"."
