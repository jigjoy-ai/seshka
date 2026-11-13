#!/bin/bash
# Builds the installer disk image: a compact window with the app on the left, Applications on the right,
# and an arrow between them (Resources/dmg-background.tiff, drawn in design/dmg-background.svg).
#
#   scripts/make-dmg.sh build/Seshka.app dist/Seshka.dmg
#
# Finder lays the window out, so this needs a logged-in desktop, and macOS may ask once whether the
# terminal may control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=$1
OUT=$2
VOLUME=Seshka
[ ! -e "/Volumes/$VOLUME" ] || { echo "/Volumes/$VOLUME is mounted; eject it first"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir "$WORK/root" "$WORK/root/.background"
ditto "$APP" "$WORK/root/Seshka.app"
ln -s /Applications "$WORK/root/Applications"
cp Resources/dmg-background.tiff "$WORK/root/.background/background.tiff"

# A writable image first, so Finder can save the window's layout into it.
hdiutil create -volname "$VOLUME" -srcfolder "$WORK/root" -fs HFS+ -format UDRW -size 40m -ov "$WORK/rw.dmg" >/dev/null
DEVICE=$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | awk '/Apple_HFS/ {print $1}')

osascript <<SCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 560x400 of content, plus the title bar.
        set the bounds of container window to {240, 160, 800, 588}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 120
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "Seshka.app" of container window to {150, 185}
        set position of item "Applications" of container window to {410, 185}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
SCRIPT

sync
hdiutil detach "$DEVICE" >/dev/null
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "Built $OUT"
