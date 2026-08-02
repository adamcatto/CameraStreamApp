#!/usr/bin/env bash
# Build a Kenny Windows zip entirely on your Mac.
# Downloads the credential-free Windows app from GitHub Actions,
# then bundles lab workspaces + credentials locally. Credentials never leave your Mac.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
workspaces_source="${1:-}"
credentials_source="${2:-}"
branch="${CAMERA_STREAM_WINDOWS_BRANCH:-windows-port}"
bundle_file="$root/dist/kenny-credentials.bundle.json"
output_zip="$root/dist/windows/kenny-CameraStream-Windows.zip"
kenny_bat="$root/windows/kenny/Install Kenny Camera Stream.bat"

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

if [[ ! -f "$kenny_bat" ]]; then
  echo "Missing Kenny installer: $kenny_bat" >&2
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

if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
The GitHub CLI (gh) is required to download the credential-free Windows app.
Install with: brew install gh
Then run: gh auth login
EOF
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run 'gh auth login' before building the Kenny Windows zip." >&2
  exit 1
fi

download_dir="$(mktemp -d "${TMPDIR:-/tmp}/kenny-windows-download.XXXXXX")"
base_zip=""
selected_run_id=""
while IFS= read -r run_id; do
  [[ -z "$run_id" ]] && continue
  rm -rf "$download_dir"/*
  echo "Trying credential-free CameraStream-Windows artifact from run $run_id ..."
  if gh run download "$run_id" --name CameraStream-Windows --dir "$download_dir" 2>/dev/null \
    && [[ -f "$download_dir/CameraStream-Windows.zip" ]]; then
    base_zip="$download_dir/CameraStream-Windows.zip"
    selected_run_id="$run_id"
    echo "Downloaded base app from run $run_id"
    break
  fi
done < <(gh run list --workflow="Windows build" --branch "$branch" -L 30 \
  --json databaseId,conclusion \
  --jq '.[] | select(.conclusion == "success") | .databaseId')

if [[ -z "$base_zip" ]]; then
  echo "No successful Windows build with a CameraStream-Windows artifact found on branch $branch." >&2
  rm -rf "$download_dir"
  exit 1
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/kenny-windows-staging.XXXXXX")"
cleanup() {
  rm -rf "$staging"
  [[ -n "$download_dir" ]] && rm -rf "$download_dir"
  rm -f "$bundle_file"
}
trap cleanup EXIT

unzip -q "$base_zip" -d "$staging"

app_dir="$staging"
if [[ ! -f "$app_dir/CameraStream.Windows.exe" ]]; then
  shopt -s nullglob
  subdirs=("$staging"/*/)
  shopt -u nullglob
  if [[ ${#subdirs[@]} -eq 1 && -f "${subdirs[0]}CameraStream.Windows.exe" ]]; then
    app_dir="${subdirs[0]}"
  else
    echo "CameraStream.Windows.exe not found after extracting $base_zip" >&2
    find "$staging" -maxdepth 2 -type f >&2 || true
    exit 1
  fi
fi

cp "$workspaces_source" "$app_dir/kenny-workspaces.json"
cp "$bundle_file" "$app_dir/kenny-credentials.json"
chmod 600 "$app_dir/kenny-credentials.json"
cp "$kenny_bat" "$app_dir/Install Kenny Camera Stream.bat"

rm -f "$output_zip"
(
  cd "$app_dir"
  zip -qr "$output_zip" .
)

if [[ ! -f "$output_zip" ]]; then
  echo "Failed to create $output_zip" >&2
  exit 1
fi

output_zip_abs="$(cd "$(dirname "$output_zip")" && pwd)/$(basename "$output_zip")"

echo
echo "Kenny Windows zip:"
echo "$output_zip_abs"
echo
echo "Bundled workspaces from: $workspaces_source"
echo "Bundled credentials from: $credentials_source"
echo "Base Windows app downloaded from GitHub Actions run $selected_run_id (no secrets sent to GitHub)."
echo
echo "Credentials were bundled locally on this Mac only."
echo "Send this zip privately to your Windows colleague."
echo "They should extract it and double-click: Install Kenny Camera Stream.bat"
