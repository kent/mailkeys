# AGENTS.md

Guidance for anyone changing MailKeys, human or coding agent. Read this before you touch the code.

## What this is

MailKeys is a macOS menu bar app that adds Gmail keyboard shortcuts to Apple Mail. It's plain Swift and AppKit, built with `swiftc` from a shell script. No Xcode project, no Swift packages, no dependencies.

## Commands

```sh
./build.sh                         # run the tests, then build, sign and install ~/Applications/MailKeys.app
MAILKEYS_APP_PATH=/tmp/MailKeys.app ./build.sh   # build somewhere else
./make-icon.sh                     # regenerate AppIcon.icns from the drawing code
MAILKEYS_SNAPSHOT=/some/dir ~/Applications/MailKeys.app/Contents/MacOS/MailKeys   # render the settings window to PNGs
```

`./build.sh` must pass before every commit. It compiles and runs `PolicyTests.swift` first and stops if a check fails.

## Layout

| File | Responsibility |
| --- | --- |
| `main.swift` | App delegate, menu bar item, the Mail-only event tap, Mail accessibility reads, diagnostics |
| `ShortcutPolicy.swift` | Key bindings and every rule for when a shortcut may act. Pure logic, no AppKit |
| `Responsiveness.swift` | Focus cache and the J/K glide state machine. Pure logic |
| `Usage.swift` | Shortcut counts and the time saved estimate. Pure logic |
| `SettingsUI.swift` | The settings window and the app icon, all drawn in code |
| `PolicyTests.swift` | Dependency-free test runner for the pure logic files |

Keep it that way. Decisions go in the pure files where they can be tested. `main.swift` gathers facts from Mail and asks the policy what to do.

## Rules that never bend

1. **Typing is sacred.** When MailKeys is unsure, the key passes through as ordinary typing. Search fields, compose windows, sheets, dialogs and other apps must never lose a keystroke. Any change to when a shortcut fires needs a test in `PolicyTests.swift`.
2. **Mail only.** The event tap is created with `tapCreateForPid` for Mail's process. Never add a global keyboard listener.
3. **No recording, no reading.** Never log, store or transmit keystrokes. Never read message contents, subjects, senders or account data. Accessibility reads stay structural: roles, identifiers, focus, positions, selection. Usage stats are one integer per shortcut in `UserDefaults`, nothing more.
4. **No network.** MailKeys makes no network requests. Don't add analytics, update checks or crash reporting without discussing it in an issue first.
5. **Don't trust stale state.** Re-check Mail's focus on every key press. The focus cache may only be reused for the same focused window and element (see `FocusSnapshotCache`).

## UI conventions

- Everything is drawn in code with small `NSView` subclasses. No asset catalogue, no XIBs or storyboards.
- Colours come from `Palette`. Use its dynamic colours so light and dark mode both work, and check both.
- After a visual change, render snapshots with `MAILKEYS_SNAPSHOT` and look at every state: no permission, ready, paused, Test Mode, light and dark.
- Keep the window height stable within a tab. Text must not clip or leave a single orphaned word.

## Writing style

For UI copy, docs and comments:

- Plain words, short sentences, contractions.
- No em dashes. Split the sentence instead.
- Sentence case for headings in the app ("Try it safely"). Title case for buttons and feature names ("Test Mode").
- Comments explain why, not what.

## Commits and pull requests

- Small, focused commits with a short imperative subject ("Keep the sidebar rhythm fixed across tabs").
- Describe what changed and how you checked it. For UI changes, attach before and after snapshots.
- Update `CHANGELOG.md` under "Unreleased" for anything a user would notice.
