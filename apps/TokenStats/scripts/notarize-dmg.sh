#!/usr/bin/env bash

set -euo pipefail

DMG_PATH="${1:?usage: notarize-dmg.sh <signed-dmg-path>}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"

test -f "$DMG_PATH" || {
  echo "error: no DMG found at $DMG_PATH" >&2
  exit 1
}

# Recheck the final signed artifact immediately before submission. A signed
# disk image is still a valid UDIF, so both checks must pass before the narrow
# notarytool preflight fallback below is allowed.
echo "==> Verifying signed DMG"
hdiutil verify "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

NOTARY_ARGS=(
  --key "$NOTARY_KEY_PATH"
  --key-id "$NOTARY_KEY_ID"
  --issuer "$NOTARY_ISSUER_ID"
  --wait
  --verbose
)
NOTARY_OUTPUT="$(mktemp)"
trap 'rm -f "$NOTARY_OUTPUT"' EXIT

set +e
xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" 2>&1 | tee "$NOTARY_OUTPUT"
SUBMISSION_PIPE_STATUS=("${PIPESTATUS[@]}")
set -e

NOTARY_STATUS="${SUBMISSION_PIPE_STATUS[0]}"
TEE_STATUS="${SUBMISSION_PIPE_STATUS[1]}"
if (( TEE_STATUS != 0 )); then
  exit "$TEE_STATUS"
fi
if (( NOTARY_STATUS == 0 )); then
  exit 0
fi

FORMAT_PREFLIGHT_MESSAGE="must be a zip archive (.zip), flat installer package (.pkg), or UDIF disk image (.dmg)"
if (( NOTARY_STATUS == 64 )) && grep -Fq "$FORMAT_PREFLIGHT_MESSAGE" "$NOTARY_OUTPUT"; then
  echo "warning: notarytool rejected a locally verified UDIF during client-side format preflight; retrying with --force" >&2
  xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --force
  exit 0
fi

exit "$NOTARY_STATUS"
