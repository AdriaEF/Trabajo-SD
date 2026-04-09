#!/usr/bin/env bash
set -euo pipefail

# Automatic start for testing (remote workers - both direct REST and RabbitMQ).
# - Ensures Python venv + direct requirements + rabbitmq requirements
# - Starts N direct REST workers pointing to Redis server
# - Starts N RabbitMQ workers pointing to RabbitMQ server
#
# Usage:
#   bash test_start_workers.sh <ip_redis> <ip_rabbit> [num_workers] [rabbit_user] [rabbit_pass]
#
# Example:
#   bash test_start_workers.sh 10.54.10.105 10.54.10.105 4 admin test
#
# Optional env vars:
#   RABBITMQ_USER (default: guest)
#   RABBITMQ_PASS (default: guest)

if [[ $# -lt 2 ]]; then
    echo "Usage: bash test_start_workers.sh <ip_redis> <ip_rabbit> [num_workers] [rabbit_user] [rabbit_pass]" >&2
    echo "Example: bash test_start_workers.sh 10.54.10.105 10.54.10.105 4 admin test" >&2
    exit 1
fi

REDIS_IP="$1"
RABBITMQ_IP="$2"
WORKERS="${3:-1}"
RABBITMQ_USER="${4:-${RABBITMQ_USER:-guest}}"
RABBITMQ_PASS="${5:-${RABBITMQ_PASS:-guest}}"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv"
DIRECT_REQ_FILE="${PROJECT_ROOT}/direct/rest/service/requirements.txt"
RABBIT_REQ_FILE="${PROJECT_ROOT}/indirect/rabbitmq/worker/requirements.txt"
RABBIT_WORKER_DIR="${PROJECT_ROOT}/indirect/rabbitmq/worker"
REDIS_URL="redis://${REDIS_IP}:6379/0"
RABBITMQ_URL="amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_IP}:5672/%2F"
PORT_BASE="${PORT_BASE:-8000}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-1}"

wait_for_local_health() {
    local port="$1"
    local retries="$2"
    local sleep_seconds="$3"
    local url="http://127.0.0.1:${port}/health"

    for attempt in $(seq 1 "${retries}"); do
        if curl --fail --silent --show-error "${url}" >/dev/null; then
            echo "Health OK: ${url}"
            return 0
        fi
        sleep "${sleep_seconds}"
    done

    echo "Health check failed: ${url}" >&2
    return 1
}

wait_for_rabbitmq_heartbeat() {
    local worker_num="$1"
    local retries="$2"
    local sleep_seconds="$3"
    local log_file="${SCRIPT_DIR}/rabbitmq_worker_${worker_num}.log"

    for attempt in $(seq 1 "${retries}"); do
        if grep -q "\[Heartbeat\]" "${log_file}" 2>/dev/null; then
            echo "RabbitMQ worker $worker_num: heartbeat detected in log"
            return 0
        fi
        sleep "${sleep_seconds}"
    done

    echo "RabbitMQ worker $worker_num: no heartbeat detected after $((retries * sleep_seconds))s" >&2
    return 1
}

if [[ ! -d "${VENV_PATH}" ]]; then
    python3 -m venv "${VENV_PATH}"
fi

# shellcheck disable=SC1091
source "${VENV_PATH}/bin/activate"

echo "=== Installing Direct REST dependencies ==="
python3 -m pip install -r "${DIRECT_REQ_FILE}" --quiet

echo "=== Installing RabbitMQ worker dependencies ==="
python3 -m pip install -r "${RABBIT_REQ_FILE}" --quiet

echo ""
echo "=== Precheck: Redis ${REDIS_URL} ==="
export REDIS_URL="${REDIS_URL}"
python3 - <<'PY'
import os
import sys
from redis import Redis

redis_url = os.environ["REDIS_URL"]
try:
    Redis.from_url(redis_url, decode_responses=True, socket_connect_timeout=3).ping()
except Exception as exc:
    print(f"✗ Redis ping failed for {redis_url}: {exc}", file=sys.stderr)
    sys.exit(1)
print(f"✓ Redis ping OK: {redis_url}")
PY

echo ""
echo "=== Precheck: RabbitMQ ${RABBITMQ_URL} ==="
export RABBITMQ_URL="${RABBITMQ_URL}"
python3 - <<'PY'
import os
import sys
import pika

rabbitmq_url = os.environ["RABBITMQ_URL"]
try:
    params = pika.URLParameters(rabbitmq_url)
    connection = pika.BlockingConnection(params)
    connection.close()
except Exception as exc:
    msg = str(exc)
    print(f"✗ RabbitMQ connection failed for {rabbitmq_url}: {msg}", file=sys.stderr)
    if "ACCESS_REFUSED" in msg and "guest" in rabbitmq_url:
        print(
            "Hint: guest is usually blocked for remote logins. "
            "Create a dedicated user on RabbitMQ host with "
            "scripts/setup_rabbitmq_remote_user.sh and run this script with "
            "RABBITMQ_USER/RABBITMQ_PASS.",
            file=sys.stderr,
        )
    sys.exit(1)
print(f"✓ RabbitMQ connection OK: {rabbitmq_url}")
PY

echo ""
echo "=== Starting RabbitMQ workers ==="
export RABBITMQ_URL="${RABBITMQ_URL}" WORKERS="${WORKERS}"
bash "${SCRIPT_DIR}/start_rabbitmq_workers.sh"

echo ""
echo "=== Postcheck: RabbitMQ worker heartbeat ==="
for i in $(seq 1 "${WORKERS}"); do
    wait_for_rabbitmq_heartbeat "${i}" "${HEALTH_RETRIES}" "${HEALTH_SLEEP_SECONDS}"
done

echo ""
echo "=== Starting Direct REST workers ==="
export REDIS_URL="${REDIS_URL}" WORKERS="${WORKERS}"
bash "${SCRIPT_DIR}/start_direct_workers_multimachine.sh"

echo ""
echo "=== Postcheck: Direct REST worker health ==="
for i in $(seq 1 "${WORKERS}"); do
    port=$((PORT_BASE + i))
    wait_for_local_health "${port}" "${HEALTH_RETRIES}" "${HEALTH_SLEEP_SECONDS}"
done

echo ""
echo "All workers started successfully!"
echo ""
echo "Logs:"
echo "  Direct REST: tail -f ${SCRIPT_DIR}/worker_*.log"
echo "  RabbitMQ:    tail -f ${SCRIPT_DIR}/rabbitmq_worker_*.log"
