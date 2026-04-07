#!/usr/bin/env bash
set -euo pipefail

# Automatic start for testing (multi-machine direct scaling).
# - Ensures Python venv + direct requirements
# - Starts the main server with env vars pointing to remote workers on and local workers
#
# Usage:
#   bash test_run_server.sh <vm1_ip> <remote_servers> [local_workers]
#
# Example:
#   bash test_run_server.sh 192.168.1.10 "192.168.1.11:8001" 1

if [[ $# -lt 2 ]]; then
    echo "Usage: bash test_run_server.sh <vm1_ip> <remote_servers> [local_workers]" >&2
    echo "Example: bash test_run_server.sh 192.168.1.10 \"192.168.1.11:8001\" 1" >&2
    exit 1
fi

VM1_IP="$1"
REMOTE_SERVERS="$2"
LOCAL_WORKERS="${3:-1}"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv"
REQ_FILE="${PROJECT_ROOT}/direct/rest/service/requirements.txt"

if [[ ! -d "${VENV_PATH}" ]]; then
    python3 -m venv "${VENV_PATH}"
fi

# shellcheck disable=SC1091
source "${VENV_PATH}/bin/activate"
python3 -m pip install -r "${REQ_FILE}"

sudo env \
    LOCAL_UPSTREAM_HOST="${VM1_IP}" \
    DIRECT_UPSTREAM_SERVERS="${REMOTE_SERVERS}" \
    LOCAL_WORKER_COUNT="${LOCAL_WORKERS}" \
    bash "${SCRIPT_DIR}/run_part4_multimachine_experiment.sh"
