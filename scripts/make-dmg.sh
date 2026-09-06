#!/bin/bash
# Builds a universal release .app and wraps it in a drag-to-Applications DMG: build/SelectTranslate-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL="${UNIVERSAL:-1}" ./scripts/build-app.sh release

APP="build/SelectTranslate.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/SelectTranslate-$VERSION.dmg"
STAGE="$(mktemp -d)"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
SelectTranslate — on-device text translation for macOS 15+

Install: drag SelectTranslate to the Applications folder, then open it.

This build is not notarized by Apple, so macOS may say it can't be opened:
  1. Open System Settings → Privacy & Security
  2. Scroll down and click "Open Anyway" next to SelectTranslate
  3. Launch it again, then grant Accessibility access when asked

Or in Terminal:  xattr -d com.apple.quarantine /Applications/SelectTranslate.app
TXT

rm -f "$DMG"
hdiutil create -volname "SelectTranslate" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created $DMG"
