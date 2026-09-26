#!/bin/bash
# Code-signs Bada.app.
#
#   scripts/sign.sh build/Bada.app
#   BADA_SIGN_IDENTITY="Developer ID Application: …" scripts/sign.sh build/Bada.app
#
# macOS remembers Microphone and Accessibility permission by code signature. An ad-hoc signature
# changes with every build, so those permissions would be lost each time. Without a Developer ID,
# this script signs with a self-signed identity kept in its own keychain in
# ~/Library/Application Support/Bada/signing. The login keychain and trust settings are untouched.
set -euo pipefail

APP="$1"
ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/Resources/Bada.entitlements"

sign() { codesign --force --options runtime --entitlements "$ENTITLEMENTS" "$@" "$APP"; }

if [[ -n "${BADA_SIGN_IDENTITY:-}" ]]; then
  sign --timestamp --sign "$BADA_SIGN_IDENTITY"
  exit 0
fi

DIR="$HOME/Library/Application Support/Bada/signing"
KEYCHAIN="$DIR/signing.keychain-db"
NAME="bada local signing"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "Creating a local signing identity in $DIR"
  mkdir -p "$DIR"
  chmod 700 "$DIR"
  (umask 077 && /usr/bin/openssl rand -hex 24 > "$DIR/password")
  WORK="$(mktemp -d)"
  cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout pass:transfer 2>/dev/null
  security create-keychain -p "$(cat "$DIR/password")" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN" # no auto-lock
  security unlock-keychain -p "$(cat "$DIR/password")" "$KEYCHAIN"
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P transfer -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$DIR/password")" "$KEYCHAIN" >/dev/null
  rm -rf "$WORK"
fi

security unlock-keychain -p "$(cat "$DIR/password")" "$KEYCHAIN"
IDENTITY="$(security find-certificate -c "$NAME" -Z "$KEYCHAIN" | awk '/SHA-1/ { print $NF }')"

# codesign only looks in the keychain search list, so add ours for this one call.
SEARCH_LIST=()
while IFS= read -r keychain; do SEARCH_LIST+=("$keychain"); done \
  < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/')
trap 'security list-keychains -d user -s "${SEARCH_LIST[@]}"' EXIT
security list-keychains -d user -s "${SEARCH_LIST[@]}" "$KEYCHAIN"
sign --sign "$IDENTITY"
