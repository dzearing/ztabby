#!/bin/bash
# Builds (incrementally) and launches the Debug app with debug logging.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo/DerivedData/Build/Products/Debug/Ztabby-Debug.app"

"$repo/ai/build.sh"

# Launch via `open` (launchd-parented) rather than running the binary directly:
# a shell-parented process gets the wrong Accessibility attribution and the
# window list comes back empty. Kill any existing instance first so `open`
# starts a fresh one instead of just activating the old build.
pkill -f Ztabby-Debug 2>/dev/null || true
sleep 1
open "$app" --args --logs=debug
