#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${SCRIPT_DIR}/.venv"

echo ""
echo ""
echo "================================================================================"
echo "============================  PREPARAR ENTORNO  ================================"
echo "================================================================================"
echo ""

chmod +x "${SCRIPT_DIR}"/*.sh

BIND="${1:-0.0.0.0}"
PORT="${2:-6379}"
CONF_CANDIDATES=(/etc/redis/redis.conf /etc/redis.conf)
conf=""

for c in "${CONF_CANDIDATES[@]}"; do
    if [[ -f "${c}" ]]; then
        conf="${c}"
        break
    fi
done

if [[ -z "${conf}" ]]; then
    echo "No Redis config found in standard locations: ${CONF_CANDIDATES[*]}" >&2
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "ensure_redis_bind_port: must run as root (sudo)." >&2
fi

bak="${conf}.bak.$(date +%s)"
cp "${conf}" "${bak}"
echo "Backup created: ${bak}"

if grep -qE '^\s*bind\b' "${conf}"; then
    sed -ri "s|^\s*bind\b.*|bind ${BIND}|" "${conf}"
else
    echo "bind ${BIND}" >>"${conf}"
fi

if grep -qE '^\s*port\b' "${conf}"; then
    sed -ri "s|^\s*port\b.*|port ${PORT}|" "${conf}"
else
    echo "port ${PORT}" >>"${conf}"
fi

if grep -qE '^\s*protected-mode\b' "${conf}"; then
    sed -ri "s|^\s*protected-mode\b.*|protected-mode no|" "${conf}"
else
    echo "protected-mode no" >>"${conf}"
fi

# Restart Redis (try common unit names)
if systemctl list-units --full -all | grep -qE '^redis(-server)?\.service'; then
    systemctl restart redis-server || systemctl restart redis || true
else
    service redis-server restart || service redis restart || true
fi

sleep 1

echo "Listening sockets for port ${PORT}:"
ss -ltnp 2>/dev/null | grep -E "[:.]${PORT}\b" || netstat -ltnp 2>/dev/null | grep -E "[:.]${PORT}\b" || echo "No listener found on port ${PORT}"

if command -v redis-cli >/dev/null 2>&1; then
    if redis-cli -h 127.0.0.1 -p "${PORT}" PING >/dev/null 2>&1; then
        echo "Redis local PING OK (127.0.0.1:${PORT})"
    else
        echo "Redis did not respond to local PING on 127.0.0.1:${PORT}" >&2
    fi
else
    echo "redis-cli not installed; install redis-tools to run local PING test." >&2
fi

python3 -m venv "${VENV_PATH}"
source "${VENV_PATH}/bin/activate"
pip install -r "${PROJECT_ROOT}/requirements.txt"

echo ""
echo "================================================================================"
echo "========================  LEVANTAR DEPENDENCIAS BASE  =========================="
echo "================================================================================"
echo ""

sudo systemctl enable --now redis-server
sudo systemctl enable --now rabbitmq-server
sudo systemctl status redis-server --no-pager
sudo systemctl status rabbitmq-server --no-pager

echo "Servicios levantados correctamente"