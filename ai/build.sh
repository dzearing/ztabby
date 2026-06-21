#!/bin/bash
# Builds the Debug app into <repo>/DerivedData. Extra args are passed to xcodebuild.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Fall back to a full Xcode if the active toolchain is only CommandLineTools.
if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcodebuild \
  -workspace "$repo/ztabby.xcworkspace" \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath "$repo/DerivedData" \
  "$@"
