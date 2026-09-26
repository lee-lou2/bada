#!/bin/bash
# Signs with a Developer ID identity and notarizes with Apple, so Gatekeeper opens
# the app without the "Apple can't check it for malware" warning.
#
# Prerequisites, once:
# 1. Apple Developer Program membership (https://developer.apple.com).
# 2. A "Developer ID Application" certificate in the login keychain
#    (Xcode → Settings → Accounts → Manage Certificates).
# 3. Credentials saved for notarytool (app-specific password from appleid.apple.com):
#      xcrun notarytool store-credentials mal2geul \
#        --apple-id you@example.com --team-id XXXXXXXXXX --password <password>
#
# Usage: MAL2GEUL_SIGN_IDENTITY="Developer ID Application: …" scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${MAL2GEUL_NOTARY_PROFILE:-mal2geul}"
IDENTITY="${MAL2GEUL_SIGN_IDENTITY:?Set MAL2GEUL_SIGN_IDENTITY to your Developer ID Application identity}"
APP="build/말2글.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/Mal2geul-$VERSION.dmg"

step() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

step "Building and signing with $IDENTITY"
scripts/build.sh

step "Submitting the app to Apple (a few minutes)"
ARCHIVE="$(mktemp -d)/app.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait
rm -f "$ARCHIVE"
xcrun stapler staple "$APP"

step "Packaging and submitting $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "말2글" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Verifying"
spctl -a -vv -t exec "$APP"
shasum -a 256 "$DMG"
