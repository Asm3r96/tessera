#!/bin/bash
# Builds Tessera.app and signs it. Releases are universal (Apple silicon and Intel); local builds use this Mac's architecture.
# Usage: ./build.sh          build into .build/app/Tessera.app
#        ./build.sh install  build, copy to ~/Applications and launch
#        ./build.sh release  build and zip into .build/app/Tessera.zip (set VERSION, for example 0.2.0)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${TESSERA_IDENTITY:-Tessera Local Signing}"
OUT=".build/app"
APP="$OUT/Tessera.app"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# macOS keys the Accessibility permission to the app's signature. An ad-hoc
# signature changes on every build, so macOS would ask again after each rebuild.
# A self-signed certificate, made once per Mac, keeps the signature stable.
provision_identity() {
  security find-identity -p codesigning | grep -qF "\"$IDENTITY\"" && return 0
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
# The Command Line Tools lack the Intel compatibility libraries that KeyboardShortcuts needs,
# so only release builds (made on CI with Xcode) are universal.
if [ "${1:-}" = release ]; then ARCHS=(--arch arm64 --arch x86_64); else ARCHS=(--arch "$(uname -m)"); fi
swift build -c release "${ARCHS[@]}" --product Tessera
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Tessera" "$APP/Contents/MacOS/Tessera"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN/KeyboardShortcuts_KeyboardShortcuts.bundle" "$APP/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
cp .build/checkouts/KeyboardShortcuts/license "$APP/Contents/Resources/KeyboardShortcuts-LICENSE"
if [ -n "${VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
else
  # Source builds show the commit, for example 0.1.0-2-g21bead2, so bug reports name the exact code.
  DESCRIBE="$(git describe --tags --always --dirty 2>/dev/null || true)"
  [ -n "$DESCRIBE" ] && plutil -replace CFBundleShortVersionString -string "${DESCRIBE#v}" "$APP/Contents/Info.plist"
fi
codesign --force --options runtime --sign "$IDENTITY" --identifier com.moe.tessera "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

case "${1:-}" in
  install)
    pkill -x Tessera || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Tessera.app"
    ditto "$APP" "$HOME/Applications/Tessera.app"
    open "$HOME/Applications/Tessera.app"
    echo "Installed $HOME/Applications/Tessera.app"
    ;;
  release)
    rm -f "$OUT/Tessera.zip"
    ditto -c -k --keepParent "$APP" "$OUT/Tessera.zip"
    echo "Packed $OUT/Tessera.zip"
    ;;
esac
