#!/usr/bin/env bash
set -euo pipefail

# Starts N RabbitMQ worker processes.
# Usage: bash scripts/start_rabbitmq_workers.sh 4

WORKERS="${1:-4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKER_DIR="${PROJECT_ROOT}/indirect/rabbitmq/worker"
PID_FILE="${SCRIPT_DIR}/.rabbitmq_workers_pids"

: > "${PID_FILE}"

for i in $(seq 1 "${WORKERS}"); do
    (
        cd "${WORKER_DIR}"
        PYTHONUNBUFFERED=1 python3 -u worker.py > "${SCRIPT_DIR}/rabbitmq_worker_${i}.log" 2>&1 &
        echo "$!" >> "${PID_FILE}"
    )
    echo "Started rabbitmq-worker-${i}"
done

echo "PIDs saved in ${PID_FILE}"
