#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -workspace ztabby.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION

set -o pipefail && xcodebuild test -workspace ztabby.xcworkspace -scheme Test -configuration Release | scripts/xcbeautify
