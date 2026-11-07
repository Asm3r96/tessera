# Tessera

Tessera is a small menu bar app for macOS. It arranges your windows into saved layouts, called modes. When you resize one arranged window, the windows next to it resize with it.

It is a personal tool. It is not on the Mac App Store and it does not need an Apple Developer account.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- Apple Command Line Tools. Xcode is not required.

To check for the Command Line Tools, run `swift --version`. If the command is missing, run `xcode-select --install` and follow the dialog.

## Install

1. Clone the repository:

   ```sh
   git clone https://github.com/Asm3r96/tessera.git ~/dev/tessera
   cd ~/dev/tessera
   ```

2. Build, install and start the app:

   ```sh
   ./build.sh install
   ```

3. On the first build, macOS shows a keychain prompt for `codesign`. Type your Mac password and click **Always Allow**.
4. Open System Settings › Privacy & Security › Accessibility and turn on **Tessera**.
5. Press ⌃⌥1 to test.

The app installs to `~/Applications/Tessera.app`. A grid icon appears in the menu bar.

## Update

Pull the latest code and run the install again:

```sh
cd ~/dev/tessera
git pull
./build.sh install
```

The Accessibility permission stays after an update. You do not need to turn it on again.

## Build commands

| Command | Result |
| --- | --- |
| `./build.sh` | Builds and signs `build/Tessera.app`. |
| `./build.sh install` | Builds, copies the app to `~/Applications`, and starts it. |
| `swift build` | Compiles only. Use it to check for compile errors. |

## Signing

macOS links the Accessibility permission to the app's signature. A normal local (ad-hoc) signature changes on every build, so macOS would ask for permission after every rebuild.

To prevent this, `build.sh` creates a self-signed certificate called **Tessera Local Signing** in your login keychain. It does this once on each Mac. Every later build uses the same certificate, so the permission stays.

Each Mac gets its own certificate. You approve Accessibility once on each Mac.

## Use

- Click the menu bar icon, then click a mode. Tessera arranges the windows on the screen under the mouse.
- Press ⌃⌥1 to ⌃⌥9 to apply the mode at that position in the list.
- The frontmost window goes into the largest zone. The next windows fill the other zones. Extra windows stay where they are.
- Drag the edge between two arranged windows. Every window on that edge resizes with it.
- Use the **Gap** slider to set the space between windows.
- Turn on **Open at login** to start Tessera when you log in.

### Add or edit a mode

1. Click the menu bar icon.
2. Click **+** for a new mode. To edit a mode, hover over its card and click the sliders icon.
3. Set the name, the columns (up to 5), the width of each column, and the rows in each column (1 to 4).
4. Click **Save**.

Modes are saved in the app's user defaults (`com.moe.tessera`). They do not sync between Macs.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `./build.sh` hangs at the signing step | macOS is waiting at a hidden keychain prompt. Find it, type your password, and click **Always Allow**. |
| Shortcuts do nothing | Turn on Tessera under Privacy & Security › Accessibility. Then quit Tessera from its menu and open it again. |
| Tessera is on in Accessibility but windows do not move | The permission belongs to an old signature. Run `tccutil reset Accessibility com.moe.tessera`, start Tessera, and allow it again. |
| `cp: /Applications/...: Permission denied` | The app installs to `~/Applications`, not `/Applications`. Pull the latest `build.sh`. |
| `ld: warning: search path ... not found` | This warning is harmless with the Command Line Tools. Ignore it. |
| A window does not get the full zone size | Some apps have a minimum window size. Tessera cannot make them smaller. |

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/Tessera/TesseraApp.swift` | App entry point and menu bar item. |
| `Sources/Tessera/AppModel.swift` | Saved modes, settings, Accessibility check, shortcuts. |
| `Sources/Tessera/Mode.swift` | Mode model and zone layout math. |
| `Sources/Tessera/WindowArranger.swift` | Finds windows and moves them through the Accessibility API. |
| `Sources/Tessera/TileSession.swift` | Linked resizing of arranged windows. |
| `Sources/Tessera/HotKeys.swift` | Global shortcuts ⌃⌥1 to ⌃⌥9. |
| `Sources/Tessera/MenuPanel.swift` | Menu bar panel and mode editor UI. |
| `Resources/Info.plist` | Bundle settings. `LSUIElement` hides the Dock icon. |
| `build.sh` | Build, sign and install script. |
