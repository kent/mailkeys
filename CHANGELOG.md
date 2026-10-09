# Changelog

All notable changes to MailKeys are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- MailKeys now warns when another app has turned on Secure Keyboard Entry and names it ("Keyboard blocked by Slack"). While that's on, macOS hides keys from MailKeys, which made E jump through the message list instead of archiving.

## [1.3.0] - 2026-10-08

First public release.

### Added

- Gmail shortcuts in Apple Mail: J and K to move (hold to glide), E to archive, R, A, F, C and /.
- Hover over a message and press E to archive it, no click needed. MailKeys then selects the next message.
- Typing protection: shortcuts only act while you're browsing the message list in Mail.
- Test Mode, to try shortcuts without acting on your mail.
- Time saved stats and per-shortcut counts, stored only on your Mac.
- Settings window with Shortcuts and Advanced tabs, light and dark mode, Open at login, and diagnostics for hover support and responsiveness.
