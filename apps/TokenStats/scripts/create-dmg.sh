#!/usr/bin/env bash

set -euo pipefail

APP_PATH="${1:?usage: create-dmg.sh <app-path> <output-dmg> <volume-name>}"
DMG_PATH="${2:?usage: create-dmg.sh <app-path> <output-dmg> <volume-name>}"
VOLUME_NAME="${3:?usage: create-dmg.sh <app-path> <output-dmg> <volume-name>}"

test -d "$APP_PATH" || {
  echo "error: no app found at $APP_PATH" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="${SCRIPT_DIR}/verify-dmg.sh"
OUTPUT_DIR="$(dirname "$DMG_PATH")"
OUTPUT_NAME="$(basename "$DMG_PATH")"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
FINAL_DMG="${OUTPUT_DIR}/${OUTPUT_NAME}"
FAILED_DIR="${OUTPUT_DIR}/.failed"
# Keep failure artifacts outside dist/*.dmg, but avoid a second leading dot so
# upload-artifact and local shell globs can find them reliably.
FAILED_DMG="${FAILED_DIR}/${OUTPUT_NAME#.}"
WORK_DIR="$(mktemp -d "${OUTPUT_DIR}/.tokenstats-dmg.XXXXXX")"
STAGE="${WORK_DIR}/stage"
CANDIDATE_DMG="${WORK_DIR}/${OUTPUT_NAME}"

cleanup_work() {
  if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup_work EXIT

diagnose_candidate() {
  local candidate="$1"
  if [[ ! -f "$candidate" ]]; then
    echo "    no candidate file was produced" >&2
    return
  fi

  echo "    candidate diagnostics:" >&2
  stat -f '      size=%z bytes' "$candidate" >&2 || true
  file "$candidate" >&2 || true
  shasum -a 256 "$candidate" >&2 || true
}

mkdir -p "$STAGE" "$FAILED_DIR"
rm -f "$FINAL_DMG" "$FAILED_DMG"

# Apple's packaging guidance recommends ditto for automated staging because it
# preserves bundle symlinks and metadata reliably. Explicit switches override a
# caller's DITTONORSRC environment setting.
ditto --rsrc --extattr --acl \
  "$APP_PATH" \
  "${STAGE}/$(basename "$APP_PATH")"
ln -s /Applications "${STAGE}/Applications"

echo "==> Creating DMG candidate"
# Do not pin HFS+. The macos-26 GitHub runner can report success while
# producing an unreadable image on that path. Let hdiutil choose a filesystem
# supported by the running OS, matching Apple's current packaging command.
if ! hdiutil create \
    -atomic \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -format UDZO \
    "$CANDIDATE_DMG"; then
  echo "error: hdiutil failed to create the DMG candidate" >&2
  diagnose_candidate "$CANDIDATE_DMG"
  if [[ -f "$CANDIDATE_DMG" ]]; then
    mv -f "$CANDIDATE_DMG" "$FAILED_DMG"
    echo "error: preserved the invalid candidate at $FAILED_DMG" >&2
  fi
  exit 1
fi

if ! "$VERIFY_SCRIPT" "$CANDIDATE_DMG" "$(basename "$APP_PATH" .app)"; then
  echo "error: hdiutil created a DMG candidate that failed validation" >&2
  diagnose_candidate "$CANDIDATE_DMG"
  mv -f "$CANDIDATE_DMG" "$FAILED_DMG"
  echo "error: preserved the invalid candidate at $FAILED_DMG" >&2
  exit 1
fi

mv -f "$CANDIDATE_DMG" "$FINAL_DMG"
cleanup_work
trap - EXIT
echo "==> Created verified DMG: $FINAL_DMG"
stat -f '    size=%z bytes' "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG"
