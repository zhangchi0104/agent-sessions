#!/usr/bin/env bash

set -euo pipefail

DMG_PATH="${1:?usage: verify-dmg.sh <dmg-path> <app-name>}"
APP_NAME="${2:?usage: verify-dmg.sh <dmg-path> <app-name>}"

test -f "$DMG_PATH" || {
  echo "error: no DMG found at $DMG_PATH" >&2
  exit 1
}

MOUNT_DIR="$(mktemp -d)"
ATTACHED=0

cleanup_mount() {
  if (( ATTACHED == 1 )); then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup_mount EXIT

echo "==> Verifying DMG structure"
DMG_FORMAT="$(
  hdiutil imageinfo -plist "$DMG_PATH" \
    | plutil -extract Format raw -o - -
)"
if [[ "$DMG_FORMAT" != "UDZO" ]]; then
  echo "error: expected a UDZO disk image, got ${DMG_FORMAT}" >&2
  exit 1
fi
hdiutil verify "$DMG_PATH"

echo "==> Verifying DMG can be mounted read-only"
hdiutil attach \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" \
  "$DMG_PATH" >/dev/null
ATTACHED=1

FILESYSTEM_TYPE="$(
  diskutil info -plist "$MOUNT_DIR" \
    | plutil -extract FilesystemType raw -o - -
)"
if [[ "$FILESYSTEM_TYPE" != "apfs" ]]; then
  echo "error: expected an APFS DMG filesystem, got ${FILESYSTEM_TYPE}" >&2
  exit 1
fi

test -d "${MOUNT_DIR}/${APP_NAME}.app" || {
  echo "error: mounted DMG is missing ${APP_NAME}.app" >&2
  exit 1
}
test -L "${MOUNT_DIR}/Applications" || {
  echo "error: mounted DMG is missing the Applications symlink" >&2
  exit 1
}
APPLICATIONS_TARGET="$(readlink "${MOUNT_DIR}/Applications")"
if [[ "$APPLICATIONS_TARGET" != "/Applications" ]]; then
  echo "error: Applications symlink targets ${APPLICATIONS_TARGET}, expected /Applications" >&2
  exit 1
fi

hdiutil detach "$MOUNT_DIR" -quiet
ATTACHED=0
rmdir "$MOUNT_DIR"
trap - EXIT
echo "==> DMG structure and mounted contents are valid"
