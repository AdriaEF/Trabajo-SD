#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${SCRIPT_DIR}/.venv"

echo ""
echo ""
echo "================================================================================"
echo "============================  PREPARAR ENTORNO  ================================"
echo "================================================================================"
echo ""

chmod +x "${SCRIPT_DIR}"/*.sh

python3 -m venv "${VENV_PATH}"
source "${VENV_PATH}/bin/activate"
pip install -r "${PROJECT_ROOT}/direct/rest/service/requirements.txt"
pip install -r "${SCRIPT_DIR}/requirements_indirect.txt"
pip install -r "${SCRIPT_DIR}/requirements_report.txt"

echo ""
echo "================================================================================"
echo "========================  LEVANTAR DEPENDENCIAS BASE  =========================="
echo "================================================================================"
echo ""

sudo systemctl enable --now redis-server
sudo systemctl enable --now rabbitmq-server
sudo systemctl status redis-server --no-pager
sudo systemctl status rabbitmq-server --no-pager

echo ""
echo "================================================================================"
echo "===================  SMOKE TEST ARQUITECTURA DIRECTA (REST)  ==================="
echo "================================================================================"
echo ""

bash "${SCRIPT_DIR}/stop_direct_workers.sh" || true
bash "${SCRIPT_DIR}/start_direct_workers.sh" 4
bash "${SCRIPT_DIR}/run_direct_healthcheck.sh" 127.0.0.1 8001
curl -s http://127.0.0.1:8001/debug/worker

echo ""
echo "================================================================================"
echo "================ BENCHMARK RAPIDO SIN NGINX (DIRECTO A UN WORKER) =============="
echo "================================================================================"
echo ""

curl -s -X POST http://127.0.0.1:8001/admin/reset/unnumbered >/dev/null
python3 "${SCRIPT_DIR}/benchmark_unnumbered_rest.py" --file "${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt" --base-url http://127.0.0.1:8001 --concurrency 64

# Señal de que está bien: SUCCESS cerca de 20000, sin errores inesperados.

echo ""
echo "================================================================================"
echo "================ TEST COMPLETO DIRECTO CON BALANCEADOR (PARTE 4) ==============="
echo "================================================================================"
echo ""

sudo cp "${PROJECT_ROOT}/direct/rest/nginx/ticket_lb.conf" /etc/nginx/conf.d/ticket_lb.conf
sudo nginx -t
sudo systemctl reload nginx
curl -s http://127.0.0.1:8080/health
bash "${SCRIPT_DIR}/run_part4_scaling_experiment.sh"

# Resultado esperado: Se genera results/direct_scaling_results.csv.

echo ""
echo "================================================================================"
echo "================= SMOKE TEST ARQUITECTURA INDIRECTA (RABBITMQ) ================="
echo "================================================================================"
echo ""

bash "${SCRIPT_DIR}/stop_rabbitmq_workers.sh" || true
bash "${SCRIPT_DIR}/start_rabbitmq_workers.sh" 4
bash "${SCRIPT_DIR}/reset_ticket_state.sh"
python3 "${SCRIPT_DIR}/benchmark_rabbitmq.py" --model unnumbered --file "${PROJECT_ROOT}/benchmarks/benchmark_unnumbered_20000.txt" --rabbitmq-url amqp://guest:guest@127.0.0.1:5672/%2F --request-queue tickets.buy --inflight 256

# Resultado esperado: SUCCESS cerca de 20000.

echo ""
echo "================================================================================"
echo "====================== TEST COMPLETO INDIRECTO (PARTE 5) ======================="
echo "================================================================================"
echo ""

bash "${SCRIPT_DIR}/run_part5_scaling_experiment.sh"

# Resultado esperado: Se genera results/indirect_scaling_results.csv.

echo ""
echo "================================================================================"
echo "============================== PRUEBAS AVANZADAS ==============================="
echo "================================================================================"
echo ""

# Hotspot
bash "${SCRIPT_DIR}/run_part6_hotspot_experiment.sh"

# Fallos
bash "${SCRIPT_DIR}/run_part7_fault_injection.sh"

echo ""
echo "================================================================================"
echo "======================== VERIFICACION FINAL DE ARTEFACTOS ======================"
echo "================================================================================"
echo ""

ls -lh "${PROJECT_ROOT}/results"
head -n 5 "${PROJECT_ROOT}/results/direct_scaling_results.csv"
head -n 5 "${PROJECT_ROOT}/results/indirect_scaling_results.csv"

# Si algo falla, verificar logs de workers: scripts/worker_1.log y scripts/rabbitmq_worker_1.log

echo ""
echo "================================================================================"
echo "=============================  FINAL EJECUCION  ================================"
echo "================================================================================"
echo ""
echo ""
