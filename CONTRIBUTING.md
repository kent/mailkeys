# Contributing to MailKeys

Thanks for wanting to make MailKeys better. Bug reports, ideas and pull requests are all welcome.

## Before you start

- Read [AGENTS.md](AGENTS.md). It covers the layout, the commands and the rules that never bend. The big one: **typing is sacred**. MailKeys must never eat a keystroke you meant to type.
- For anything bigger than a small fix, open an issue first so we can agree on the approach.

## Set up

You need macOS 13 or later, Apple Mail and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/kent/mailkeys.git
cd mailkeys
./build.sh
```

Open `~/Applications/MailKeys.app` and allow it under **System Settings → Privacy & Security → Accessibility**. See the README for signing with a stable identity, so the permission survives rebuilds.

## Making a change

1. Branch off `main`.
2. Keep decisions in the pure logic files (`ShortcutPolicy.swift`, `Responsiveness.swift`, `Usage.swift`) and add a check to `PolicyTests.swift` for any behaviour change.
3. Run `./build.sh`. It runs the tests first.
4. Try it for real in Mail. Test Mode (**Settings → Advanced**) lets you press shortcuts without acting on your mail.
5. For UI changes, render snapshots and check light and dark mode:
   ```sh
   MAILKEYS_SNAPSHOT=/tmp/mailkeys-shots ~/Applications/MailKeys.app/Contents/MacOS/MailKeys
   ```
6. Add a line to `CHANGELOG.md` under "Unreleased" if users will notice the change.

## Pull requests

- One focused change per pull request.
- Say what changed, why, and how you checked it. Attach before and after snapshots for UI changes.
- CI builds the app and runs the tests on macOS. It needs to pass.

## Reporting bugs

Use the bug report template. Include your macOS version, Mail version, what you pressed, what you expected and what happened. Test Mode output helps a lot.

Found a security or privacy problem? Please don't open a public issue. See [SECURITY.md](SECURITY.md).

## Code of conduct

Everyone taking part agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).
