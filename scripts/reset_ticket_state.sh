#!/usr/bin/env bash
set -euo pipefail

# Resets Redis keys for both models.
# Optional: pass REDIS_HOST and REDIS_PORT as env vars.

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" DEL \
  tickets:unnumbered:sold \
  tickets:unnumbered:requests \
  tickets:numbered:seats \
  tickets:numbered:requests >/dev/null

echo "Ticket state reset in Redis ${REDIS_HOST}:${REDIS_PORT}"
