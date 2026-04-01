#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.direct_workers_pids"
APP_DIR="${SCRIPT_DIR}/../direct/rest/service"

kill_if_running() {
    local pid="$1"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}" 2>/dev/null; then
            echo "Stopped PID ${pid}"
        fi
    fi
}

if [[ -f "${PID_FILE}" ]]; then
    while IFS= read -r pid; do
        kill_if_running "${pid}"
    done < "${PID_FILE}"
    rm -f "${PID_FILE}"
fi

# Fallback cleanup in case PID file is missing/stale.
pkill -f "uvicorn app:app --host 0.0.0.0 --port 800[1-4]" 2>/dev/null || true
pkill -f "${APP_DIR}/.venv/bin/uvicorn app:app" 2>/dev/null || true

echo "Done"
