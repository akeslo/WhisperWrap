#!/bin/bash
# Build, sign, notarize, staple (app + DMG), and publish a GitHub release with a Sparkle appcast.
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
# DMG for first installs (built after the appcast so Sparkle keeps updating via the zip).
DMG="$DIST/WhisperWrap-${VERSION}.dmg"
STAGE="$(mktemp -d)"; ditto WhisperWrap.app "$STAGE/WhisperWrap.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname WhisperWrap -srcfolder "$STAGE" -format UDZO -ov "$DMG"; rm -rf "$STAGE"
codesign --force --timestamp --sign "Developer ID Application: Outsource Wisely LLC (MNJ22JRCB8)" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile roar --wait
xcrun stapler staple "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"
gh release create "v${VERSION}" "$DMG" "$ZIP" "$DIST/appcast.xml" --title "WhisperWrap v${VERSION}" --generate-notes
