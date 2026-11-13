#!/bin/bash
# Builds build/Seshka.app.
#
#   scripts/build.sh      a quick local build for this Mac, signed ad-hoc
#
# scripts/release.sh calls it with UNIVERSAL=1 and SIGN_IDENTITY (and SIGN_KEYCHAIN) set, which builds for
# Apple silicon and Intel and signs for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${UNIVERSAL:-}" = 1 ]; then
    swift build -c release --arch arm64 --arch x86_64
    PRODUCTS=.build/apple/Products/Release
else
    swift build -c release
    PRODUCTS=.build/release
fi

APP="build/Seshka.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/Seshka" "$APP/Contents/MacOS/Seshka"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle, the updater, ships inside the app.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$PRODUCTS/Sparkle.framework" "$FRAMEWORK"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Seshka"

IDENTITY="${SIGN_IDENTITY:--}"
OPTIONS=""
if [ "$IDENTITY" != "-" ]; then
    # Apple's notary service requires the hardened runtime and a secure timestamp.
    OPTIONS="--options runtime --timestamp"
fi
sign() {
    # shellcheck disable=SC2086
    codesign --force --sign "$IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} $OPTIONS "$@"
}
# Inside out: Sparkle's helpers, then the framework, then the app.
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP"
echo "Built $APP"
