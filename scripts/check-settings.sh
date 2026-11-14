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
app="$tmp/SettingsChecks.app"
mkdir -p "$app/Contents/MacOS"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>at.m-reschreiter.tessera.settings-checks</string><key>CFBundleExecutable</key><string>SettingsChecks</string><key>LSUIElement</key><true/></dict></plist>' > "$app/Contents/Info.plist"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources/Tessera -name '*.swift' ! -name TesseraApp.swift | sort)
swiftc -I "$mods" $(objects TesseraCore) $(objects KeyboardShortcuts) \
    "${sources[@]}" tests/SettingsChecks/main.swift -o "$app/Contents/MacOS/SettingsChecks"
ditto "$bin/KeyboardShortcuts_KeyboardShortcuts.bundle" "$app/KeyboardShortcuts_KeyboardShortcuts.bundle"
"$app/Contents/MacOS/SettingsChecks"
