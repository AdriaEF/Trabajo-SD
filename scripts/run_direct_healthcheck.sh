#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="${1:-127.0.0.1}"
PORT="${2:-8000}"
URI="http://${HOST_NAME}:${PORT}/health"

echo "Checking ${URI}"
curl --fail --silent --show-error "${URI}"
echo
