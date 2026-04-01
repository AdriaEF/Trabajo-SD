#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="${1:-127.0.0.1}"
PORT="${2:-8000}"
URI="http://${HOST_NAME}:${PORT}/health"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-20}"
SLEEP_SECONDS="${SLEEP_SECONDS:-0.5}"

echo "Checking ${URI}"

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
	if curl --fail --silent --show-error "${URI}"; then
		exit 0
	fi

	if [[ "${attempt}" -lt "${MAX_ATTEMPTS}" ]]; then
        echo "Attempt failed, retrying in ${SLEEP_SECONDS} seconds... (${attempt}/${MAX_ATTEMPTS})"
		sleep "${SLEEP_SECONDS}"
	fi
done

echo "Healthcheck failed after ${MAX_ATTEMPTS} attempts: ${URI}" >&2
exit 1
