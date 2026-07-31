#!/usr/bin/env bash

set -euo pipefail

APP_PATH="${1:?usage: verify-release-toolchain.sh <TokenStats.app>}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
# Xcode 26.3 release binaries crash in SwiftUI's button gesture path when the
# Tokens tab is selected. Xcode 26.6 emits DTXcode 2660 and is verified good.
MIN_DTXCODE=2660
DTXCODE=""

if [[ -f "$INFO_PLIST" ]]; then
  DTXCODE="$(/usr/libexec/PlistBuddy -c "Print :DTXcode" "$INFO_PLIST" 2>/dev/null || true)"
fi

case "$DTXCODE" in
  ""|*[!0-9]*)
    echo "error: release app is missing numeric DTXcode metadata" >&2
    exit 1
    ;;
esac

if (( DTXCODE < MIN_DTXCODE )); then
  echo "error: release app was built with DTXcode ${DTXCODE}; Xcode 26.6 or newer is required" >&2
  exit 1
fi

echo "verified release toolchain: DTXcode ${DTXCODE} (minimum ${MIN_DTXCODE})"
