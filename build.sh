#!/bin/bash
# Builds Tessera.app and signs it with a persistent local certificate.
# Usage: ./build.sh          build into build/Tessera.app
#        ./build.sh install  build, copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Tessera Local Signing"
APP="build/Tessera.app"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# macOS keys the Accessibility permission to the app's signature. An ad-hoc
# signature changes on every build, so macOS would ask again after each rebuild.
# A self-signed certificate, made once per Mac, keeps the signature stable.
provision_identity() {
  security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$IDENTITY\"" && return 0
  echo "Creating signing certificate \"$IDENTITY\"..."
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -subj "/CN=$IDENTITY" \
    -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/identity.p12" -passout pass:tessera >/dev/null 2>&1
  # No trust step: codesign signs with an untrusted self-signed certificate, and
  # marking it trusted would open a password prompt.
  security import "$tmp/identity.p12" -k "$KEYCHAIN" -P tessera -T /usr/bin/codesign >/dev/null
}

provision_identity
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Tessera "$APP/Contents/MacOS/Tessera"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "$IDENTITY" --identifier com.moe.tessera "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x Tessera || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Tessera.app"
  cp -R "$APP" "$HOME/Applications/Tessera.app"
  open "$HOME/Applications/Tessera.app"
  echo "Installed $HOME/Applications/Tessera.app"
fi
