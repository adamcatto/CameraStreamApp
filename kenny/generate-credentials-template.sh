#!/usr/bin/env bash
# Generate kenny/credentials.local.json with one entry per workspace.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
workspaces_source="${1:-}"
output="${2:-$root/kenny/credentials.local.json}"

if [[ -z "$workspaces_source" ]]; then
  if [[ -f "$HOME/Library/Application Support/CameraStream/workspaces.json" ]]; then
    workspaces_source="$HOME/Library/Application Support/CameraStream/workspaces.json"
  elif [[ -f "$root/sandbox/workspaces.local.json" ]]; then
    workspaces_source="$root/sandbox/workspaces.local.json"
  fi
fi

if [[ -z "$workspaces_source" || ! -f "$workspaces_source" ]]; then
  echo "Usage: $0 [workspaces.json] [output-credentials.json]" >&2
  exit 1
fi

python3 - "$workspaces_source" "$output" <<'PY'
import json, sys
workspaces = json.load(open(sys.argv[1]))
entries = []
for workspace in workspaces:
    entry = {"workspaceName": workspace["name"], "cameraPassword": ""}
    if workspace.get("jumpHost"):
        entry["jumpPassword"] = ""
    entries.append(entry)
json.dump(entries, open(sys.argv[2], "w"), indent=2)
print(f"Wrote {sys.argv[2]} with {len(entries)} workspace credential entries.")
print("Add cameraPassword (and jumpPassword if needed) for each workspace, then run ./package-kenny-dmg.sh")
PY
