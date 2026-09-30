#!/usr/bin/env bash
# Launch Camera Stream from the extracted zip without installing it.
exec "$(cd "$(dirname "$0")" && pwd)/CameraStream/camera-stream" "$@"
