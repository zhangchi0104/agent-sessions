#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_root="$(cd -- "$script_dir/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required for localization checks." >&2
  exit 2
fi

# Optional roots make the scanner independently testable with static fixtures.
# Product runs omit them and scan the complete app source tree.
if (( $# > 0 )); then
  scan_roots=("$@")
else
  scan_roots=("$app_root/TokenStats")
fi

exec node "$script_dir/check-localization.mjs" "${scan_roots[@]}"
