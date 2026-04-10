#!/usr/bin/env bash
set -euo pipefail

# Automatic multi-machine full test suite execution (Parts 4-7).
# Executes all scaling and fault injection experiments end-to-end:
#   Part 4: Direct REST scaling
#   Part 5: RabbitMQ scaling
#   Part 6: Hotspot experiment (80/5)
#   Part 7: Fault injection scenarios
#
# Usage:
#   bash test_run_server.sh <server_ip> <remote_servers> [total_workers] [rabbitmq_ip] [rabbitmq_user] [rabbitmq_pass]
#
# Example:
#   bash test_run_server.sh 192.168.247.247 "192.168.247.112:8001 192.168.247.112:8002 192.168.247.112:8003 192.168.247.112:8004" 4 192.168.247.247 admin test

if [[ $# -lt 2 ]]; then
    echo "Usage: bash test_run_server.sh <server_ip> <remote_servers> [total_workers] [rabbitmq_ip] [rabbitmq_user] [rabbitmq_pass]" >&2
    exit 1
fi

SERVER_IP="$1"
REMOTE_SERVERS="$2"
TOTAL_WORKERS="${3:-4}"
RABBITMQ_IP="${4:-127.0.0.1}"
RABBITMQ_USER="${5:-${RABBITMQ_USER:-guest}}"
RABBITMQ_PASS="${6:-${RABBITMQ_PASS:-guest}}"
RABBITMQ_URL="amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_IP}:5672/%2F"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv"
REQ_FILE="${PROJECT_ROOT}/requirements.txt"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-1}"

wait_for_health() {
    local host_port="$1"
    local retries="$2"
    local sleep_seconds="$3"
    local url="http://${host_port}/health"

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

check_service_status() {
    local service_name="$1"
    echo "Precheck: service status ${service_name}"
    sudo systemctl status "${service_name}" --no-pager || true
}

ensure_nginx_running() {
    if ! sudo systemctl is-active --quiet nginx; then
        echo "NGINX is not active. Starting nginx..."
        sudo systemctl start nginx
    fi
    sudo systemctl status nginx --no-pager || true
}

if [[ ! -d "${VENV_PATH}" ]]; then
    python3 -m venv "${VENV_PATH}"
fi

# shellcheck disable=SC1091
source "${VENV_PATH}/bin/activate"
python3 -m pip install -r "${REQ_FILE}"

check_service_status "redis-server"
ensure_nginx_running

echo "Precheck: RabbitMQ TCP ${RABBITMQ_IP}:5672"
if command -v nc >/dev/null 2>&1; then
    if ! nc -vz -w 2 "${RABBITMQ_IP}" 5672 >/dev/null 2>&1; then
        echo "RabbitMQ TCP check failed (nc): ${RABBITMQ_IP}:5672" >&2
        exit 1
    fi
else
    if ! timeout 3 bash -c "echo '' > /dev/tcp/${RABBITMQ_IP}/5672" 2>/dev/null; then
        echo "RabbitMQ TCP check failed (/dev/tcp): ${RABBITMQ_IP}:5672" >&2
        echo "Tip: install netcat-openbsd for nc-based checks." >&2
        exit 1
    fi
fi

echo "Precheck: remote workers"
for server in ${REMOTE_SERVERS}; do
    wait_for_health "${server}" "${HEALTH_RETRIES}" "${HEALTH_SLEEP_SECONDS}"
done

echo "Using remote upstream servers: ${REMOTE_SERVERS}"

sudo env \
    LOCAL_UPSTREAM_HOST="${SERVER_IP}" \
    DIRECT_UPSTREAM_SERVERS="${REMOTE_SERVERS}" \
    TOTAL_WORKERS="${TOTAL_WORKERS}" \
    WORKERS_LIST="1 2 4" \
    bash "${SCRIPT_DIR}/run_part4_multimachine_scaling_redis.sh"

sudo env \
    LOCAL_UPSTREAM_HOST="${SERVER_IP}" \
    DIRECT_UPSTREAM_SERVERS="${REMOTE_SERVERS}" \
    TOTAL_WORKERS="${TOTAL_WORKERS}" \
    WORKERS_LIST="1 2 4" \
    RABBITMQ_URL="${RABBITMQ_URL}" \
    bash "${SCRIPT_DIR}/run_part5_multimachine_scaling_rabbit.sh"

sudo env \
    LOCAL_UPSTREAM_HOST="${SERVER_IP}" \
    DIRECT_UPSTREAM_SERVERS="${REMOTE_SERVERS}" \
    TOTAL_WORKERS="${TOTAL_WORKERS}" \
    RABBITMQ_URL="${RABBITMQ_URL}" \
    bash "${SCRIPT_DIR}/run_part6_multimachine_hotspot_experiment.sh"

sudo env \
    LOCAL_UPSTREAM_HOST="${SERVER_IP}" \
    DIRECT_UPSTREAM_SERVERS="${REMOTE_SERVERS}" \
    TOTAL_WORKERS="${TOTAL_WORKERS}" \
    RABBITMQ_URL="${RABBITMQ_URL}" \
    bash "${SCRIPT_DIR}/run_part7_multimachine_fault_injection.sh"
