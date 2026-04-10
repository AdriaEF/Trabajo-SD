#!/usr/bin/env bash
set -euo pipefail

# Multimachine version of run_part7_fault_injection.sh
# Fault injection protocol for Part 7 (scaled to multimachine deployment).
#
# Scenarios covered:
# 1) Kill one online worker during benchmark (local PID kill by default, or custom command)
# 2) Kill Redis service during benchmark
# 3) Restart service during benchmark
#
# Usage example:
#   LOCAL_UPSTREAM_HOST="10.0.0.11" \
#   DIRECT_UPSTREAM_SERVERS="10.0.0.12:8001 10.0.0.12:8002" \
#   TOTAL_WORKERS=4 \
#   RABBITMQ_URL="amqp://admin:test@10.0.0.11:5672/%2F" \
#   bash scripts/run_part7_multimachine_fault_injection.sh
#
# Notes:
# - Run this script on the machine that hosts NGINX and runs the local workers for each iteration.
# - Remote workers must already be running on other machine(s) if DIRECT_UPSTREAM_SERVERS is used.
# - To kill a remote online worker, set ONLINE_WORKER_KILL_CMD (for example via ssh).
# - The script iterates over WORKERS_LIST so fault injection is measured at 1/2/4 workers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${RESULTS_DIR}/fault_injection_results.csv"
BASE_URL="http://127.0.0.1:8080"
NGINX_CONF_PATH="/etc/nginx/conf.d/ticket_lb.conf"
UNNUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_60000.txt"
HOTSPOT_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_hotspot_80_5.txt"

# Environment variables with defaults
LOCAL_UPSTREAM_HOST="${LOCAL_UPSTREAM_HOST:-127.0.0.1}"
DIRECT_UPSTREAM_SERVERS="${DIRECT_UPSTREAM_SERVERS:-}"
TOTAL_WORKERS="${TOTAL_WORKERS:-}"
REST_CONCURRENCY="${REST_CONCURRENCY:-128}"
ONLINE_WORKER_KILL_CMD="${ONLINE_WORKER_KILL_CMD:-}"
REDIS_KILL_CMD="${REDIS_KILL_CMD:-sudo systemctl stop redis}"
REDIS_START_CMD="${REDIS_START_CMD:-sudo systemctl start redis}"
SERVICE_RESTART_CMD="${SERVICE_RESTART_CMD:-sudo systemctl restart nginx}"
WORKERS_LIST="${WORKERS_LIST:-1 2 4}"

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

for workers_count in ${WORKERS_LIST}; do
    if ! [[ "${workers_count}" =~ ^[0-9]+$ ]] || [[ "${workers_count}" -lt 1 ]]; then
        echo "Invalid workers value in WORKERS_LIST: ${workers_count}" >&2
        exit 1
    fi
done

mkdir -p "${RESULTS_DIR}"

echo "scenario,workers,architecture,model,operations,elapsed_seconds,throughput_ops_s,success,sold_out,seat_taken,duplicate,error,notes" > "${OUT_FILE}"

