#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREATE_SCRIPT="${SCRIPT_DIR}/create-dmg.sh"
VERIFY_SCRIPT="${SCRIPT_DIR}/verify-dmg.sh"
FIXTURE_ROOT="$(mktemp -d)"
APP_PATH="${FIXTURE_ROOT}/TokenStats.app"
DMG_PATH="${FIXTURE_ROOT}/dist/TokenStats-integration.dmg"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "${APP_PATH}/Contents/Resources"
printf 'TokenStats DMG integration fixture\n' >"${APP_PATH}/Contents/Resources/payload.txt"

"$CREATE_SCRIPT" \
  "$APP_PATH" \
  "$DMG_PATH" \
  "TokenStats Integration"

# Exercise the same container mutation that the release path performs before
# notarization, using an ad-hoc identity because CI imports the Developer ID
# certificate only after this test step.
codesign --force \
  --identifier "dev.otakuma.TokenStats.dmg.integration" \
  --sign - \
  "$DMG_PATH"
"$VERIFY_SCRIPT" "$DMG_PATH" "TokenStats"
codesign --verify --strict --verbose=2 "$DMG_PATH"

echo "real DMG packaging integration passed"
