#!/bin/bash
# Build, sign, notarize, staple, and publish a GitHub release with a Sparkle appcast.
# Usage: VERSION=1.1 ./release.sh   (needs notarytool profile "roar" and the Sparkle EdDSA key in Keychain)
set -euo pipefail
VERSION="${VERSION:?set VERSION}"
export VERSION
./generate_app.sh
DIST="dist"; rm -rf "$DIST"; mkdir -p "$DIST"
ZIP="$DIST/WhisperWrap-${VERSION}.zip"
ditto -c -k --keepParent WhisperWrap.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile roar --wait
xcrun stapler staple WhisperWrap.app
spctl -a -vv -t exec WhisperWrap.app
rm "$ZIP"; ditto -c -k --keepParent WhisperWrap.app "$ZIP"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/akeslo/WhisperWrap/releases/download/v${VERSION}/" "$DIST"
gh release create "v${VERSION}" "$ZIP" "$DIST/appcast.xml" --title "WhisperWrap v${VERSION}" --generate-notes
