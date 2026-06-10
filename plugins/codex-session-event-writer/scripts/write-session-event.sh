#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVENT_NAME="${AGENT_SESSIONS_HOOK_EVENT:-${1:-unknown}}"

exec bun "$PLUGIN_ROOT/scripts/write-session-event.ts" "$EVENT_NAME"
