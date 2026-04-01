#!/usr/bin/env bash
set -euo pipefail

# Runs direct REST scaling experiment for workers 1, 2, 4.
# Prerequisites:
# - Redis running
# - NGINX configured with direct/rest/nginx/ticket_lb.conf
# - Python environment ready

RESULTS_DIR="results"
OUT_FILE="${RESULTS_DIR}/direct_scaling_results.csv"
UNNUMBERED_BENCH="benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="benchmarks/benchmark_numbered_60000.txt"
BASE_URL="http://127.0.0.1:8080"
NGINX_CONF_PATH="/etc/nginx/conf.d/ticket_lb.conf"

mkdir -p "${RESULTS_DIR}"

echo "architecture,workers,model,operations,elapsed_seconds,throughput_ops_s,success,sold_out,seat_taken,duplicate,error" > "${OUT_FILE}"

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

for workers in 1 2 4; do
    echo "Running with ${workers} workers"
    bash scripts/stop_direct_workers.sh || true
    bash scripts/start_direct_workers.sh "${workers}"
    write_nginx_conf "${workers}"
    sleep 2

    curl -s -X POST "${BASE_URL}/admin/reset/unnumbered" >/dev/null
    run_and_append "${workers}" "unnumbered" "python3 scripts/benchmark_unnumbered_rest.py --file ${UNNUMBERED_BENCH} --base-url ${BASE_URL} --concurrency 128"

    curl -s -X POST "${BASE_URL}/admin/reset/numbered" >/dev/null
    run_and_append "${workers}" "numbered" "python3 scripts/benchmark_numbered_rest.py --file ${NUMBERED_BENCH} --base-url ${BASE_URL} --concurrency 128"
done

bash scripts/stop_direct_workers.sh || true

echo "Results written to ${OUT_FILE}"
