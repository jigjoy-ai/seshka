#!/bin/bash
# Builds build/Seshka.app.
# Signs ad-hoc by default; set SIGN_IDENTITY to a certificate name to sign for distribution:
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Seshka.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Seshka "$APP/Contents/MacOS/Seshka"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
