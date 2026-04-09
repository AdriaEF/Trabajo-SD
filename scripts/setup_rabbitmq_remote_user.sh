#!/usr/bin/env bash
set -euo pipefail

# Configure a RabbitMQ user for remote access.
# Run this script on the machine where RabbitMQ server is installed.
#
# Usage:
#   sudo bash scripts/setup_rabbitmq_remote_user.sh <user> <password>
#
# Example:
#   sudo bash scripts/setup_rabbitmq_remote_user.sh sduser sdpass123
#
# Optional env vars:
#   VHOST (default: /)
#   TAGS (default: administrator)
#   CONFIGURE_RE (default: .*)
#   WRITE_RE (default: .*)
#   READ_RE (default: .*)

if [[ $# -lt 2 ]]; then
    echo "Usage: sudo bash scripts/setup_rabbitmq_remote_user.sh <user> <password>" >&2
    exit 1
fi

USER_NAME="$1"
USER_PASS="$2"
VHOST="${VHOST:-/}"
TAGS="${TAGS:-administrator}"
CONFIGURE_RE="${CONFIGURE_RE:-.*}"
WRITE_RE="${WRITE_RE:-.*}"
READ_RE="${READ_RE:-.*}"

if ! command -v rabbitmqctl >/dev/null 2>&1; then
    echo "rabbitmqctl not found. Install/start RabbitMQ first." >&2
    exit 1
fi

SERVICE_NAME=""
if systemctl list-unit-files | grep -q '^rabbitmq-server\.service'; then
    SERVICE_NAME="rabbitmq-server"
elif systemctl list-unit-files | grep -q '^rabbit-server\.service'; then
    SERVICE_NAME="rabbit-server"
fi

if [[ -n "${SERVICE_NAME}" ]]; then
    if ! sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo "Starting service: ${SERVICE_NAME}"
        sudo systemctl start "${SERVICE_NAME}"
    fi
fi

sudo rabbitmqctl await_startup >/dev/null 2>&1 || true

if sudo rabbitmqctl list_vhosts | awk '{print $1}' | grep -qx "${VHOST}"; then
    echo "Vhost exists: ${VHOST}"
else
    echo "Creating vhost: ${VHOST}"
    sudo rabbitmqctl add_vhost "${VHOST}"
fi

if sudo rabbitmqctl list_users | awk '{print $1}' | grep -qx "${USER_NAME}"; then
    echo "User exists, updating password: ${USER_NAME}"
    sudo rabbitmqctl change_password "${USER_NAME}" "${USER_PASS}"
else
    echo "Creating user: ${USER_NAME}"
    sudo rabbitmqctl add_user "${USER_NAME}" "${USER_PASS}"
fi

echo "Setting tags: ${TAGS}"
sudo rabbitmqctl set_user_tags "${USER_NAME}" ${TAGS}

echo "Setting permissions on vhost ${VHOST}"
sudo rabbitmqctl set_permissions -p "${VHOST}" "${USER_NAME}" "${CONFIGURE_RE}" "${WRITE_RE}" "${READ_RE}"

echo ""
echo "Configured RabbitMQ user successfully"
echo "User: ${USER_NAME}"
echo "Vhost: ${VHOST}"
echo ""
echo "Test from remote machine with:"
echo "  RABBITMQ_USER=${USER_NAME} RABBITMQ_PASS=${USER_PASS} bash scripts/test_start_workers.sh <IP_REDIS> <IP_RABBITMQ> <WORKERS>"
