#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/SettingsChecks.app"
mkdir -p "$app/Contents/MacOS"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>at.m-reschreiter.tessera.settings-checks</string><key>CFBundleExecutable</key><string>SettingsChecks</string><key>LSUIElement</key><true/></dict></plist>' > "$app/Contents/Info.plist"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources/Tessera -name '*.swift' ! -name TesseraApp.swift | sort)
swiftc -I "$bin/Modules" "$bin"/TesseraCore.build/*.swift.o "$bin"/KeyboardShortcuts.build/*.swift.o \
    "${sources[@]}" tests/SettingsChecks/main.swift -o "$app/Contents/MacOS/SettingsChecks"
ditto "$bin/KeyboardShortcuts_KeyboardShortcuts.bundle" "$app/KeyboardShortcuts_KeyboardShortcuts.bundle"
"$app/Contents/MacOS/SettingsChecks"
