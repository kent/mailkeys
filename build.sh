#!/bin/zsh
# Runs the tests, then builds, signs and installs MailKeys.app (default: ~/Applications).
set -euo pipefail
cd "${0:A:h}"
# Prefer the Command Line Tools, which build without accepting the full Xcode licence.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
# Optional, git-ignored: a line like  MAILKEYS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
[[ -f signing.local ]] && source signing.local
APP="${MAILKEYS_APP_PATH:-$HOME/Applications/MailKeys.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xcrun swiftc ShortcutPolicy.swift Responsiveness.swift Usage.swift PolicyTests.swift -o "${TMPDIR:-/tmp}/mailkeys-policy-tests"
"${TMPDIR:-/tmp}/mailkeys-policy-tests"
xcrun swiftc -O ShortcutPolicy.swift Responsiveness.swift Usage.swift SettingsUI.swift main.swift -framework AppKit -framework ApplicationServices -o "$APP/Contents/MacOS/MailKeys"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.kent.MailKeys</string>
<key>CFBundleName</key><string>MailKeys</string>
<key>CFBundleDisplayName</key><string>MailKeys</string>
<key>CFBundleExecutable</key><string>MailKeys</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A stable identity keeps Accessibility authorization valid across future builds.
# Set MAILKEYS_SIGN_IDENTITY to your certificate, e.g. 'Developer ID Application: Your Name (TEAMID)'.
# Without it the app is signed ad hoc, and macOS may ask for Accessibility again after each rebuild.
/usr/bin/codesign --force --sign "${MAILKEYS_SIGN_IDENTITY:--}" --options runtime --timestamp=none "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
