# Contributing to Tessera

Thank you for helping. Issues and pull requests are welcome.

## Report a bug

Open a [bug report](https://github.com/Asm3r96/tessera/issues/new?template=bug.yml). Include:

1. Your macOS version and Mac model (Apple silicon or Intel).
2. The Tessera version. It shows at the bottom left of the menu bar panel, next to **Quit**.
3. The steps that cause the bug, what you expected, and what happened.
4. The apps involved. Some apps limit how small their windows can get.

## Suggest a feature

Open a [feature request](https://github.com/Asm3r96/tessera/issues/new?template=feature.yml). Describe the problem first, then your idea. For a large change, wait for a reply before you write code.

## Send a pull request

1. Fork the repository and create a branch from `main`.
2. Build and test on a real Mac:

   ```sh
   swift build
   swift run TesseraChecks
   ./build.sh install
   ```

3. Keep the change small and focused on one thing.
4. Update `README.md` when behavior changes. Do not add network requests beyond the update check. If you change layout or resize math in `Sources/TesseraCore`, update `site/index.html` too.
5. Open the pull request and describe what you changed and how you tested it.

Read [AGENTS.md](AGENTS.md) for the code rules. You need only the Apple Command Line Tools. Xcode is not required.

## Rules for `main`

- All changes go through a pull request.
- The **Checks** workflow must pass before a merge.
- Pull requests are squash-merged.
- Workflows from first-time contributors run only after the maintainer approves them.

## Security

Do not report a security problem in a public issue. Use [private vulnerability reporting](https://github.com/Asm3r96/tessera/security/advisories/new).
