#!/usr/bin/env bash
# Build private, preloaded Camera Stream installers for macOS, Windows, and Linux in
# one step, ready to upload to a restricted shared folder.
#
#   ./config/profiles/package-profile-bundles.sh --name "Kenny Lab" --only "IVSA,motioncage,mousemingle"
#
# Options:
#   --name NAME          Label used in the zip names (default: Lab)
#   --only A,B,C         Bundle only these workspaces (case-insensitive; exact name
#                        or a unique part of it). Default: every workspace.
#   --workspaces FILE    Workspace JSON (default: the macOS app's saved workspaces,
#                        then config/sandbox/workspaces.local.json)
#   --credentials FILE   Credentials JSON (default: config/profiles/credentials.local.json)
#   --platforms LIST     Any of macos,windows,linux (default: all three)
#
# Output: dist/profiles/<name>/CameraStream-<name>-{macOS,Windows,Linux}.zip plus a
# README. The zips contain hosts and passwords: share them only with lab members.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
name="Lab"
only=""
workspaces_source=""
credentials_source=""
platforms="macos,windows,linux"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --workspaces) workspaces_source="$2"; shift 2 ;;
    --credentials) credentials_source="$2"; shift 2 ;;
    --platforms) platforms="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

slug="$(printf '%s' "$name" | tr -cs 'A-Za-z0-9' '-' | sed 's/^-*//; s/-*$//')"
[[ -n "$slug" ]] || { echo "--name must contain letters or numbers." >&2; exit 1; }

if [[ -z "$workspaces_source" ]]; then
  if [[ -f "$HOME/Library/Application Support/CameraStream/workspaces.json" ]]; then
    workspaces_source="$HOME/Library/Application Support/CameraStream/workspaces.json"
  elif [[ -f "$repo_root/config/sandbox/workspaces.local.json" ]]; then
    workspaces_source="$repo_root/config/sandbox/workspaces.local.json"
  else
    echo "No workspace file found. Pass --workspaces FILE or create config/sandbox/workspaces.local.json." >&2
    exit 1
  fi
fi
[[ -f "$workspaces_source" ]] || { echo "Workspace file not found: $workspaces_source" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/profile-bundles.XXXXXX")"
trap 'rm -rf "$work"' EXIT
selected="$work/workspaces.json"

python3 - "$workspaces_source" "$only" "$selected" <<'PY'
import json, sys
workspaces = json.load(open(sys.argv[1]))
tokens = [token.strip() for token in sys.argv[2].split(",") if token.strip()]
if tokens:
    chosen = []
    for token in tokens:
        key = token.lower()
        matches = [w for w in workspaces if w["name"].lower() == key] or [w for w in workspaces if key in w["name"].lower()]
        if len(matches) != 1:
            names = ", ".join(w["name"] for w in workspaces)
            problem = "matches no workspace" if not matches else "matches several workspaces"
            raise SystemExit(f'"{token}" {problem}. Available: {names}')
        if matches[0] not in chosen:
            chosen.append(matches[0])
    workspaces = [w for w in workspaces if w in chosen]
if not workspaces:
    raise SystemExit("No workspaces to bundle.")
json.dump(workspaces, open(sys.argv[3], "w"), indent=2)
print("Bundling workspaces: " + ", ".join(w["name"] for w in workspaces))
PY

if [[ -z "$credentials_source" ]]; then
  credentials_source="$repo_root/config/profiles/credentials.local.json"
fi
if [[ ! -f "$credentials_source" ]]; then
  "$repo_root/config/profiles/generate-credentials-template.sh" "$selected" "$credentials_source"
  echo "Fill in the passwords in $credentials_source, then run this script again." >&2
  exit 1
fi
# Fail fast on missing passwords before any slow build starts.
python3 "$repo_root/config/profiles/bundle-credentials.py" "$selected" "$credentials_source" "$work/check.json"

out="$repo_root/dist/profiles/$slug"
rm -rf "$out"
mkdir -p "$out"
built=()
skipped=()

# Each step ends in `|| return 1`: `set -e` does not apply inside a function called
# from `||`, and a failed build must never ship a stale zip from an earlier run.
build_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skipped+=("macOS (build it on a Mac)")
    return 0
  fi
  local folder="$work/macos/Camera Stream ($name)"
  "$repo_root/apps/macos/scripts/package-profiles-dmg.sh" "$selected" "$credentials_source" || return 1
  mkdir -p "$folder" || return 1
  ditto "$repo_root/dist/macos/Camera Stream.app" "$folder/Camera Stream.app" || return 1
  cp "$repo_root/config/profiles/Install Profiles Camera Stream.command" "$folder/Install Camera Stream.command" || return 1
  chmod +x "$folder/Install Camera Stream.command" || return 1
  ditto -c -k --sequesterRsrc --keepParent "$folder" "$out/CameraStream-$slug-macOS.zip" || return 1
  built+=("$out/CameraStream-$slug-macOS.zip")
}

build_windows() {
  local zip="$repo_root/dist/windows/profiles-CameraStream-Windows.zip"
  rm -f "$zip"
  "$repo_root/apps/windows/scripts/package-profiles-on-macos.sh" "$selected" "$credentials_source" || return 1
  cp "$zip" "$out/CameraStream-$slug-Windows.zip" || return 1
  built+=("$out/CameraStream-$slug-Windows.zip")
}

build_linux() {
  local zip="$repo_root/dist/linux/profiles-CameraStream-Linux-x64.zip"
  rm -f "$zip"
  CAMERA_STREAM_LINUX_ARCH=x64 "$repo_root/apps/web/scripts/package-profiles-linux.sh" "$selected" "$credentials_source" || return 1
  cp "$zip" "$out/CameraStream-$slug-Linux.zip" || return 1
  built+=("$out/CameraStream-$slug-Linux.zip")
}

IFS=',' read -r -a requested <<<"$platforms"
for platform in "${requested[@]}"; do
  platform="$(printf '%s' "$platform" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  echo
  echo "=== $platform ==="
  case "$platform" in
    macos|mac) build_macos || skipped+=("macOS (build failed; see output above)") ;;
    windows|win) build_windows || skipped+=("Windows (build failed; see output above)") ;;
    linux) build_linux || skipped+=("Linux (build failed; see output above)") ;;
    *) echo "Unknown platform: $platform" >&2; exit 1 ;;
  esac
done

python3 - "$repo_root/config/profiles/INSTALL-README.txt" "$out/README - How to install.txt" "$name" "$slug" <<'PY'
import sys
text = open(sys.argv[1]).read().replace("{{NAME}}", sys.argv[3]).replace("{{SLUG}}", sys.argv[4])
open(sys.argv[2], "w").write(text)
PY

echo
echo "================================================================"
if [[ ${#built[@]} -gt 0 ]]; then
  echo "Ready to upload (from $out):"
  for file in "${built[@]}"; do echo "  $(basename "$file")"; done
  echo "  README - How to install.txt"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Not built:"
  for item in "${skipped[@]}"; do echo "  $item"; done
fi
echo
echo "These zips contain camera hosts and passwords. Upload them only to a Google Drive"
echo "folder shared with specific lab members (General access: Restricted), never to"
echo "\"Anyone with the link\" or to GitHub."
[[ ${#built[@]} -gt 0 ]]
