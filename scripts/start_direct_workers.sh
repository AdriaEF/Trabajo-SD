#!/usr/bin/env bash
set -euo pipefail

# Starts N uvicorn worker processes on ports 8001..(8000+N)
# Usage: bash scripts/start_direct_workers.sh 4

WORKERS="${1:-4}"
APP_DIR="direct/rest/service"
PID_FILE="scripts/.direct_workers_pids"

: > "${PID_FILE}"

for i in $(seq 1 "${WORKERS}"); do
    port=$((8000 + i))
    worker_id="direct-worker-${i}"

    (
        cd "${APP_DIR}"
        WORKER_ID="${worker_id}" uvicorn app:app --host 0.0.0.0 --port "${port}" > "../../../scripts/worker_${i}.log" 2>&1 &
        echo "$!" >> "../../../${PID_FILE}"
    )

    echo "Started ${worker_id} on port ${port}"
done

echo "PIDs saved in ${PID_FILE}"
