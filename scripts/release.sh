#!/bin/bash
# Makes a release and publishes it: a signed, notarized app as a .dmg (to download) and a .zip (for the
# updater), plus the update feed, uploaded to the downloads bucket behind CloudFront (deploy/releases.yaml).
# seshka.dev redirects /download/* and /appcast.xml there.
#
# Only someone holding the signing material and AWS access can run this. Nothing secret lives in this repository:
#
#   SESHKA_SIGNING_DIR   a folder with the Developer ID certificate and the notary key:
#                          developer-id.p12, p12-password,
#                          AuthKey_<id>.p8, notary-key-id, notary-issuer
#   SESHKA_AWS_PROFILE   an AWS CLI profile allowed to write to the downloads bucket
#
# The private key that signs updates is in the login keychain of whoever ran Sparkle's generate_keys.
#
#   SESHKA_SIGNING_DIR=~/keys/developer-id SESHKA_AWS_PROFILE=my-profile scripts/release.sh
#
# Before running: raise CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SESHKA_SIGNING_DIR:?set SESHKA_SIGNING_DIR to the folder with the signing material}"
: "${SESHKA_AWS_PROFILE:?set SESHKA_AWS_PROFILE to an AWS profile that can write to the downloads bucket}"
KEYS=$(cd "$SESHKA_SIGNING_DIR" && pwd)
STACK=seshka-releases
REGION=eu-west-1
output() {  # output <key>   a value the downloads stack exports
    aws cloudformation describe-stacks --profile "$SESHKA_AWS_PROFILE" --region "$REGION" --stack-name "$STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
BUCKET=$(output Bucket)
DOWNLOADS=$(output DownloadsUrl)
[ -n "$BUCKET" ] && [ -n "$DOWNLOADS" ] || { echo "Could not read the $STACK stack; deploy deploy/releases.yaml first"; exit 1; }
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

# dist/updates holds every update archive, because the feed lists all of them.
UPDATES=dist/updates
mkdir -p "$UPDATES"
aws s3 sync "s3://$BUCKET/" "$UPDATES" --profile "$SESHKA_AWS_PROFILE" --exclude "*" --include "Seshka-*.zip" >/dev/null
ZIP="$UPDATES/Seshka-$VERSION.zip"
DMG="dist/Seshka.dmg"

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
"$SPARKLE/generate_appcast" "$UPDATES" \
    --download-url-prefix "$DOWNLOADS/" \
    --link "https://seshka.dev" \
    --maximum-deltas 0 \
    -o "$UPDATES/appcast.xml"

echo "==> Uploading"
upload() {  # upload <file> <name> <cache-control> [content-type]
    aws s3 cp "$1" "s3://$BUCKET/$2" --profile "$SESHKA_AWS_PROFILE" --cache-control "$3" ${4:+--content-type "$4"} >/dev/null
}
# A version's archive never changes. The disk image and the feed keep their names, so they must not be cached.
upload "$ZIP" "Seshka-$VERSION.zip" "public, max-age=31536000, immutable"
upload "$DMG" "Seshka.dmg" "no-cache"
upload "$UPDATES/appcast.xml" "appcast.xml" "no-cache" "application/xml"

echo
echo "seshka $VERSION is published:"
echo "  https://seshka.dev/download/Seshka.dmg   ->  $DOWNLOADS/Seshka.dmg"
echo "  https://seshka.dev/appcast.xml           ->  $DOWNLOADS/appcast.xml"
