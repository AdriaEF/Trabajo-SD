#!/usr/bin/env bash
set -euo pipefail

# Runs RabbitMQ scaling experiment for workers 1, 2, 4.
# Prerequisites:
# - RabbitMQ running
# - Redis running
# - Python dependencies installed for benchmark + worker

RESULTS_DIR="results"
OUT_FILE="${RESULTS_DIR}/indirect_scaling_results.csv"
UNNUMBERED_BENCH="benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="benchmarks/benchmark_numbered_60000.txt"
RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672/%2F}"
REQUEST_QUEUE="${REQUEST_QUEUE:-tickets.buy}"
INFLIGHT="${INFLIGHT:-256}"

mkdir -p "${RESULTS_DIR}"

echo "architecture,workers,model,operations,elapsed_seconds,throughput_ops_s,success,sold_out,seat_taken,duplicate,error" > "${OUT_FILE}"

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

    echo "indirect,${workers},${model},${operations},${elapsed},${throughput},${success},${sold_out},${seat_taken},${duplicate},${error}" >> "${OUT_FILE}"
}

for workers in 1 2 4; do
    echo "Running RabbitMQ with ${workers} workers"
    bash scripts/stop_rabbitmq_workers.sh || true
    bash scripts/start_rabbitmq_workers.sh "${workers}"
    sleep 2

    bash scripts/reset_ticket_state.sh
    run_and_append "${workers}" "unnumbered" "python3 scripts/benchmark_rabbitmq.py --model unnumbered --file ${UNNUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"

    bash scripts/reset_ticket_state.sh
    run_and_append "${workers}" "numbered" "python3 scripts/benchmark_rabbitmq.py --model numbered --file ${NUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"
done

bash scripts/stop_rabbitmq_workers.sh || true

echo "Results written to ${OUT_FILE}"
