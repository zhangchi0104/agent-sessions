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
SCHEME="TokenStats"
ENTITLEMENTS="TokenStats/TokenStats.entitlements"
DERIVED="build"
APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
DIST="dist"
DMG_PATH="${DIST}/${APP_NAME}-${VERSION}.dmg"

# Run from the app root (apps/TokenStats) regardless of caller's cwd.
cd "$(dirname "$0")/.."

echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER})"
# Build unsigned: CI can't reliably use Xcode automatic signing, so we strip
# signing here and apply a Developer ID signature manually below. -scheme (not
# -target) is required alongside -derivedDataPath; the scheme is shared in
# TokenStats.xcodeproj/xcshareddata so it resolves on CI.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
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

# Guard: the signed app MUST NOT carry any RESTRICTED entitlement. AMFI
# authorizes restricted entitlements only against an embedded provisioning
# profile, which this direct-distribution Developer ID build does not have, so
# any such key makes the kernel SIGKILL the app at launch ("can't be opened",
# exit 137) — codesign/spctl/notarization don't catch it. This bit us twice:
# App Sandbox temporary-exceptions (commit c04930f) and keychain-access-groups
# (commit 79a2c01, added on the false premise that it is AMFI-safe). We read the
# entitlements back from the SIGNED binary because that is what actually ships.
# (KeychainTokenStore uses the legacy login keychain, which needs no entitlement
# — see ADR-0004.)
echo "==> Verifying signed entitlements carry no restricted keys"
SIGNED_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null || true)"
case "$SIGNED_ENTITLEMENTS" in
  *keychain-access-groups*|*com.apple.security.temporary-exception*|*com.apple.security.app-sandbox*)
    echo "error: signed app carries a restricted entitlement AMFI will SIGKILL at launch" >&2
    echo "       (keychain-access-groups / sandbox temporary-exception; aborting release)" >&2
    echo "$SIGNED_ENTITLEMENTS" >&2
    exit 1
    ;;
esac

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

# Verify the app as it exists inside the finished release asset, not only the
# pre-packaging build product. A damaged inner signature can still leave a DMG
# that signs, notarizes and staples successfully, but the installed app is then
# no longer the executable we verified above.
echo "==> Verifying packaged app signature"
VERIFY_MOUNT="$(mktemp -d)"
VERIFY_MOUNTED=0
cleanup_verification_mount() {
  if [[ "$VERIFY_MOUNTED" -eq 1 ]]; then
    hdiutil detach "$VERIFY_MOUNT" -quiet >/dev/null 2>&1 || true
  fi
  rmdir "$VERIFY_MOUNT" >/dev/null 2>&1 || true
}
trap cleanup_verification_mount EXIT

hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$VERIFY_MOUNT" \
  -quiet \
  "$DMG_PATH"
VERIFY_MOUNTED=1
codesign --verify --deep --strict --verbose=4 "$VERIFY_MOUNT/${APP_NAME}.app"
hdiutil detach "$VERIFY_MOUNT" -quiet
VERIFY_MOUNTED=0
rmdir "$VERIFY_MOUNT"
trap - EXIT

echo "==> Done: $DMG_PATH"
