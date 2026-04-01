#!/usr/bin/env bash
set -euo pipefail

PID_FILE="scripts/.direct_workers_pids"

if [[ ! -f "${PID_FILE}" ]]; then
    echo "No PID file found: ${PID_FILE}"
    exit 0
fi

while IFS= read -r pid; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" || true
        echo "Stopped PID ${pid}"
    fi
done < "${PID_FILE}"

rm -f "${PID_FILE}"
echo "Done"
