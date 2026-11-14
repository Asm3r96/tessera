#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin="$(swift build --show-bin-path)"
# Swift 6.2+ (swiftbuild) and the native build system put modules and objects in different places.
if [ -d "$bin/Modules" ]; then mods="$bin/Modules"; else mods="$bin"; fi
objects() { if [ -d "$bin/$1.build" ]; then ls "$bin/$1.build"/*.swift.o; else echo "$bin/$1.o"; fi; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -I "$mods" $(objects TesseraCore) \
    Sources/Tessera/TileSession.swift tests/FocusChecks/main.swift \
    -o "$tmp/FocusChecks"
"$tmp/FocusChecks"
