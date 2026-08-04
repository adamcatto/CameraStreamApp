#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
source="$root/workspaces.local.json"
dest="$HOME/Library/Application Support/CameraStream/workspaces.json"

if [[ ! -f "$source" ]]; then
  echo "Missing $source" >&2
  echo "Copy workspaces.example.json to workspaces.local.json and edit it first." >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
cp "$source" "$dest"
echo "Imported $source → $dest"
echo "Launch Camera Stream to use the imported workspaces."
