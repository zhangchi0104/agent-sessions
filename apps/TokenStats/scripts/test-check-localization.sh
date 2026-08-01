#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$script_dir/fixtures/localization"
checker="$script_dir/check-localization.sh"

"$checker" "$fixtures/pass" >/dev/null

expect_failure() {
  local fixture="$1"
  local expected="$2"
  local output

  if output="$("$checker" "$fixtures/$fixture" 2>&1)"; then
    echo "error: localization fixture '$fixture' unexpectedly passed." >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "error: localization fixture '$fixture' did not report '$expected'." >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_failure fail-multiline "user-facing string literal"
expect_failure fail-appkit "user-facing string literal"
expect_failure fail-empty-ignore "i18n-ignore must include a non-empty reason"

echo "Localization scanner fixtures passed."
