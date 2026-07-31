#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="${SCRIPT_DIR}/verify-release-toolchain.sh"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

make_app_fixture() {
  local name="$1"
  local dtxcode="${2:-}"
  local info_plist="${FIXTURE_ROOT}/${name}.app/Contents/Info.plist"

  mkdir -p "$(dirname "$info_plist")"
  plutil -create xml1 "$info_plist"
  if [[ -n "$dtxcode" ]]; then
    plutil -insert DTXcode -string "$dtxcode" "$info_plist"
  fi
}

expect_failure() {
  local app_path="$1"
  local expected_message="$2"
  local output="${FIXTURE_ROOT}/failure-output.txt"

  if "$VERIFY_SCRIPT" "$app_path" >"$output" 2>&1; then
    echo "error: expected verification to fail for ${app_path}" >&2
    exit 1
  fi

  grep -F "$expected_message" "$output" >/dev/null
}

expect_success() {
  local app_path="$1"
  local expected_message="$2"
  local output="${FIXTURE_ROOT}/success-output.txt"

  "$VERIFY_SCRIPT" "$app_path" >"$output" 2>&1
  grep -F "$expected_message" "$output" >/dev/null
}

make_app_fixture "xcode-26.3" "2630"
make_app_fixture "xcode-26.6" "2660"
make_app_fixture "future-xcode" "2670"
make_app_fixture "missing-metadata"
make_app_fixture "invalid-metadata" "unknown"

expect_failure \
  "${FIXTURE_ROOT}/xcode-26.3.app" \
  "error: release app was built with DTXcode 2630; Xcode 26.6 or newer is required"
expect_failure \
  "${FIXTURE_ROOT}/missing-metadata.app" \
  "error: release app is missing numeric DTXcode metadata"
expect_failure \
  "${FIXTURE_ROOT}/invalid-metadata.app" \
  "error: release app is missing numeric DTXcode metadata"
expect_success \
  "${FIXTURE_ROOT}/xcode-26.6.app" \
  "verified release toolchain: DTXcode 2660 (minimum 2660)"
expect_success \
  "${FIXTURE_ROOT}/future-xcode.app" \
  "verified release toolchain: DTXcode 2670 (minimum 2660)"

echo "release toolchain verification tests passed"
