#!/bin/bash
# Builds bada.
#
#   scripts/build.sh            build/Bada.app
#   scripts/build.sh --install  also copies it to /Applications and opens it
#
# Needs an Apple Silicon Mac, the Xcode Command Line Tools and uv.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Bada.app"
BUNDLE_ID="app.bada.mac"
ENGINE_ENV="$HOME/Library/Application Support/Bada/python"

step() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "arm64" ]] || fail "MLX needs an Apple Silicon Mac."
command -v swift >/dev/null || fail "Install the Xcode Command Line Tools: xcode-select --install"
command -v uv >/dev/null || fail "Install uv: brew install uv"

step "Speech engine environment"
[[ -x "$ENGINE_ENV/bin/python3" ]] || uv venv --quiet --python 3.12 "$ENGINE_ENV"
uv pip install --quiet --python "$ENGINE_ENV/bin/python3" -r engine/requirements.txt

step "Compiling"
swift build -c release --arch arm64
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/Bada"

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Bada"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp engine/engine.py "$APP/Contents/Resources/engine.py"
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

if [[ "${1:-}" == "--install" ]]; then
  step "Installing /Applications/Bada.app"
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
  rm -rf /Applications/Bada.app
  cp -R "$APP" /Applications/
  open /Applications/Bada.app
fi
echo "Done."
