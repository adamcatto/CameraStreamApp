#!/usr/bin/env bash
# Build a private Linux zip of the web client with profile workspaces and passwords
# bundled. Runs on macOS or Linux; it downloads the Linux Node.js runtime and FFmpeg
# for the target architecture, so the result needs nothing preinstalled.
#
#   ./apps/web/scripts/package-profiles-linux.sh [workspaces.json] [credentials.json]
#
# CAMERA_STREAM_LINUX_ARCH=x64|arm64 selects the target (default x64).
# CAMERA_STREAM_NODE_RELEASE selects the Node.js line (default latest-v22.x).
set -euo pipefail

web_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$web_root/../.." && pwd)"
arch="${CAMERA_STREAM_LINUX_ARCH:-x64}"
node_release="${CAMERA_STREAM_NODE_RELEASE:-latest-v22.x}"
workspaces_source="${1:-}"
credentials_source="${2:-}"
dist="$repo_root/dist/linux"
output_zip="$dist/profiles-CameraStream-Linux-$arch.zip"

case "$arch" in
  x64|arm64) ;;
  *) echo "Unsupported CAMERA_STREAM_LINUX_ARCH: $arch (use x64 or arm64)" >&2; exit 1 ;;
esac

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
  ./apps/web/scripts/package-profiles-linux.sh [workspaces.json] [credentials.json]

Or ensure one of these exists:
  ~/Library/Application Support/CameraStream/workspaces.json
  config/sandbox/workspaces.local.json
EOF
  exit 1
fi
if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
  echo "No credentials file found. Generating config/profiles/credentials.local.json template..." >&2
  "$repo_root/config/profiles/generate-credentials-template.sh" "$workspaces_source" "$repo_root/config/profiles/credentials.local.json"
  echo "Add passwords to config/profiles/credentials.local.json, then run this script again." >&2
  exit 1
fi
for tool in npm python3 curl tar zip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/profiles-linux.XXXXXX")"
trap 'rm -rf "$work"' EXIT
bundle="$work/bundle"
payload="$bundle/CameraStream"
app="$payload/app"
mkdir -p "$app/server" "$app/profile" "$payload/runtime" "$dist"
chmod 700 "$app/profile"

python3 -m json.tool "$workspaces_source" >/dev/null || { echo "Workspace file is not valid JSON: $workspaces_source" >&2; exit 1; }
cp "$workspaces_source" "$app/profile/profiles-workspaces.json"
python3 "$repo_root/config/profiles/bundle-credentials.py" "$workspaces_source" "$credentials_source" "$app/profile/profiles-credentials.json"
chmod 600 "$app/profile"/*.json

echo "Building the web client ..."
if [[ ! -x "$repo_root/node_modules/.bin/esbuild" ]]; then
  (cd "$repo_root" && npm ci)
fi
(cd "$repo_root" && npm run web:build)
cp -R "$web_root/dist" "$app/dist"
"$repo_root/node_modules/.bin/esbuild" "$web_root/server/index.ts" \
  --bundle --platform=node --format=esm --target=node20 --packages=external \
  --log-level=warning --outfile="$app/server/index.mjs"

echo "Installing Linux $arch runtime dependencies ..."
python3 - "$web_root/package.json" "$app/package.json" <<'PY'
import json, sys
dependencies = json.load(open(sys.argv[1]))["dependencies"]
runtime = {name: dependencies[name] for name in ("ffmpeg-static", "ssh2", "ws")}
json.dump({"name": "camera-stream-linux", "private": True, "type": "module", "dependencies": runtime}, open(sys.argv[2], "w"), indent=2)
PY
(
  cd "$app"
  npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-package-lock --os=linux --cpu="$arch" >/dev/null
  npm_config_platform=linux npm_config_arch="$arch" node node_modules/ffmpeg-static/install.js
  rm -rf node_modules/.bin
)
[[ -x "$app/node_modules/ffmpeg-static/ffmpeg" ]] || { echo "FFmpeg for linux-$arch was not downloaded." >&2; exit 1; }

echo "Downloading Node.js ($node_release, linux-$arch) ..."
node_base="https://nodejs.org/dist/$node_release"
curl -fsSL "$node_base/SHASUMS256.txt" -o "$work/SHASUMS256.txt"
node_archive="$(awk -v suffix="-linux-$arch.tar.gz" '$2 ~ suffix"$" { print $2 }' "$work/SHASUMS256.txt" | head -n 1)"
[[ -n "$node_archive" ]] || { echo "No linux-$arch Node.js archive listed at $node_base" >&2; exit 1; }
curl -fsSL "$node_base/$node_archive" -o "$work/$node_archive"
expected="$(awk -v name="$node_archive" '$2 == name { print $1 }' "$work/SHASUMS256.txt")"
if command -v sha256sum >/dev/null 2>&1; then actual="$(sha256sum "$work/$node_archive" | awk '{ print $1 }')"
else actual="$(shasum -a 256 "$work/$node_archive" | awk '{ print $1 }')"; fi
[[ "$expected" == "$actual" ]] || { echo "Checksum mismatch for $node_archive" >&2; exit 1; }
node_dir="${node_archive%.tar.gz}"
tar -xzf "$work/$node_archive" -C "$work" "$node_dir/bin/node" "$node_dir/LICENSE"
mv "$work/$node_dir/bin/node" "$payload/runtime/node"
mv "$work/$node_dir/LICENSE" "$payload/runtime/NODE-LICENSE"

cp "$web_root/linux/camera-stream" "$payload/camera-stream"
cp "$repo_root/apps/macos/Resources/Assets/CameraStreamIcon.png" "$payload/icon.png"
cp "$web_root/linux/Install Camera Stream.sh" "$web_root/linux/Run Camera Stream.sh" "$bundle/"
chmod +x "$payload/camera-stream" "$payload/runtime/node" "$bundle"/*.sh

rm -f "$output_zip"
(cd "$bundle" && zip -qry "$output_zip" .)

echo
echo "Profiles Linux zip:"
echo "$output_zip"
echo "Bundled workspaces from: $workspaces_source"
echo "Bundled credentials from: $credentials_source"
echo "Share this zip privately - it contains workspace hosts and passwords."
echo "Users extract it and run: Install Camera Stream.sh"
