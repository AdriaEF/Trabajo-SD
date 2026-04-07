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

if [[ ! -d "${VENV_PATH}" ]]; then
    python3 -m venv "${VENV_PATH}"
fi

# shellcheck disable=SC1091
source "${VENV_PATH}/bin/activate"
python3 -m pip install -r "${REQ_FILE}"

REDIS_URL="${REDIS_URL}" WORKERS="${WORKERS}" bash "${SCRIPT_DIR}/start_direct_workers_multimachine.sh"
