#!/usr/bin/env bash
set -euo pipefail

# Multimachine version of run_part5_scaling_experiment.sh
# Usage example:
#   REMOTE_WORKER_HOSTS="host1:2 host2:1" \
#   TOTAL_WORKERS=4 \
#   RABBITMQ_URL="amqp://guest:guest@10.0.0.10:5672/%2F" \
#   bash scripts/run_part5_multimachine_experiment.sh
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

REMOTE_WORKER_HOSTS="${REMOTE_WORKER_HOSTS:-}"
TOTAL_WORKERS="${TOTAL_WORKERS:-}"

# Parse remote hosts list and compute remote worker count.
REMOTE_TOKENS=()
REMOTE_WORKER_COUNT=0
if [[ -n "${REMOTE_WORKER_HOSTS}" ]]; then
    read -r -a REMOTE_TOKENS <<< "${REMOTE_WORKER_HOSTS}"
    for tok in "${REMOTE_TOKENS[@]}"; do
        if [[ "${tok}" =~ ^([^:]+):([0-9]+)$ ]]; then
            count="${BASH_REMATCH[2]}"
            REMOTE_WORKER_COUNT=$((REMOTE_WORKER_COUNT + count))
        else
            # token without count -> one worker
            REMOTE_WORKER_COUNT=$((REMOTE_WORKER_COUNT + 1))
        fi
    done
fi

# Determine total and local worker counts
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

if [[ -n "${REMOTE_WORKER_HOSTS}" && "${LOCAL_WORKER_COUNT}" -eq 0 ]]; then
    echo "Warning: all workers are remote; this machine will only run benchmarks." >&2
fi

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

# Stop/start only local workers
bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true
bash "${PROJECT_ROOT}/scripts/start_rabbitmq_workers.sh" "${LOCAL_WORKER_COUNT}"
sleep 2

# Run benchmarks (ensure remote workers are already running if any)
bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"
run_and_append "${TOTAL_WORKERS}" "unnumbered" "python3 ${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py --model unnumbered --file ${UNNUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"

bash "${PROJECT_ROOT}/scripts/reset_ticket_state.sh"
run_and_append "${TOTAL_WORKERS}" "numbered" "python3 ${PROJECT_ROOT}/scripts/benchmark_rabbitmq.py --model numbered --file ${NUMBERED_BENCH} --rabbitmq-url ${RABBITMQ_URL} --request-queue ${REQUEST_QUEUE} --inflight ${INFLIGHT}"

bash "${PROJECT_ROOT}/scripts/stop_rabbitmq_workers.sh" || true

echo "Results written to ${OUT_FILE}"