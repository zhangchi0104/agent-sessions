#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTARIZE_SCRIPT="${SCRIPT_DIR}/notarize-dmg.sh"
FIXTURE_ROOT="$(mktemp -d)"
BIN_DIR="${FIXTURE_ROOT}/bin"
DMG_PATH="${FIXTURE_ROOT}/TokenStats-test.dmg"
CALL_LOG="${FIXTURE_ROOT}/calls.log"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$BIN_DIR"
touch "$DMG_PATH"
export CALL_LOG
export NOTARY_KEY_PATH="${FIXTURE_ROOT}/AuthKey_test.p8"
export NOTARY_KEY_ID="test-key-id"
export NOTARY_ISSUER_ID="test-issuer-id"

cat >"${BIN_DIR}/hdiutil" <<'EOF'
#!/usr/bin/env bash
printf 'hdiutil %s\n' "$*" >>"$CALL_LOG"
exit "${HDIUTIL_STATUS:-0}"
EOF

cat >"${BIN_DIR}/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >>"$CALL_LOG"
exit "${CODESIGN_STATUS:-0}"
EOF

cat >"${BIN_DIR}/xcrun" <<'EOF'
#!/usr/bin/env bash
printf 'xcrun %s\n' "$*" >>"$CALL_LOG"

if [[ " $* " == *" --force "* ]]; then
  exit "${FORCED_NOTARY_STATUS:-0}"
fi

case "${NOTARY_MODE:-success}" in
  success)
    exit 0
    ;;
  format-preflight)
    echo "Error: TokenStats-test.dmg must be a zip archive (.zip), flat installer package (.pkg), or UDIF disk image (.dmg), use 'notarytool submit --force' to skip this validation and submit anyway." >&2
    exit 64
    ;;
  format-message-wrong-status)
    echo "Error: TokenStats-test.dmg must be a zip archive (.zip), flat installer package (.pkg), or UDIF disk image (.dmg), use 'notarytool submit --force' to skip this validation and submit anyway." >&2
    exit 1
    ;;
  unrelated-usage-error)
    echo "Error: invalid notarytool option" >&2
    exit 64
    ;;
  service-error)
    echo "Error: notarization service unavailable" >&2
    exit 1
    ;;
esac
EOF

chmod +x "${BIN_DIR}/hdiutil" "${BIN_DIR}/codesign" "${BIN_DIR}/xcrun"

run_notarize() {
  PATH="${BIN_DIR}:$PATH" "$NOTARIZE_SCRIPT" "$DMG_PATH"
}

BASE_SUBMISSION="xcrun notarytool submit $DMG_PATH --key $NOTARY_KEY_PATH --key-id $NOTARY_KEY_ID --issuer $NOTARY_ISSUER_ID --wait --verbose"
FORCED_SUBMISSION="${BASE_SUBMISSION} --force"

reset_calls() {
  : >"$CALL_LOG"
}

expect_call_count() {
  local pattern="$1"
  local expected="$2"
  local actual
  actual="$(grep -c -F -- "$pattern" "$CALL_LOG" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: expected ${expected} calls matching '${pattern}', got ${actual}" >&2
    cat "$CALL_LOG" >&2
    exit 1
  fi
}

reset_calls
NOTARY_MODE=success run_notarize >/dev/null
expect_call_count "hdiutil verify $DMG_PATH" 1
expect_call_count "codesign --verify --strict --verbose=2 $DMG_PATH" 1
expect_call_count "$BASE_SUBMISSION" 1
expect_call_count "--force" 0

reset_calls
NOTARY_MODE=format-preflight run_notarize >/dev/null 2>&1
expect_call_count "$BASE_SUBMISSION" 2
expect_call_count "$FORCED_SUBMISSION" 1

reset_calls
if NOTARY_MODE=format-message-wrong-status run_notarize >/dev/null 2>&1; then
  echo "error: the format message without exit 64 must not trigger the forced fallback" >&2
  exit 1
fi
expect_call_count "xcrun notarytool submit" 1
expect_call_count "--force" 0

reset_calls
if NOTARY_MODE=unrelated-usage-error run_notarize >/dev/null 2>&1; then
  echo "error: unrelated exit-64 errors must not trigger the forced fallback" >&2
  exit 1
fi
expect_call_count "xcrun notarytool submit" 1
expect_call_count "--force" 0

reset_calls
if NOTARY_MODE=service-error run_notarize >/dev/null 2>&1; then
  echo "error: service errors must propagate" >&2
  exit 1
fi
expect_call_count "xcrun notarytool submit" 1
expect_call_count "--force" 0

reset_calls
if FORCED_NOTARY_STATUS=73 NOTARY_MODE=format-preflight run_notarize >/dev/null 2>&1; then
  echo "error: a failed forced submission must propagate" >&2
  exit 1
else
  forced_status="$?"
fi
if [[ "$forced_status" != "73" ]]; then
  echo "error: expected forced submission status 73, got ${forced_status}" >&2
  exit 1
fi
expect_call_count "$BASE_SUBMISSION" 2
expect_call_count "$FORCED_SUBMISSION" 1

reset_calls
if HDIUTIL_STATUS=1 NOTARY_MODE=format-preflight run_notarize >/dev/null 2>&1; then
  echo "error: an invalid disk image must fail before notarization" >&2
  exit 1
fi
expect_call_count "xcrun notarytool submit" 0

reset_calls
if CODESIGN_STATUS=1 NOTARY_MODE=format-preflight run_notarize >/dev/null 2>&1; then
  echo "error: an invalid disk image signature must fail before notarization" >&2
  exit 1
fi
expect_call_count "xcrun notarytool submit" 0

echo "DMG notarization submission tests passed"
