#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.rabbitmq_workers_pids"

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
pkill -f "python3 -u worker.py" 2>/dev/null || true
pkill -f "indirect/rabbitmq/worker/worker.py" 2>/dev/null || true

echo "Done"
