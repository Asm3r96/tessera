#!/bin/bash
# Installs or updates Tessera from the latest GitHub release.
# Usage: curl -fsSL https://raw.githubusercontent.com/Asm3r96/tessera/main/install.sh | bash
set -euo pipefail

URL="https://github.com/Asm3r96/tessera/releases/latest/download/Tessera.zip"
DEST="$HOME/Applications"

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
  echo "Tessera needs macOS 14 or later." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Tessera..."
curl -fsSL "$URL" -o "$tmp/Tessera.zip"
ditto -x -k "$tmp/Tessera.zip" "$tmp"
codesign --verify --strict "$tmp/Tessera.app"

pkill -x Tessera 2>/dev/null || true
mkdir -p "$DEST"
rm -rf "$DEST/Tessera.app"
ditto "$tmp/Tessera.app" "$DEST/Tessera.app"
open "$DEST/Tessera.app"

echo "Installed $DEST/Tessera.app"
echo "First install: allow Tessera in System Settings > Privacy & Security > Accessibility."
