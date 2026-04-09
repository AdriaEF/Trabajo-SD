#!/usr/bin/env bash
set -euo pipefail

# Starts direct REST workers for a multi-machine setup.
# Use this on the worker VM (for example, VM2).
#
# Required environment:
# - REDIS_URL: Redis reachable from this VM, for example redis://10.0.0.11:6379/0
#
# Optional environment:
# - WORKERS: number of local workers to start, default 1
# - PORT_BASE: base port for workers, default 8000
#
# Example:
#   REDIS_URL="redis://10.0.0.11:6379/0" WORKERS=1 bash scripts/start_direct_workers_multimachine.sh

WORKERS="${WORKERS:-1}"
PORT_BASE="${PORT_BASE:-8000}"
REDIS_URL="${REDIS_URL:-}"

if [[ -z "${REDIS_URL}" ]]; then
    echo "REDIS_URL is required, for example redis://10.0.0.11:6379/0" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/direct/rest/service"
PID_FILE="${SCRIPT_DIR}/.direct_workers_pids"

bash "${SCRIPT_DIR}/stop_direct_workers.sh" || true
: > "${PID_FILE}"

for i in $(seq 1 "${WORKERS}"); do
    port=$((PORT_BASE + i))
    worker_id="direct-worker-${i}"
    log_file="${SCRIPT_DIR}/worker_${i}.log"

    # Verificar que el puerto no esté en uso
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
        echo "✗ Error: Puerto ${port} ya está en uso" >&2
        ss -ltnp 2>/dev/null | grep ":${port} " >&2 || true
        exit 1
    fi

    cd "${APP_DIR}"
    export REDIS_URL="${REDIS_URL}"
    export WORKER_ID="${worker_id}"
    
    # Log inicial con variables
    {
        echo "=== Worker ${i} startup at $(date) ==="
        echo "REDIS_URL=${REDIS_URL}"
        echo "WORKER_ID=${worker_id}"
        echo "PORT=${port}"
    } > "${log_file}"
    
    uvicorn app:app --host 0.0.0.0 --port "${port}" >> "${log_file}" 2>&1 &
    pid=$!
    echo "${pid}" >> "${PID_FILE}"
    
    echo "Started ${worker_id} on port ${port} (PID: ${pid})"
    
    # Esperar un poco para que el worker intente conectarse a Redis
    sleep 1
    
    # Verificar que el worker no se haya crasheado inmediatamente
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "✗ Error: Worker ${worker_id} (PID ${pid}) se crasheó inmediatamente" >&2
        echo "=== Log del worker ===" >&2
        tail -20 "${log_file}" >&2
        echo "====================\n" >&2
        exit 1
    fi
done

echo ""
echo "Workers using REDIS_URL=${REDIS_URL}"
echo "PIDs saved in ${PID_FILE}"
echo "Ver logs: tail -f scripts/worker_*.log"
