#!/usr/bin/env bash
set -euo pipefail

# Multimachine version of run_part6_hotspot_experiment.sh
# Runs hotspot experiment (80/5) for numbered model in both architectures across multiple machines.
#
# Usage example:
#   LOCAL_UPSTREAM_HOST="10.0.0.11" \
#   DIRECT_UPSTREAM_SERVERS="10.0.0.12:8001 10.0.0.12:8002" \
#   TOTAL_WORKERS=4 \
#   RABBITMQ_URL="amqp://admin:test@10.0.0.11:5672/%2F" \
#   bash scripts/run_part6_multimachine_hotspot_experiment.sh
#
# Notes:
# - Run this script on the machine that hosts NGINX and runs local workers.
# - Remote workers must already be running on other machine(s).
# - LOCAL_UPSTREAM_HOST is the IP address of the local NGINX server.
# - DIRECT_UPSTREAM_SERVERS format: space-separated "host:port" entries.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${RESULTS_DIR}/hotspot_comparison_results.csv"
BASE_NUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_60000.txt"
HOTSPOT_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_hotspot_80_5.txt"
BASE_URL="http://127.0.0.1:8080"
NGINX_CONF_PATH="/etc/nginx/conf.d/ticket_lb.conf"

# Environment variables with defaults
LOCAL_UPSTREAM_HOST="${LOCAL_UPSTREAM_HOST:-127.0.0.1}"
DIRECT_UPSTREAM_SERVERS="${DIRECT_UPSTREAM_SERVERS:-}"
TOTAL_WORKERS="${TOTAL_WORKERS:-}"
RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672/%2F}"
REQUEST_QUEUE="${REQUEST_QUEUE:-tickets.buy}"
INFLIGHT="${INFLIGHT:-256}"
REST_CONCURRENCY="${REST_CONCURRENCY:-128}"
REPEATS="${REPEATS:-3}"

# Determine BENCH_PYTHON
BENCH_PYTHON="${PROJECT_ROOT}/scripts/.venv-indirect/bin/python"
if [[ ! -x "${BENCH_PYTHON}" ]]; then
    BENCH_PYTHON="python3"
fi

# Parse remote servers
REMOTE_SERVERS_ARRAY=()
REMOTE_WORKER_COUNT=0
if [[ -n "${DIRECT_UPSTREAM_SERVERS}" ]]; then
    read -r -a REMOTE_SERVERS_ARRAY <<< "${DIRECT_UPSTREAM_SERVERS}"
    REMOTE_WORKER_COUNT="${#REMOTE_SERVERS_ARRAY[@]}"
fi

# Determine worker counts
if [[ -z "${TOTAL_WORKERS}" ]]; then
    if [[ "${REMOTE_WORKER_COUNT}" -gt 0 ]]; then
        TOTAL_WORKERS="$((REMOTE_WORKER_COUNT + 1))"
    else
        TOTAL_WORKERS="4"
    fi
fi

LOCAL_WORKER_COUNT="$((TOTAL_WORKERS - REMOTE_WORKER_COUNT))"

if [[ "${LOCAL_WORKER_COUNT}" -lt 0 ]]; then
    echo "TOTAL_WORKERS (${TOTAL_WORKERS}) cannot be smaller than remote workers (${REMOTE_WORKER_COUNT})" >&2
    exit 1
fi

if [[ -n "${DIRECT_UPSTREAM_SERVERS}" && "${LOCAL_WORKER_COUNT}" -eq 0 ]]; then
    echo "Warning: all workers are remote; this machine will only run NGINX and benchmarks." >&2
fi

mkdir -p "${RESULTS_DIR}"

echo "architecture,workers,run,model,workload,operations,elapsed_seconds,throughput_ops_s,success,seat_taken,duplicate,error" > "${OUT_FILE}"

write_nginx_conf() {
    local workers="$1"

    tmp_file=$(mktemp)
    {
        echo "upstream ticket_workers {"
        echo "    least_conn;"
        for i in $(seq 1 "${workers}"); do
            port=$((8000 + i))
            echo "    server ${LOCAL_UPSTREAM_HOST}:${port};"
        done
        for server in ${REMOTE_SERVERS_ARRAY[@]}; do
            echo "    server ${server};"
        done
        echo "}"
        echo ""
        echo "server {"
        echo "    listen 8080;"
        echo "    server_name _;"
        echo ""
        echo "    location / {"
        echo "        proxy_pass http://ticket_workers;"
        echo "        proxy_http_version 1.1;"
        echo "        proxy_set_header Host \$host;"
        echo "        proxy_set_header X-Real-IP \$remote_addr;"
        echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
        echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
        echo "    }"
        echo "}"
    } > "${tmp_file}"

    sudo cp "${tmp_file}" "${NGINX_CONF_PATH}"
    rm -f "${tmp_file}"
    sudo nginx -t
    sudo systemctl reload nginx
}

append_result() {
    local architecture="$1"
    local workers="$2"
    local run_id="$3"
    local model="$4"
    local workload="$5"
    local output="$6"

    operations=$(echo "${output}" | awk -F': ' '/Operations:/ {print $2}')
    elapsed=$(echo "${output}" | awk -F': ' '/Elapsed seconds:/ {print $2}')
    throughput=$(echo "${output}" | awk -F': ' '/Throughput ops\/s:/ {print $2}')
    success=$(echo "${output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    seat_taken=$(echo "${output}" | awk -F': ' '/SEAT_TAKEN:/ {print $2}')
    duplicate=$(echo "${output}" | awk -F': ' '/DUPLICATE:/ {print $2}')
    error=$(echo "${output}" | awk -F': ' '/ERROR:/ {print $2}')

    seat_taken=${seat_taken:-0}

    echo "${architecture},${workers},${run_id},${model},${workload},${operations},${elapsed},${throughput},${success},${seat_taken},${duplicate},${error}" >> "${OUT_FILE}"
}

python3 "${PROJECT_ROOT}/scripts/generate_hotspot_numbered.py" --input "${BASE_NUMBERED_BENCH}" --output "${HOTSPOT_BENCH}" --hot-ratio 0.8 --hot-seat-ratio 0.05 --seed 42

for run_id in $(seq 1 "${REPEATS}"); do
    echo "[Direct] workers=${LOCAL_WORKER_COUNT} run=${run_id}"
    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${LOCAL_WORKER_COUNT}"
    write_nginx_conf "${LOCAL_WORKER_COUNT}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/numbered" >/dev/null
    direct_output=$(python3 "${PROJECT_ROOT}/scripts/benchmark_numbered_rest.py" --file "${HOTSPOT_BENCH}" --base-url "${BASE_URL}" --concurrency "${REST_CONCURRENCY}")
    append_result "direct" "${TOTAL_WORKERS}" "${run_id}" "numbered" "hotspot_80_5" "${direct_output}"

    echo "[Indirect] workers=${LOCAL_WORKER_COUNT} local run=${run_id} (assuming remote workers running)"
    bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_rabbitmq_workers.sh" "${LOCAL_WORKER_COUNT}"
    sleep 2

    bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"
    indirect_output=$("${BENCH_PYTHON}" "${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py" --model numbered --file "${HOTSPOT_BENCH}" --rabbitmq-url "${RABBITMQ_URL}" --request-queue "${REQUEST_QUEUE}" --inflight "${INFLIGHT}")
    append_result "indirect" "${TOTAL_WORKERS}" "${run_id}" "numbered" "hotspot_80_5" "${indirect_output}"
done

bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true

echo "Hotspot comparison results written to ${OUT_FILE}"
