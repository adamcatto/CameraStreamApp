#!/usr/bin/env bash
# Build a Kenny Windows zip via GitHub Actions from your Mac.
# Bundles lab workspaces + credentials, triggers CI, downloads dist/windows/kenny-CameraStream-Windows.zip
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
workspaces_source="${1:-}"
credentials_source="${2:-}"
branch="${CAMERA_STREAM_WINDOWS_BRANCH:-windows-port}"
bundle_file="$root/dist/kenny-credentials.bundle.json"
output_zip="$root/dist/windows/kenny-CameraStream-Windows.zip"

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
  ./package-kenny-windows.sh [workspaces.json] [credentials.json]

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

Add passwords to kenny/credentials.local.json, then run ./package-kenny-windows.sh again.
EOF
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "The GitHub CLI (gh) is required. Install with: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run 'gh auth login' before building the Kenny Windows zip." >&2
  exit 1
fi

mkdir -p "$root/dist/windows"

if ! python3 -m json.tool "$workspaces_source" >/dev/null 2>&1; then
  echo "Workspace file is not valid JSON: $workspaces_source" >&2
  exit 1
fi

if ! python3 -m json.tool "$credentials_source" >/dev/null 2>&1; then
  echo "Credentials file is not valid JSON: $credentials_source" >&2
  exit 1
fi

if python3 - "$workspaces_source" "$credentials_source" "$bundle_file" <<'PY'
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

workspaces_b64="$(base64 -i "$workspaces_source" | tr -d '\n')"
credentials_b64="$(base64 -i "$bundle_file" | tr -d '\n')"
rm -f "$bundle_file"

echo "Triggering GitHub Actions Kenny Windows build on branch $branch ..."
gh workflow run "Windows build" --ref "$branch" \
  -f "workspaces_b64=$workspaces_b64" \
  -f "credentials_b64=$credentials_b64"

sleep 5
run_id="$(gh run list --workflow="Windows build" --branch "$branch" -L 1 --json databaseId --jq '.[0].databaseId')"
if [[ -z "$run_id" || "$run_id" == "null" ]]; then
  echo "Could not find the workflow run. Check: gh run list --workflow=\"Windows build\"" >&2
  exit 1
fi

echo "Waiting for workflow run $run_id ..."
if ! gh run watch "$run_id" --exit-status; then
  echo "Kenny Windows build failed. Logs:" >&2
  gh run view "$run_id" --log-failed >&2 || true
  exit 1
fi

rm -f "$output_zip"
gh run download "$run_id" --name kenny-CameraStream-Windows --dir "$root/dist/windows"

if [[ ! -f "$output_zip" ]]; then
  echo "Download finished but $output_zip was not found." >&2
  ls -la "$root/dist/windows" >&2 || true
  exit 1
fi

echo
echo "Created $output_zip"
echo "Bundled workspaces from: $workspaces_source"
echo "Bundled credentials from: $credentials_source"
echo
echo "Send this zip privately to your Windows colleague."
echo "They should extract it and double-click: Install Kenny Camera Stream.bat"
echo "Share like a credential — never commit or upload to a public link."
