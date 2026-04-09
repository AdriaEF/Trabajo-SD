#!/usr/bin/env bash
set -euo pipefail

# Multimachine version of run_part7_fault_injection.sh
# Fault injection protocol for Part 7 (scaled to multimachine deployment).
#
# Scenarios covered:
# 1) Kill one local direct worker during benchmark
# 2) Kill one local RabbitMQ worker during benchmark
# 3) Restart Redis service during benchmark
#
# Usage example:
#   LOCAL_UPSTREAM_HOST="10.0.0.11" \
#   DIRECT_UPSTREAM_SERVERS="10.0.0.12:8001 10.0.0.12:8002" \
#   TOTAL_WORKERS=4 \
#   RABBITMQ_URL="amqp://admin:test@10.0.0.11:5672/%2F" \
#   bash scripts/run_part7_multimachine_fault_injection.sh
#
# Notes:
# - Run this script on the machine that hosts NGINX and runs local workers.
# - Remote workers must already be running on other machine(s).
# - Uses local workers only for fault injection (killing/restarting).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${RESULTS_DIR}/fault_injection_results.csv"
BASE_URL="http://127.0.0.1:8080"
UNNUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_60000.txt"
HOTSPOT_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_hotspot_80_5.txt"

# Environment variables with defaults
LOCAL_UPSTREAM_HOST="${LOCAL_UPSTREAM_HOST:-127.0.0.1}"
DIRECT_UPSTREAM_SERVERS="${DIRECT_UPSTREAM_SERVERS:-}"
TOTAL_WORKERS="${TOTAL_WORKERS:-}"
RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672/%2F}"
REQUEST_QUEUE="${REQUEST_QUEUE:-tickets.buy}"
REST_CONCURRENCY="${REST_CONCURRENCY:-128}"
INFLIGHT="${INFLIGHT:-256}"
REDIS_RESTART_CMD="${REDIS_RESTART_CMD:-sudo systemctl restart redis}"

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

mkdir -p "${RESULTS_DIR}"

echo "scenario,architecture,model,operations,elapsed_seconds,throughput_ops_s,success,sold_out,seat_taken,duplicate,error,notes" > "${OUT_FILE}"

append_row() {
    local scenario="$1"
    local architecture="$2"
    local model="$3"
    local output="$4"
    local notes="$5"

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
    duplicate=${duplicate:-0}
    error=${error:-0}

    echo "${scenario},${architecture},${model},${operations},${elapsed},${throughput},${success},${sold_out},${seat_taken},${duplicate},${error},${notes}" >> "${OUT_FILE}"
}

check_correctness_note() {
    local model="$1"
    local success="$2"
    local extra="$3"

    if [[ "${model}" == "unnumbered" ]]; then
        if [[ "${success}" == "20000" ]]; then
            echo "correctness_ok_unnumbered_${extra}"
        else
            echo "correctness_warning_unnumbered_success_${success}_${extra}"
        fi
        return
    fi

    if [[ "${model}" == "numbered_hotspot" ]]; then
        echo "correctness_requires_seat_uniqueness_check_${extra}"
        return
    fi

    echo "correctness_not_checked_${extra}"
}

start_background_benchmark() {
    local pid_var_name="$1"
    local output_file="$2"
    local cmd="$3"

    bash -lc "${cmd}" >"${output_file}" 2>&1 &
    local pid="$!"
    printf -v "${pid_var_name}" '%s' "${pid}"
}

read_benchmark_output_or_fail() {
    local output_file="$1"
    if [[ ! -s "${output_file}" ]]; then
        echo "Benchmark output file is empty: ${output_file}" >&2
        exit 1
    fi
    cat "${output_file}"
}

# Generate hotspot benchmark if not present
if [[ ! -f "${HOTSPOT_BENCH}" ]]; then
    python3 "${PROJECT_ROOT}/scripts/generate_hotspot_numbered.py" --input "${NUMBERED_BENCH}" --output "${HOTSPOT_BENCH}" --hot-ratio 0.8 --hot-seat-ratio 0.05 --seed 42
fi

# Check that pika module is available
"${BENCH_PYTHON}" -c "import pika" >/dev/null 2>&1 || {
    echo "Missing Python module 'pika'. Install it with: pip install -r ${PROJECT_ROOT}/scripts/requirements_indirect.txt" >&2
    exit 1
}

# Write NGINX config for local workers
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

