#!/bin/bash
# Makes a release: a signed, notarized app as a .dmg (to download) and a .zip (for the updater),
# plus the update feed. Everything lands in the website checkout, ready to commit and deploy.
#
# Only someone holding the signing material can run this. Nothing secret lives in this repository:
#
#   SESHKA_SIGNING_DIR   a folder with the Developer ID certificate and the notary key:
#                          developer-id.p12, p12-password,
#                          AuthKey_<id>.p8, notary-key-id, notary-issuer
#   SESHKA_SITE_DIR      a checkout of the website (jigjoy-ai/seshka-website)
#
# The private key that signs updates is in the login keychain of whoever ran Sparkle's generate_keys.
#
#   SESHKA_SIGNING_DIR=~/keys/developer-id SESHKA_SITE_DIR=../seshka-website scripts/release.sh
#
# Before running: raise CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SESHKA_SIGNING_DIR:?set SESHKA_SIGNING_DIR to the folder with the signing material}"
: "${SESHKA_SITE_DIR:?set SESHKA_SITE_DIR to a checkout of the website}"
KEYS=$(cd "$SESHKA_SIGNING_DIR" && pwd)
SITE=$(cd "$SESHKA_SITE_DIR" && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
SPARKLE=.build/artifacts/sparkle/Sparkle/bin
WORK=$(mktemp -d)
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD=$(uuidgen)

cleanup() {
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Releasing seshka $VERSION"

# The certificate goes into a throwaway keychain that is deleted when the script ends.
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$KEYS/developer-id.p12" -k "$KEYCHAIN" -P "$(cat "$KEYS/p12-password")" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# codesign only finds identities in keychains on the search list.
EXISTING=$(security list-keychains -d user | sed 's/^ *"//; s/"$//')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING
restore_keychains() {
    # shellcheck disable=SC2086
    security list-keychains -d user -s $EXISTING
    cleanup
}
trap restore_keychains EXIT
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity in $KEYS/developer-id.p12"; exit 1; }
echo "==> Signing as $IDENTITY"

UNIVERSAL=1 SIGN_IDENTITY="$IDENTITY" SIGN_KEYCHAIN="$KEYCHAIN" scripts/build.sh
APP=build/Seshka.app
codesign --verify --deep --strict "$APP"

notarize() {  # notarize <file>   uploads it to Apple and waits for the verdict
    xcrun notarytool submit "$1" --wait \
        --key "$(ls "$KEYS"/AuthKey_*.p8 | head -1)" \
        --key-id "$(cat "$KEYS/notary-key-id")" \
        --issuer "$(cat "$KEYS/notary-issuer")"
}

echo "==> Notarizing the app"
ditto -c -k --keepParent "$APP" "$WORK/Seshka.zip"
notarize "$WORK/Seshka.zip"
xcrun stapler staple "$APP"

mkdir -p "$SITE/public/download"
ZIP="$SITE/public/download/Seshka-$VERSION.zip"
DMG="$SITE/public/download/Seshka.dmg"

# The updater downloads the zip; it holds the stapled app.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building and notarizing the disk image"
mkdir "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Seshka.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "Seshka" -srcfolder "$WORK/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "==> Writing the update feed"
"$SPARKLE/generate_appcast" "$SITE/public/download" \
    --download-url-prefix "https://seshka.dev/download/" \
    --link "https://seshka.dev" \
    --maximum-deltas 0 \
    -o "$SITE/public/appcast.xml"

echo
echo "seshka $VERSION is ready in $SITE/public:"
echo "  download/Seshka.dmg            the download"
echo "  download/Seshka-$VERSION.zip   what the updater fetches"
echo "  appcast.xml                    the update feed"
echo "Commit and push the website to publish it."
