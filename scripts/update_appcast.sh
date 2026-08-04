#!/usr/bin/env bash
# Prepends a release item to docs/appcast.xml so Sparkle picks up the update.
# Runs on the ubuntu update-website job (GNU coreutils; no BSD-only flags).
# Required env:
#   VERSION                  e.g. 0.3.1
#   ED_SIGNATURE_AND_LENGTH  sign_update output: sparkle:edSignature="..." length="..."

set -eu

date="$(date +'%a, %d %b %Y %H:%M:%S %z')"
minimumSystemVersion="$(awk -F ' = ' '/MACOSX_DEPLOYMENT_TARGET/ { print $2; exit }' config/base.xcconfig)"
dmgName="Ztabby_${VERSION}_aarch64.dmg"

cat > /tmp/appcast-item.xml <<XML
    <item>
      <title>Version $VERSION</title>
      <pubDate>$date</pubDate>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/dzearing/ztabby/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/dzearing/ztabby/releases/download/v$VERSION/$dmgName"
        sparkle:version="$VERSION"
        sparkle:shortVersionString="$VERSION"
        $ED_SIGNATURE_AND_LENGTH
        type="application/octet-stream"/>
    </item>
XML

awk '/<\/language>/ { print; while ((getline line < "/tmp/appcast-item.xml") > 0) print line; next } 1' \
  docs/appcast.xml > /tmp/appcast.xml
mv /tmp/appcast.xml docs/appcast.xml
