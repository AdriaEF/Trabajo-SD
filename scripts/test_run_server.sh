#!/usr/bin/env bash
set -euo pipefail

# Automatic start for testing (multi-machine direct scaling).
# - Ensures Python venv + direct requirements
# - Starts the main server with env vars pointing to remote workers and a total worker target
#
# Usage:
#   bash test_run_server.sh <vm1_ip> <remote_servers> [total_workers]
#
# Example:
#   bash test_run_server.sh 192.168.1.10 "192.168.1.11:8001 192.168.1.11:8002" 4

if [[ $# -lt 2 ]]; then
    echo "Usage: bash test_run_server.sh <vm1_ip> <remote_servers> [total_workers]" >&2
    echo "Example: bash test_run_server.sh 192.168.1.10 \"192.168.1.11:8001 192.168.1.11:8002\" 4" >&2
    exit 1
fi

VM1_IP="$1"
REMOTE_SERVERS="$2"
TOTAL_WORKERS="${3:-4}"

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
    TOTAL_WORKERS="${TOTAL_WORKERS}" \
    bash "${SCRIPT_DIR}/run_part4_multimachine_experiment.sh"
