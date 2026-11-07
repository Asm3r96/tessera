# Tessera

A small menu bar app that arranges your windows into saved modes. For personal use on macOS 14 or later. Xcode is not required; the Command Line Tools are enough.

## Build

1. Run `./build.sh install`.
2. On the first run, allow Tessera under System Settings › Privacy & Security › Accessibility.

The first build creates a local signing certificate, "Tessera Local Signing", in your login keychain. Every later build uses it, so macOS keeps the Accessibility permission after a rebuild.

## Use

- Click the menu bar icon and click a mode. Tessera arranges the windows on the screen under the mouse.
- Press ⌃⌥1 to ⌃⌥9 to apply the mode at that position.
- The frontmost window goes into the largest zone. The next windows fill the other zones. Extra windows stay where they are.
- Drag the edge between two arranged windows: every window on that edge resizes with it.
- Hover a mode and click the sliders icon to edit columns, widths and rows.
