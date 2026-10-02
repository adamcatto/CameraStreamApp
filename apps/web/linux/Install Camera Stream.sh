#!/usr/bin/env bash
# Install Camera Stream for the current user (no sudo), add it to the application
# menu, and launch it.
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)/CameraStream"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/camera-stream"
applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
bin_dir="$HOME/.local/bin"

fail() {
  echo "ERROR: $1" >&2
  if [[ ! -t 2 ]] && command -v zenity >/dev/null 2>&1; then
    zenity --error --title="Camera Stream" --text="$1" 2>/dev/null || true
  fi
  exit 1
}

[[ -x "$source_dir/camera-stream" && -x "$source_dir/runtime/node" ]] \
  || fail "Extract the full zip first. The CameraStream folder must sit next to this installer."
[[ "$(uname -s)" == "Linux" ]] || fail "This package is for Linux."

echo "Installing Camera Stream to $dest ..."
if [[ -x "$dest/camera-stream" ]]; then
  "$dest/camera-stream" --stop >/dev/null 2>&1 || true
fi
rm -rf "$dest"
mkdir -p "$dest" "$applications" "$bin_dir"
cp -R "$source_dir"/. "$dest/"
if [[ -d "$dest/app/profile" ]]; then
  chmod 700 "$dest/app/profile"
  chmod 600 "$dest/app/profile"/*.json
fi

ln -sf "$dest/camera-stream" "$bin_dir/camera-stream"

cat >"$applications/camera-stream.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Camera Stream
Comment=View and control Raspberry Pi camera workspaces
Exec="$dest/camera-stream"
Icon=$dest/icon.png
Terminal=false
Categories=Video;Network;
Actions=Stop;

[Desktop Action Stop]
Name=Stop Camera Stream
Exec="$dest/camera-stream" --stop
EOF
chmod +x "$applications/camera-stream.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$applications" >/dev/null 2>&1 || true

echo "Installed. Camera Stream is now in your applications menu (and \`camera-stream\` in ~/.local/bin)."
echo "Starting Camera Stream ..."
exec "$dest/camera-stream"
