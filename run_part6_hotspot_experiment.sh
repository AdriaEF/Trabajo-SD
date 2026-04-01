#!/usr/bin/env bash
set -euo pipefail

# Runs hotspot experiment (80/5) for numbered model in both architectures.
# Output CSV is suitable for direct vs indirect comparison under contention.

RESULTS_DIR="results"
OUT_FILE="${RESULTS_DIR}/hotspot_comparison_results.csv"
BASE_NUMBERED_BENCH="benchmarks/benchmark_numbered_60000.txt"
HOTSPOT_BENCH="benchmarks/benchmark_numbered_hotspot_80_5.txt"
BASE_URL="http://127.0.0.1:8080"
NGINX_CONF_PATH="/etc/nginx/conf.d/ticket_lb.conf"
RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672/%2F}"
REQUEST_QUEUE="${REQUEST_QUEUE:-tickets.buy}"
INFLIGHT="${INFLIGHT:-256}"
REST_CONCURRENCY="${REST_CONCURRENCY:-128}"
REPEATS="${REPEATS:-3}"

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
            echo "    server 127.0.0.1:${port};"
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

python3 scripts/generate_hotspot_numbered.py --input "${BASE_NUMBERED_BENCH}" --output "${HOTSPOT_BENCH}" --hot-ratio 0.8 --hot-seat-ratio 0.05 --seed 42

for workers in 1 2 4; do
    for run_id in $(seq 1 "${REPEATS}"); do
        echo "[Direct] workers=${workers} run=${run_id}"
        bash scripts/stop_direct_workers.sh || true
        bash scripts/start_direct_workers.sh "${workers}"
        write_nginx_conf "${workers}"
        sleep 2

        curl -s -X POST "${BASE_URL}/admin/reset/numbered" >/dev/null
        direct_output=$(python3 scripts/benchmark_numbered_rest.py --file "${HOTSPOT_BENCH}" --base-url "${BASE_URL}" --concurrency "${REST_CONCURRENCY}")
        append_result "direct" "${workers}" "${run_id}" "numbered" "hotspot_80_5" "${direct_output}"

        echo "[Indirect] workers=${workers} run=${run_id}"
        bash scripts/stop_rabbitmq_workers.sh || true
        bash scripts/start_rabbitmq_workers.sh "${workers}"
        sleep 2

        bash scripts/reset_ticket_state.sh
        indirect_output=$(python3 scripts/benchmark_rabbitmq.py --model numbered --file "${HOTSPOT_BENCH}" --rabbitmq-url "${RABBITMQ_URL}" --request-queue "${REQUEST_QUEUE}" --inflight "${INFLIGHT}")
        append_result "indirect" "${workers}" "${run_id}" "numbered" "hotspot_80_5" "${indirect_output}"
    done
done

bash scripts/stop_direct_workers.sh || true
bash scripts/stop_rabbitmq_workers.sh || true

echo "Hotspot comparison results written to ${OUT_FILE}"
