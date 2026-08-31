#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREATE_SCRIPT="${SCRIPT_DIR}/create-dmg.sh"
FIXTURE_ROOT="$(mktemp -d)"
BIN_DIR="${FIXTURE_ROOT}/bin"
APP_PATH="${FIXTURE_ROOT}/TokenStats.app"
OUTPUT_DIR="${FIXTURE_ROOT}/dist"
DMG_PATH="${OUTPUT_DIR}/TokenStats-test.dmg"
FAILED_DMG_PATH="${OUTPUT_DIR}/.failed/TokenStats-test.dmg"
CALL_LOG="${FIXTURE_ROOT}/calls.log"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$BIN_DIR" "$APP_PATH"
export CALL_LOG

cat >"${BIN_DIR}/ditto" <<'EOF'
#!/usr/bin/env bash
printf 'ditto' >>"$CALL_LOG"
for argument in "$@"; do
  printf ' <%s>' "$argument" >>"$CALL_LOG"
  destination="$argument"
done
printf '\n' >>"$CALL_LOG"
if [[ "${DITTO_STATUS:-0}" != "0" ]]; then
  exit "$DITTO_STATUS"
fi
mkdir -p "$destination"
EOF

cat >"${BIN_DIR}/hdiutil" <<'EOF'
#!/usr/bin/env bash
printf 'hdiutil' >>"$CALL_LOG"
for argument in "$@"; do
  printf ' <%s>' "$argument" >>"$CALL_LOG"
done
printf '\n' >>"$CALL_LOG"

command_name="$1"
shift
case "$command_name" in
  create)
    for output_path in "$@"; do :; done
    printf 'mock DMG candidate\n' >"$output_path"
    if [[ "${CREATE_STATUS:-0}" != "0" ]]; then
      exit "$CREATE_STATUS"
    fi
    ;;
  imageinfo)
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Format</key><string>${DMG_FORMAT:-UDZO}</string></dict></plist>
PLIST
    ;;
  verify)
    exit "${VERIFY_STATUS:-0}"
    ;;
  attach)
    if [[ "${ATTACH_STATUS:-0}" != "0" ]]; then
      exit "$ATTACH_STATUS"
    fi
    mountpoint=""
    previous=""
    for argument in "$@"; do
      if [[ "$previous" == "-mountpoint" ]]; then
        mountpoint="$argument"
        break
      fi
      previous="$argument"
    done
    test -n "$mountpoint"
    mkdir -p "${mountpoint}/TokenStats.app"
    ln -s "${APPLICATIONS_TARGET:-/Applications}" "${mountpoint}/Applications"
    ;;
  detach)
    mountpoint="$1"
    rm -rf "${mountpoint}/TokenStats.app"
    rm -f "${mountpoint}/Applications"
    ;;
esac
EOF

cat >"${BIN_DIR}/diskutil" <<'EOF'
#!/usr/bin/env bash
printf 'diskutil' >>"$CALL_LOG"
for argument in "$@"; do
  printf ' <%s>' "$argument" >>"$CALL_LOG"
done
printf '\n' >>"$CALL_LOG"
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>FilesystemType</key><string>${FILESYSTEM_TYPE:-apfs}</string></dict></plist>
PLIST
EOF

chmod +x "${BIN_DIR}/ditto" "${BIN_DIR}/hdiutil" "${BIN_DIR}/diskutil"

run_create() {
  PATH="${BIN_DIR}:$PATH" \
    DITTO_STATUS="${DITTO_STATUS:-0}" \
    CREATE_STATUS="${CREATE_STATUS:-0}" \
    DMG_FORMAT="${DMG_FORMAT:-UDZO}" \
    VERIFY_STATUS="${VERIFY_STATUS:-0}" \
    ATTACH_STATUS="${ATTACH_STATUS:-0}" \
    FILESYSTEM_TYPE="${FILESYSTEM_TYPE:-apfs}" \
    APPLICATIONS_TARGET="${APPLICATIONS_TARGET:-/Applications}" \
    "$CREATE_SCRIPT" "$APP_PATH" "$DMG_PATH" "TokenStats Test"
}

reset_fixture() {
  : >"$CALL_LOG"
  rm -rf "$OUTPUT_DIR"
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

expect_failed_candidate() {
  test ! -e "$DMG_PATH"
  test -f "$FAILED_DMG_PATH"
  expect_call_count "hdiutil <create>" 1
}

reset_fixture
run_create >/dev/null
test -f "$DMG_PATH"
test ! -e "$FAILED_DMG_PATH"
expect_call_count "ditto <--rsrc> <--extattr> <--acl> <$APP_PATH>" 1
expect_call_count "hdiutil <create>" 1
expect_call_count "<-atomic>" 1
expect_call_count "<-format> <UDZO>" 1
expect_call_count "<-fs>" 0
expect_call_count "hdiutil <imageinfo>" 1
expect_call_count "hdiutil <verify>" 1
expect_call_count "hdiutil <attach>" 1
expect_call_count "diskutil <info> <-plist>" 1
expect_call_count "hdiutil <detach>" 1

reset_fixture
if CREATE_STATUS=1 run_create >/dev/null 2>&1; then
  echo "error: a failed hdiutil create must fail closed" >&2
  exit 1
fi
expect_failed_candidate
expect_call_count "hdiutil <imageinfo>" 0

reset_fixture
if DMG_FORMAT=UDRW run_create >/dev/null 2>&1; then
  echo "error: a non-UDZO candidate must fail closed" >&2
  exit 1
fi
expect_failed_candidate
expect_call_count "hdiutil <verify>" 0
expect_call_count "hdiutil <attach>" 0

reset_fixture
if VERIFY_STATUS=1 run_create >/dev/null 2>&1; then
  echo "error: a candidate that fails checksum verification must fail closed" >&2
  exit 1
fi
expect_failed_candidate
expect_call_count "hdiutil <verify>" 1
expect_call_count "hdiutil <attach>" 0

reset_fixture
if FILESYSTEM_TYPE=hfs run_create >/dev/null 2>&1; then
  echo "error: a non-APFS mounted filesystem must fail closed" >&2
  exit 1
fi
expect_failed_candidate
expect_call_count "hdiutil <attach>" 1
expect_call_count "hdiutil <detach>" 1

reset_fixture
if APPLICATIONS_TARGET=/Wrong run_create >/dev/null 2>&1; then
  echo "error: an incorrect Applications symlink must fail closed" >&2
  exit 1
fi
expect_failed_candidate
expect_call_count "hdiutil <detach>" 1

reset_fixture
if DITTO_STATUS=1 run_create >/dev/null 2>&1; then
  echo "error: a staging failure must fail closed" >&2
  exit 1
fi
test ! -e "$DMG_PATH"
test ! -e "$FAILED_DMG_PATH"
expect_call_count "ditto <--rsrc> <--extattr> <--acl> <$APP_PATH>" 1
expect_call_count "hdiutil <create>" 0

echo "DMG creation and validation tests passed"
