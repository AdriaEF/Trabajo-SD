#!/usr/bin/env bash
# Diagnóstico de conexión RabbitMQ desde VM2

RABBITMQ_IP="${1:-10.54.10.105}"
RABBITMQ_PORT="${2:-5672}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASS="${RABBITMQ_PASS:-guest}"

echo "=== Diagnóstico RabbitMQ ==="
echo "RABBITMQ_IP: $RABBITMQ_IP"
echo "RABBITMQ_PORT: $RABBITMQ_PORT"
echo "RABBITMQ_USER: $RABBITMQ_USER"
echo ""

# 1. Ping por IP
echo "1. Intentando ping a $RABBITMQ_IP..."
if ping -c 1 "$RABBITMQ_IP" &>/dev/null; then
    echo "✓ Ping OK"
else
    echo "✗ Ping falló - posible problema de red/firewall"
    exit 1
fi
echo ""

# 2. Test conexión TCP
echo "2. Test conexión TCP (timeout 3s)..."
if timeout 3 bash -c "echo '' > /dev/tcp/$RABBITMQ_IP/$RABBITMQ_PORT" 2>/dev/null; then
    echo "✓ Puerto accesible"
else
    echo "✗ No se puede conectar al puerto $RABBITMQ_PORT"
    echo "  Soluciones:"
    echo "  - Activar firewall UFW en VM1: sudo ufw allow 5672/tcp"
    echo "  - O abrir puerto directamente: sudo iptables -A INPUT -p tcp --dport 5672 -j ACCEPT"
    exit 1
fi
echo ""

# 3. Test con nc si está disponible
echo "3. Test con nc..."
if command -v nc &>/dev/null; then
    if nc -zv "$RABBITMQ_IP" "$RABBITMQ_PORT" 2>&1 | grep -q succeeded; then
        echo "✓ nc OK"
    else
        echo "✗ nc falló"
    fi
else
    echo "⚠ nc no instalado"
fi
echo ""

# 4. Test Python pika
echo "4. Test con Python pika..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv"

if [[ -d "${VENV_PATH}" ]]; then
    # shellcheck disable=SC1091
    source "${VENV_PATH}/bin/activate"
fi

export RABBITMQ_IP RABBITMQ_PORT RABBITMQ_USER RABBITMQ_PASS
python3 - <<'PY'
import os
import sys
try:
    import pika
    rabbitmq_ip = os.environ["RABBITMQ_IP"]
    rabbitmq_port = os.environ["RABBITMQ_PORT"]
    rabbitmq_user = os.environ["RABBITMQ_USER"]
    rabbitmq_pass = os.environ["RABBITMQ_PASS"]

    url = f"amqp://{rabbitmq_user}:{rabbitmq_pass}@{rabbitmq_ip}:{rabbitmq_port}/%2F"
    params = pika.URLParameters(url)
    conn = pika.BlockingConnection(params)
    conn.close()
    print(f"✓ Python pika OK - Conexion establecida a amqp://{rabbitmq_user}@{rabbitmq_ip}:{rabbitmq_port}")
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)
PY

echo ""
echo "=== Fin diagnóstico ==="
