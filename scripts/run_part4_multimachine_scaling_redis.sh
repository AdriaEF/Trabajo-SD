#!/usr/bin/env bash
set -euo pipefail

# Runs direct REST scaling experiment for multiple machines.
# Usage examples:
#   LOCAL_UPSTREAM_HOST="10.0.0.11" \
#   DIRECT_UPSTREAM_SERVERS="10.0.0.12:8001 10.0.0.12:8002 10.0.0.12:8003 10.0.0.12:8004" \
#   WORKERS_LIST="1 2 4" \
#   bash scripts/run_part4_multimachine_scaling_redis.sh
#
#   LOCAL_UPSTREAM_HOST="10.0.0.11" \
#   DIRECT_UPSTREAM_SERVERS="10.0.0.12:8001" \
#   TOTAL_WORKERS=2 \
#   bash scripts/run_part4_multimachine_scaling_redis.sh
#
# Notes:
# - Run this script on the machine that hosts NGINX.
# - Start workers manually on the other machine(s) before running.
# - Each upstream entry must point to a reachable worker port.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${RESULTS_DIR}/direct_scaling_results.csv"
UNNUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_60000.txt"
BASE_URL="http://127.0.0.1:8080"
NGINX_CONF_PATH="/etc/nginx/conf.d/ticket_lb.conf"
LOCAL_UPSTREAM_HOST="${LOCAL_UPSTREAM_HOST:-127.0.0.1}"
DIRECT_UPSTREAM_SERVERS="${DIRECT_UPSTREAM_SERVERS:-}"
TOTAL_WORKERS="${TOTAL_WORKERS:-}"
WORKERS_LIST="${WORKERS_LIST:-}"

REMOTE_SERVERS_ARRAY=()
REMOTE_WORKER_COUNT=0
if [[ -n "${DIRECT_UPSTREAM_SERVERS}" ]]; then
    # split DIRECT_UPSTREAM_SERVERS into array by whitespace (preserves host:port entries)
    read -r -a REMOTE_SERVERS_ARRAY <<< "${DIRECT_UPSTREAM_SERVERS}"
    REMOTE_WORKER_COUNT="${#REMOTE_SERVERS_ARRAY[@]}"
fi

if [[ -z "${WORKERS_LIST}" ]]; then
    if [[ -n "${TOTAL_WORKERS}" ]]; then
        WORKERS_LIST="${TOTAL_WORKERS}"
    else
        WORKERS_LIST="1 2 4"
    fi
fi

mkdir -p "${RESULTS_DIR}"

if [[ -z "${DIRECT_UPSTREAM_SERVERS}" ]]; then
    echo "DIRECT_UPSTREAM_SERVERS is not set; defaulting to local 127.0.0.1 workers." >&2
fi

printf 'architecture,workers,model,operations,elapsed_seconds,throughput_ops_s,success,sold_out,seat_taken,duplicate,error\n' > "${OUT_FILE}"

write_nginx_conf() {
    local local_workers="$1"
    shift
    local remote_servers=("$@")

    tmp_file=$(mktemp)
    {
        echo "upstream ticket_workers {"
        echo "    least_conn;"
        if [[ "${#remote_servers[@]}" -gt 0 ]]; then
            for i in $(seq 1 "${local_workers}"); do
                port=$((8000 + i))
                echo "    server ${LOCAL_UPSTREAM_HOST}:${port};"
            done
            for server in "${remote_servers[@]}"; do
                echo "    server ${server};"
            done
        else
            for i in $(seq 1 "${local_workers}"); do
                port=$((8000 + i))
                echo "    server 127.0.0.1:${port};"
            done
        fi
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

run_and_append() {
    local workers="$1"
    local model="$2"
    local cmd="$3"

    output=$(eval "${cmd}")

    operations=$(echo "${output}" | awk -F': ' '/Operations:/ {print $2}')
    elapsed=$(echo "${output}" | awk -F': ' '/Elapsed seconds:/ {print $2}')
    throughput=$(echo "${output}" | awk -F': ' '/Throughput ops\/s:/ {print $2}')
    success=$(echo "${output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    sold_out=$(echo "${output}" | awk -F': ' '/SOLD_OUT:/ {print $2}')
    seat_taken=$(echo "${output}" | awk -F': ' '/SEAT_TAKEN:/ {print $2}')
    duplicate=$(echo "${output}" | awk -F': ' '/DUPLICATE:/ {print $2}')
    error=$(echo "${output}" | awk -F': ' '/ERROR:/ {print $2}')

    sold_out=${sold_out:-0}
    seat_taken=${seat_taken:-0}

    echo "direct,${workers},${model},${operations},${elapsed},${throughput},${success},${sold_out},${seat_taken},${duplicate},${error}" >> "${OUT_FILE}"
}

for total_workers in ${WORKERS_LIST}; do
    if ! [[ "${total_workers}" =~ ^[0-9]+$ ]] || [[ "${total_workers}" -lt 1 ]]; then
        echo "Invalid workers value in WORKERS_LIST: ${total_workers}" >&2
        exit 1
    fi

    selected_remote_servers=()
    if [[ "${REMOTE_WORKER_COUNT}" -gt 0 ]]; then
        remote_to_use="${total_workers}"
        if [[ "${remote_to_use}" -gt "${REMOTE_WORKER_COUNT}" ]]; then
            remote_to_use="${REMOTE_WORKER_COUNT}"
        fi

        for ((i = 0; i < remote_to_use; i++)); do
            selected_remote_servers+=("${REMOTE_SERVERS_ARRAY[$i]}")
        done
    fi

    local_worker_count="$((total_workers - ${#selected_remote_servers[@]}))"
    if [[ "${local_worker_count}" -lt 0 ]]; then
        echo "Computed LOCAL_WORKER_COUNT (${local_worker_count}) is invalid for total_workers=${total_workers}" >&2
        exit 1
    fi

    if [[ "${local_worker_count}" -eq 0 ]]; then
        echo "Running with ${total_workers} total workers (all remote)"
    else
        echo "Running with ${total_workers} total workers (${local_worker_count} local, ${#selected_remote_servers[@]} remote)"
    fi

    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    if [[ "${local_worker_count}" -gt 0 ]]; then
        bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${local_worker_count}"
    fi

    write_nginx_conf "${local_worker_count}" "${selected_remote_servers[@]}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/unnumbered" >/dev/null
    run_and_append "${total_workers}" "unnumbered" "python3 ${PROJECT_ROOT}/scripts/benchmark_unnumbered_rest.py --file ${UNNUMBERED_BENCH} --base-url ${BASE_URL} --concurrency 128"

    curl -s -X POST "${BASE_URL}/admin/reset/numbered" >/dev/null
    run_and_append "${total_workers}" "numbered" "python3 ${PROJECT_ROOT}/scripts/benchmark_numbered_rest.py --file ${NUMBERED_BENCH} --base-url ${BASE_URL} --concurrency 128"
done

bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true

echo "Results written to ${OUT_FILE}"
