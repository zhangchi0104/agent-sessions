#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${PROJECT_ROOT}/build"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/TokenStats.app"
APP_PROCESS_NAME="TokenStats"

stop_running_app() {
    local -a pids
    local pid attempt pgrep_output pgrep_exit

    # Match the executable name exactly; do not terminate unrelated processes
    # whose command line merely happens to contain "TokenStats".
    pids=()
    if pgrep_output="$(pgrep -x "${APP_PROCESS_NAME}" 2>/dev/null)"; then
        :
    else
        pgrep_exit=$?
        # pgrep uses exit 1 for a successful search with no matches. Any other
        # status means the process list could not be inspected safely.
        if ((pgrep_exit != 1)); then
            echo "error: unable to inspect ${APP_PROCESS_NAME} processes (pgrep exit ${pgrep_exit})" >&2
            return "${pgrep_exit}"
        fi
    fi

    # pgrep emits one numeric PID per line. A here-string also handles a single
    # PID without relying on unquoted word splitting.
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] && pids+=("${pid}")
    done <<< "${pgrep_output}"
    ((${#pids[@]} == 0)) && return 0

    printf 'Stopping %s (PID(s): %s)\n' "${APP_PROCESS_NAME}" "${pids[*]}"
    for pid in "${pids[@]}"; do
        kill -TERM "${pid}" 2>/dev/null || true
    done

    # Give the app a short, bounded grace period to flush state and exit.
    for pid in "${pids[@]}"; do
        for ((attempt = 0; attempt < 50; attempt++)); do
            kill -0 "${pid}" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "${pid}" 2>/dev/null; then
            echo "error: ${APP_PROCESS_NAME} PID ${pid} did not exit after SIGTERM" >&2
            return 1
        fi
    done
}

cd "${PROJECT_ROOT}"
stop_running_app

xcodebuild \
    -project TokenStats.xcodeproj \
    -scheme TokenStats \
    -configuration Debug \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build \
    && open -n "${APP_PATH}"
