#!/usr/bin/env bash
set -euo pipefail

# Starts N RabbitMQ worker processes.
# Usage: bash scripts/start_rabbitmq_workers.sh 4

WORKERS="${1:-4}"
WORKER_DIR="indirect/rabbitmq/worker"
PID_FILE="scripts/.rabbitmq_workers_pids"

: > "${PID_FILE}"

for i in $(seq 1 "${WORKERS}"); do
    (
        cd "${WORKER_DIR}"
        python3 worker.py > "../../../scripts/rabbitmq_worker_${i}.log" 2>&1 &
        echo "$!" >> "../../../${PID_FILE}"
    )
    echo "Started rabbitmq-worker-${i}"
done

echo "PIDs saved in ${PID_FILE}"
