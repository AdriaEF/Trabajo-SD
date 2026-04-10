#!/usr/bin/env bash
set -euo pipefail

# Multimachine version of run_part5_scaling_rabbit.sh
# Usage example:
#   REMOTE_WORKER_HOSTS="host1:2 host2:1" \
#   TOTAL_WORKERS=4 \
#   RABBITMQ_URL="amqp://guest:guest@10.0.0.10:5672/%2F" \
#   bash scripts/run_part5_multimachine_scaling_rabbit.sh
#
# Notes:
# - Start remote workers manually on the remote hosts before running, or use your own orchestration.
# - REMOTE_WORKER_HOSTS format: space-separated tokens, each either "host" (counts as 1) or "host:count".
# - TOTAL_WORKERS must be >= total remote workers. If not provided and there are remote workers,
#   TOTAL_WORKERS defaults to remote_count + 1. Otherwise defaults to 4.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
OUT_FILE="${RESULTS_DIR}/indirect_scaling_results.csv"
UNNUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt"
NUMBERED_BENCH="${PROJECT_ROOT}/benchmarks/benchmark_numbered_60000.txt"

RABBITMQ_URL="${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672/%2F}"
REQUEST_QUEUE="${REQUEST_QUEUE:-tickets.buy}"
INFLIGHT="${INFLIGHT:-256}"
BENCH_PYTHON="${PROJECT_ROOT}/scripts/.venv-indirect/bin/python"
WORKERS_LIST="${WORKERS_LIST:-1 2 4}"
TOTAL_WORKERS="${TOTAL_WORKERS:-4}"

if [[ ! -x "${BENCH_PYTHON}" ]]; then
    BENCH_PYTHON="python3"
fi

# Validate WORKERS_LIST values
for workers_count in ${WORKERS_LIST}; do
    if ! [[ "${workers_count}" =~ ^[0-9]+$ ]] || [[ "${workers_count}" -lt 1 ]]; then
        echo "Invalid worker count in WORKERS_LIST: ${workers_count}" >&2
        exit 1
    fi
done

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

# Scaling loop: test each worker count
for total_workers in ${WORKERS_LIST}; do
    if ! [[ "${total_workers}" =~ ^[0-9]+$ ]] || [[ "${total_workers}" -lt 1 ]]; then
        echo "Invalid workers value in WORKERS_LIST: ${total_workers}" >&2
        exit 1
    fi

    echo "Running with ${total_workers} total workers"

    bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true
    bash "${PROJECT_ROOT}/scripts/start_rabbitmq_workers.sh" "${total_workers}"
    sleep 2

    bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"
    run_and_append "${total_workers}" "unnumbered" "${BENCH_PYTHON} ${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py --model unnumbered --file ${UNNUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"

    bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"
    run_and_append "${total_workers}" "numbered" "${BENCH_PYTHON} ${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py --model numbered --file ${NUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"
done

bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true

echo "Results written to ${OUT_FILE}"