# Only run fault injection scenarios if we have local workers
if [[ "${LOCAL_WORKER_COUNT}" -gt 0 ]]; then

    # Scenario 1: Kill direct worker
    echo "[Fault] Scenario 1: kill one local direct worker"
    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${LOCAL_WORKER_COUNT}"
    write_nginx_conf "${LOCAL_WORKER_COUNT}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/numbered" >/dev/null

    DIRECT_PIDS_FILE="${PROJECT_ROOT}/scripts/.direct_workers_pids"

    if [[ ! -f "${DIRECT_PIDS_FILE}" ]]; then
        echo "Missing ${DIRECT_PIDS_FILE}"
        exit 1
    fi

    direct_output_file=$(mktemp)
    start_background_benchmark direct_bench_pid "${direct_output_file}" "python3 ${PROJECT_ROOT}/scripts/benchmark_numbered_rest.py --file ${HOTSPOT_BENCH} --base-url ${BASE_URL} --concurrency ${REST_CONCURRENCY}"
    sleep 2

    victim_direct_pid=$(sed -n '1p' "${DIRECT_PIDS_FILE}")
    if [[ -n "${victim_direct_pid}" ]] && kill -0 "${victim_direct_pid}" 2>/dev/null; then
        kill "${victim_direct_pid}" || true
        direct_note="killed_direct_worker_pid_${victim_direct_pid}"
    else
        direct_note="direct_worker_pid_not_found"
    fi

    wait "${direct_bench_pid}" || true
    direct_output=$(read_benchmark_output_or_fail "${direct_output_file}")
    rm -f "${direct_output_file}"
    direct_success=$(echo "${direct_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    direct_correctness=$(check_correctness_note "numbered_hotspot" "${direct_success}" "after_kill")
    append_row "kill_worker" "direct" "numbered_hotspot" "${direct_output}" "${direct_note}_${direct_correctness}"

    # Scenario 2: Kill RabbitMQ worker
    echo "[Fault] Scenario 2: kill one local RabbitMQ worker"
    bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_rabbitmq_workers.sh" "${LOCAL_WORKER_COUNT}"
    sleep 2

    bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"

    RABBITMQ_PIDS_FILE="${PROJECT_ROOT}/scripts/.rabbitmq_workers_pids"

    if [[ ! -f "${RABBITMQ_PIDS_FILE}" ]]; then
        echo "Missing ${RABBITMQ_PIDS_FILE}"
        exit 1
    fi

    rabbit_output_file=$(mktemp)
    start_background_benchmark rabbit_bench_pid "${rabbit_output_file}" "${BENCH_PYTHON} ${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py --model numbered --file ${HOTSPOT_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"
    sleep 2

    victim_rabbit_pid=$(sed -n '1p' "${RABBITMQ_PIDS_FILE}")
    if [[ -n "${victim_rabbit_pid}" ]] && kill -0 "${victim_rabbit_pid}" 2>/dev/null; then
        kill "${victim_rabbit_pid}" || true
        rabbit_note="killed_rabbit_worker_pid_${victim_rabbit_pid}"
    else
        rabbit_note="rabbit_worker_pid_not_found"
    fi

    wait "${rabbit_bench_pid}" || true
    rabbit_output=$(read_benchmark_output_or_fail "${rabbit_output_file}")
    rm -f "${rabbit_output_file}"
    rabbit_success=$(echo "${rabbit_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    rabbit_correctness=$(check_correctness_note "numbered_hotspot" "${rabbit_success}" "after_kill")
    append_row "kill_worker" "indirect" "numbered_hotspot" "${rabbit_output}" "${rabbit_note}_${rabbit_correctness}"

else
    echo "Skipping local worker fault injection scenarios (no local workers configured)"
fi

# Scenario 3: Redis restart during load
echo "[Fault] Scenario 3: restart Redis during load"
bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${LOCAL_WORKER_COUNT}"
write_nginx_conf "${LOCAL_WORKER_COUNT}"
sleep 2

curl -s -X POST "${BASE_URL}/admin/reset/unnumbered" >/dev/null

redis_output_file=$(mktemp)
start_background_benchmark redis_bench_pid "${redis_output_file}" "python3 ${PROJECT_ROOT}/scripts/benchmark_unnumbered_rest.py --file ${UNNUMBERED_BENCH} --base-url ${BASE_URL} --concurrency ${REST_CONCURRENCY}"
sleep 2

set +e
bash -lc "${REDIS_RESTART_CMD}"
redis_cmd_exit=$?
set -e

wait "${redis_bench_pid}" || true
redis_output=$(read_benchmark_output_or_fail "${redis_output_file}")
rm -f "${redis_output_file}"
redis_success=$(echo "${redis_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
redis_correctness=$(check_correctness_note "unnumbered" "${redis_success}" "after_redis_restart")
append_row "restart_redis" "direct" "unnumbered" "${redis_output}" "redis_restart_cmd_exit_${redis_cmd_exit}_${redis_correctness}"

bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true

echo "Fault injection results written to ${OUT_FILE}"
