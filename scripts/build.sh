#!/bin/bash
# Builds mal2geul (말2글).
#
#   scripts/build.sh            build/말2글.app
#   scripts/build.sh --install  also copies it to /Applications and opens it
#   scripts/build.sh --dmg      also packages build/Mal2geul-<version>.dmg for a release
#
# Needs an Apple Silicon Mac and the Xcode Command Line Tools. The app sets up its own
# speech engine (Python + MLX) on first launch.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/말2글.app"
BUNDLE_ID="app.mal2geul.mac"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"

step() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "arm64" ]] || fail "MLX needs an Apple Silicon Mac."
command -v swift >/dev/null || fail "Install the Xcode Command Line Tools: xcode-select --install"

step "Compiling mal2geul $VERSION"
swift build -c release --arch arm64
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/Mal2geul"

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Mal2geul"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp engine/engine.py engine/requirements.txt "$APP/Contents/Resources/"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

step "Signing"
scripts/sign.sh "$APP"

case "${1:-}" in
  --install)
    step "Installing /Applications/말2글.app"
    osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/말2글.app"
    cp -R "$APP" /Applications/
    open "/Applications/말2글.app"
    ;;
  --dmg)
    DMG="build/Mal2geul-$VERSION.dmg"
    step "Packaging $DMG"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -quiet -volname "말2글" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
    rm -rf "$STAGE"
    shasum -a 256 "$DMG"
    ;;
esac
echo "Done."
