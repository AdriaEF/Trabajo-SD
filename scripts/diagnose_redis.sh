#!/usr/bin/env bash
# Diagnóstico de conexión Redis desde VM2

REDIS_IP="${1:-10.54.10.105}"
REDIS_PORT="${2:-6379}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Diagnóstico Redis ==="
echo "REDIS_IP: $REDIS_IP"
echo "REDIS_PORT: $REDIS_PORT"
echo ""

# 1. Ping por IP
echo "1. Intentando ping a $REDIS_IP..."
if ping -c 1 "$REDIS_IP" &>/dev/null; then
    echo "✓ Ping OK"
else
    echo "✗ Ping falló - posible problema de red/firewall"
fi
echo ""

# 2. Test conexión TCP
echo "2. Test conexión TCP (timeout 3s)..."
if timeout 3 bash -c "echo '' > /dev/tcp/$REDIS_IP/$REDIS_PORT" 2>/dev/null; then
    echo "✓ Puerto accesible"
else
    echo "✗ No se puede conectar al puerto $REDIS_PORT - Firewall o Redis no escuchando"
fi
echo ""

# 3. Intenta redis-cli si existe
echo "3. Intentando redis-cli PING..."
if command -v redis-cli &>/dev/null; then
    if redis-cli -h "$REDIS_IP" -p "$REDIS_PORT" PING 2>&1 | grep -q PONG; then
        echo "✓ Redis responde PONG"
    else
        echo "✗ Redis no responde correctamente"
    fi
else
    echo "⚠ redis-cli no instalado"
fi
echo ""

# 4. Intenta con Python Redis
echo "4. Intento con Python (Redis.from_url)..."
PYTHON_CMD="python3"
VENV_CANDIDATES=(
    "${PROJECT_ROOT}/direct/rest/service/.venv"
    "${PROJECT_ROOT}/indirect/rabbitmq/worker/.venv"
    "${PROJECT_ROOT}/scripts/.venv-indirect"
    "${PROJECT_ROOT}/.venv"
)

for venv in "${VENV_CANDIDATES[@]}"; do
    if [[ -x "${venv}/bin/python" ]] && "${venv}/bin/python" -c "import redis" >/dev/null 2>&1; then
        PYTHON_CMD="${venv}/bin/python"
        break
    fi
done

"${PYTHON_CMD}" <<PY
import sys
try:
    from redis import Redis
    url = "redis://$REDIS_IP:$REDIS_PORT/0"
    r = Redis.from_url(url, decode_responses=True, socket_connect_timeout=3)
    result = r.ping()
    print(f"✓ Python Redis OK - {result}")
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)
PY
echo ""

echo "=== Fin diagnóstico ==="
