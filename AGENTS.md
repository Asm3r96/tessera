# Agent guide for Tessera

Tessera is a macOS menu bar app that tiles windows into saved modes. Read [README.md](README.md) for install, use and troubleshooting.

## Build and install

1. Check the toolchain with `swift --version`. If it is missing, ask the user to run `xcode-select --install`. Do not install Xcode.
2. Run `./build.sh install` from the repository root.
3. The first build on a Mac creates the "Tessera Local Signing" certificate. macOS then shows a keychain prompt for `codesign`. Tell the user to type the password and click **Always Allow**. The build waits until they do, so run it with a long timeout and while the user is at the screen.
4. Tell the user to turn on Tessera under System Settings › Privacy & Security › Accessibility. An agent cannot grant this permission.
5. Confirm with `pgrep -x Tessera` and `codesign -dr - ~/Applications/Tessera.app`. The designated requirement must name `certificate leaf`, not `cdhash`.

## Rules

- Keep the local signing certificate. An ad-hoc signature makes macOS ask for Accessibility again after every build.
- Do not add a trust step for the certificate. `security add-trusted-cert` opens a password prompt, and codesign does not need it.
- Install to `~/Applications`. `/Applications` can be write-protected on managed Macs.
- Do not use SwiftUI or Observation macros (`@State`, `@Observable`, `@Bindable`). The Command Line Tools do not include the macro plugins, so these fail to compile. Use `ObservableObject`, `@Published` and `@ObservedObject`.
- Use `swift build` to check compile errors before you install.
- The app is for personal use. Do not add App Store sandboxing; it blocks control of other apps' windows.
