#!/usr/bin/env bash
set -euo pipefail

# Automatic start for testing (remote direct workers).
# - Ensures Python venv + direct requirements
# - Starts N workers pointing to Redis server
#
# Usage:
#   bash test_start_workers.sh <redis_ip> [workers]
#
# Example:
#   bash test_start_workers.sh 192.168.1.10 2

if [[ $# -lt 1 ]]; then
    echo "Usage: bash test_start_workers.sh <vm1_redis_ip> [workers]" >&2
    echo "Example: bash test_start_workers.sh 192.168.1.10 1" >&2
    exit 1
fi

VM1_REDIS_IP="$1"
WORKERS="${2:-1}"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv"
REQ_FILE="${PROJECT_ROOT}/direct/rest/service/requirements.txt"
REDIS_URL="redis://${VM1_REDIS_IP}:6379/0"
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

if [[ ! -d "${VENV_PATH}" ]]; then
    python3 -m venv "${VENV_PATH}"
fi

# shellcheck disable=SC1091
source "${VENV_PATH}/bin/activate"
python3 -m pip install -r "${REQ_FILE}"

echo "Precheck: Redis ${REDIS_URL}"
python3 - <<'PY'
import os
import sys
from redis import Redis

redis_url = os.environ["REDIS_URL"]
try:
    Redis.from_url(redis_url, decode_responses=True).ping()
except Exception as exc:
    print(f"Redis ping failed for {redis_url}: {exc}", file=sys.stderr)
    raise
print(f"Redis ping OK: {redis_url}")
PY

REDIS_URL="${REDIS_URL}" WORKERS="${WORKERS}" bash "${SCRIPT_DIR}/start_direct_workers_multimachine.sh"

echo "Postcheck: local worker health"
for i in $(seq 1 "${WORKERS}"); do
    port=$((PORT_BASE + i))
    wait_for_local_health "${port}" "${HEALTH_RETRIES}" "${HEALTH_SLEEP_SECONDS}"
done
