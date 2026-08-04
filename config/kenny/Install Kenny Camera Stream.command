#!/usr/bin/env bash
set -euo pipefail

dmg_root="$(cd "$(dirname "$0")" && pwd)"
app_src="$dmg_root/Camera Stream.app"
app_dest="/Applications/Camera Stream.app"

if [[ ! -d "$app_src" ]]; then
  osascript -e 'display alert "Install failed" message "Camera Stream.app was not found next to this installer." as critical'
  exit 1
fi

echo "Installing Camera Stream to Applications..."
ditto "$app_src" "$app_dest"
xattr -cr "$app_dest" 2>/dev/null || true

echo "Done. Launching Camera Stream..."
open "$app_dest"
