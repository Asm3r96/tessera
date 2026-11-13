#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -I "$bin/Modules" "$bin"/TesseraCore.build/*.swift.o \
    Sources/Tessera/TileSession.swift tests/FocusChecks/main.swift \
    -o "$tmp/FocusChecks"
"$tmp/FocusChecks"
