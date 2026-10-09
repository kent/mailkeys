#!/bin/zsh
# Regenerates AppIcon.icns from the icon drawing code in SettingsUI.swift.
set -euo pipefail
cd "${0:A:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
WORK=$(mktemp -d)
xcrun swiftc ShortcutPolicy.swift Responsiveness.swift Usage.swift SecureInput.swift SettingsUI.swift main.swift -framework AppKit -framework ApplicationServices -framework Carbon -framework IOKit -o "$WORK/mk"
MAILKEYS_ICON="$WORK/icon.png" "$WORK/mk"
mkdir "$WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o AppIcon.icns
rm -rf "$WORK"
printf 'Wrote AppIcon.icns\n'
