#!/usr/bin/env bash
set -euo pipefail

# Starts N RabbitMQ worker processes.
# Use this on the worker VM (for example, VM2).
#
# Required environment:
# - RABBITMQ_URL: RabbitMQ connection string, for example amqp://guest:guest@10.0.0.11:5672/%2F
#
# Optional environment:
# - WORKERS: number of local workers to start, default 1
#
# Example:
#   RABBITMQ_URL="amqp://guest:guest@10.0.0.11:5672/%2F" WORKERS=1 bash scripts/start_rabbitmq_workers.sh

WORKERS="${WORKERS:-1}"
RABBITMQ_URL="${RABBITMQ_URL:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKER_DIR="${PROJECT_ROOT}/indirect/rabbitmq/worker"
PID_FILE="${SCRIPT_DIR}/.rabbitmq_workers_pids"

if [[ -z "${RABBITMQ_URL}" ]]; then
    echo "RABBITMQ_URL is required, for example amqp://guest:guest@10.0.0.11:5672/%2F" >&2
    exit 1
fi

# Stop existing workers first
bash "${SCRIPT_DIR}/stop_rabbitmq_workers.sh" || true
: > "${PID_FILE}"

for i in $(seq 1 "${WORKERS}"); do
    log_file="${SCRIPT_DIR}/rabbitmq_worker_${i}.log"
    
    # Log initial info
    {
        echo "=== RabbitMQ Worker ${i} startup at $(date) ==="
        echo "RABBITMQ_URL=${RABBITMQ_URL}"
        echo "WORKER_ID=rabbit-worker-${i}"
    } > "${log_file}"
    
    cd "${WORKER_DIR}"
    export RABBITMQ_URL="${RABBITMQ_URL}"
    export WORKER_ID="rabbit-worker-${i}"
    PYTHONUNBUFFERED=1 python3 -u worker.py >> "${log_file}" 2>&1 &
    pid=$!
    echo "${pid}" >> "${PID_FILE}"
    
    echo "Started rabbit-worker-${i} (PID: ${pid})"
    
    # Wait a bit for worker to connect and produce first log
    sleep 1
done

echo ""
echo "Workers using RABBITMQ_URL=${RABBITMQ_URL}"
echo "PIDs saved in ${PID_FILE}"