append_row() {
    local scenario="$1"
    local workers="$2"
    local architecture="$3"
    local model="$4"
    local output="$5"
    local notes="$6"

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

    echo "${scenario},${workers},${architecture},${model},${operations},${elapsed},${throughput},${success},${sold_out},${seat_taken},${duplicate},${error},${notes}" >> "${OUT_FILE}"
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

for total_workers in ${WORKERS_LIST}; do
    if [[ -z "${total_workers}" ]]; then
        continue
    fi

    if ! [[ "${total_workers}" =~ ^[0-9]+$ ]] || [[ "${total_workers}" -lt 1 ]]; then
        echo "Invalid workers value in WORKERS_LIST: ${total_workers}" >&2
        exit 1
    fi

    local_worker_count="$((total_workers - REMOTE_WORKER_COUNT))"
    if [[ "${local_worker_count}" -lt 0 ]]; then
        echo "Computed LOCAL_WORKER_COUNT (${local_worker_count}) is invalid for total_workers=${total_workers}" >&2
        exit 1
    fi

    echo "[Fault] Running with ${total_workers} total workers (${local_worker_count} local, ${REMOTE_WORKER_COUNT} remote)"

    # Scenario 1: Kill online direct worker
    if [[ "${local_worker_count}" -gt 0 ]] || [[ -n "${ONLINE_WORKER_KILL_CMD}" ]]; then
    echo "[Fault] Scenario 1: kill one online worker"
    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${local_worker_count}"
    write_nginx_conf "${local_worker_count}"
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

    if [[ -n "${ONLINE_WORKER_KILL_CMD}" ]]; then
        set +e
        bash -lc "${ONLINE_WORKER_KILL_CMD}"
        online_kill_exit=$?
        set -e
        direct_note="killed_online_worker_cmd_exit_${online_kill_exit}"
    else
        victim_direct_pid=$(sed -n '1p' "${DIRECT_PIDS_FILE}")
        if [[ -n "${victim_direct_pid}" ]] && kill -0 "${victim_direct_pid}" 2>/dev/null; then
            kill "${victim_direct_pid}" || true
            direct_note="killed_direct_worker_pid_${victim_direct_pid}"
        else
            direct_note="direct_worker_pid_not_found"
        fi
    fi

    wait "${direct_bench_pid}" || true
    direct_output=$(read_benchmark_output_or_fail "${direct_output_file}")
    rm -f "${direct_output_file}"
    direct_success=$(echo "${direct_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    direct_correctness=$(check_correctness_note "numbered_hotspot" "${direct_success}" "after_kill")
    append_row "kill_worker" "${total_workers}" "direct" "numbered_hotspot" "${direct_output}" "${direct_note}_${direct_correctness}"

    else
        echo "Skipping online worker kill scenario for ${total_workers} total workers (no local workers and no ONLINE_WORKER_KILL_CMD configured)"
    fi

    # Scenario 2: Redis kill during load
    echo "[Fault] Scenario 2: kill Redis during load"
    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${local_worker_count}"
    write_nginx_conf "${local_worker_count}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/unnumbered" >/dev/null

    redis_output_file=$(mktemp)
    start_background_benchmark redis_bench_pid "${redis_output_file}" "python3 ${PROJECT_ROOT}/scripts/benchmark_unnumbered_rest.py --file ${UNNUMBERED_BENCH} --base-url ${BASE_URL} --concurrency ${REST_CONCURRENCY}"
    sleep 2

    set +e
    bash -lc "${REDIS_KILL_CMD}"
    redis_kill_exit=$?
    set -e

    sleep 2

    set +e
    bash -lc "${REDIS_START_CMD}"
    redis_start_exit=$?
    set -e

    wait "${redis_bench_pid}" || true
    redis_output=$(read_benchmark_output_or_fail "${redis_output_file}")
    rm -f "${redis_output_file}"
    redis_success=$(echo "${redis_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    redis_correctness=$(check_correctness_note "unnumbered" "${redis_success}" "after_redis_kill")
    append_row "kill_redis" "${total_workers}" "direct" "unnumbered" "${redis_output}" "redis_kill_cmd_exit_${redis_kill_exit}_redis_start_cmd_exit_${redis_start_exit}_${redis_correctness}"

    # Scenario 3: Service restart during load
    echo "[Fault] Scenario 3: restart service during load"
    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_direct_workers.sh" "${local_worker_count}"
    write_nginx_conf "${local_worker_count}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/unnumbered" >/dev/null

    service_output_file=$(mktemp)
    start_background_benchmark service_bench_pid "${service_output_file}" "python3 ${PROJECT_ROOT}/scripts/benchmark_unnumbered_rest.py --file ${UNNUMBERED_BENCH} --base-url ${BASE_URL} --concurrency ${REST_CONCURRENCY}"
    sleep 2

    set +e
    bash -lc "${SERVICE_RESTART_CMD}"
    service_restart_exit=$?
    set -e

    wait "${service_bench_pid}" || true
    service_output=$(read_benchmark_output_or_fail "${service_output_file}")
    rm -f "${service_output_file}"
    service_success=$(echo "${service_output}" | awk -F': ' '/SUCCESS:/ {print $2}')
    service_correctness=$(check_correctness_note "unnumbered" "${service_success}" "after_service_restart")
    append_row "restart_service" "${total_workers}" "direct" "unnumbered" "${service_output}" "service_restart_cmd_exit_${service_restart_exit}_${service_correctness}"

    bash "${PROJECT_ROOT}/scripts/stop_direct_workers.sh" || true
done

echo "Fault injection results written to ${OUT_FILE}"
