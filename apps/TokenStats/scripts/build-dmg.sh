#!/usr/bin/env bash
#
# Build, codesign, notarize and package TokenStats.app into a distributable
# .dmg. Invoked by semantic-release's @semantic-release/exec prepareCmd with the
# computed version, e.g.:
#
#     ./scripts/build-dmg.sh 1.4.0
#
# Output: dist/TokenStats-<version>.dmg (signed + notarized + stapled).
#
# Required environment (provided by the GitHub Actions release workflow):
#   BUILD_NUMBER       CFBundleVersion to stamp (defaults to 1)
#   MACOS_SIGN_IDENTITY  Optional. Overrides auto-detection of the
#                        "Developer ID Application: …" identity in the keychain.
#   NOTARY_KEY_PATH    Path to the App Store Connect API key (.p8)
#   NOTARY_KEY_ID      App Store Connect API Key ID
#   NOTARY_ISSUER_ID   App Store Connect Issuer ID
#
# A Developer ID Application signing identity must already be present in the
# default keychain search list before this script runs.

set -euo pipefail

VERSION="${1:?usage: build-dmg.sh <version>}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP_NAME="TokenStats"
PROJECT="TokenStats.xcodeproj"
TARGET="TokenStats"
ENTITLEMENTS="TokenStats/TokenStats.entitlements"
DERIVED="build"
APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
DIST="dist"
DMG_PATH="${DIST}/${APP_NAME}-${VERSION}.dmg"

# Run from the app root (apps/TokenStats) regardless of caller's cwd.
cd "$(dirname "$0")/.."

echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER})"
# Build unsigned: CI can't reliably use Xcode automatic signing, so we strip
# signing here and apply a Developer ID signature manually below. We build the
# target directly (-target) because no shared scheme is checked in.
xcodebuild \
  -project "$PROJECT" \
  -target "$TARGET" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean build

test -d "$APP_PATH" || { echo "error: build produced no app at $APP_PATH" >&2; exit 1; }

# Resolve the Developer ID Application identity.
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
test -n "$SIGN_IDENTITY" || {
  echo "error: no 'Developer ID Application' identity in keychain" >&2
  exit 1
}
echo "==> Signing with: $SIGN_IDENTITY"

# Deep-sign with the hardened runtime + secure timestamp (both required for
# notarization) and the app's entitlements.
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> Packaging DMG: $DMG_PATH"
mkdir -p "$DIST"
rm -f "$DMG_PATH"
STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# hdiutil is the most reliable DMG builder in headless CI (no AppleScript/GUI).
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"
rm -rf "$STAGE"

# Sign the DMG itself so the download carries a valid signature.
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

echo "==> Notarizing"
xcrun notarytool submit "$DMG_PATH" \
  --key "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}" \
  --key-id "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}" \
  --issuer "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Done: $DMG_PATH"
