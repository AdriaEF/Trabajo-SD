#!/bin/bash

echo ""
echo ""
echo "================================================================================"
echo "============================  PREPARAR ENTORNO  ================================"
echo "================================================================================"
echo ""

chmod +x ../*

python3 -m venv .venv
source .venv/bin/activate
pip install -r ../direct/rest/service/requirements.txt
pip install -r requirements_indirect.txt
pip install -r requirements_report.txt

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

bash stop_direct_workers.sh || true
bash start_direct_workers.sh 4
bash run_direct_healthcheck.sh 127.0.0.1 8001
curl -s http://127.0.0.1:8001/debug/worker

echo ""
echo "================================================================================"
echo "================ BENCHMARK RAPIDO SIN NGINX (DIRECTO A UN WORKER) =============="
echo "================================================================================"
echo ""

curl -s -X POST http://127.0.0.1:8001/admin/reset/unnumbered >/dev/null
python3 benchmark_unnumbered_rest.py --file ../benchmarks/benchmark_unnumbered_20000.txt --base-url http://127.0.0.1:8001 --concurrency 64

# Señal de que está bien: SUCCESS cerca de 20000, sin errores inesperados.

echo ""
echo "================================================================================"
echo "================ TEST COMPLETO DIRECTO CON BALANCEADOR (PARTE 4) ==============="
echo "================================================================================"
echo ""

# Si ya se tiene nginx instalado:

sudo cp ticket_lb.conf /etc/nginx/conf.d/ticket_lb.conf
sudo nginx -t
sudo systemctl reload nginx
curl -s http://127.0.0.1:8080/health
bash run_part4_scaling_experiment.sh

# Resultado esperado: Se genera results/direct_scaling_results.csv.

echo ""
echo "================================================================================"
echo "================= SMOKE TEST ARQUITECTURA INFIRECTA (RABBITMQ) ================="
echo "================================================================================"
echo ""

bash stop_rabbitmq_workers.sh || true
bash start_rabbitmq_workers.sh 4
bash reset_ticket_state.sh
python3 benchmark_rabbitmq.py --model unnumbered --file ../benchmarks/benchmark_unnumbered_20000.txt --rabbitmq-url amqp://guest:guest@127.0.0.1:5672/%2F --request-queue tickets.buy --inflight 256

# Resultado esperado: SUCCESS cerca de 20000.

echo ""
echo "================================================================================"
echo "====================== TEST COMPLETO INDIRECTO (PARTE 5) ======================="
echo "================================================================================"
echo ""

bash run_part5_scaling_experiment.sh

# Resultado esperado: Se genera results/indirect_scaling_results.csv.

echo ""
echo "================================================================================"
echo "============================== PRUEBAS AVANZADAS ==============================="
echo "================================================================================"
echo ""

# Hotspot

bash run_part6_hotspot_experiment.sh

# Fallos

bash run_part7_fault_injection.sh

echo ""
echo "================================================================================"
echo "======================== VERIFICACION FINAL DE ARTEFACTOS ======================"
echo "================================================================================"
echo ""

ls -lh results
head -n 5 results/direct_scaling_results.csv
head -n 5 results/indirect_scaling_results.csv

# Si algo falla, verificar logs de workers: scripts/worker_1.log y scripts/rabbitmq_worker_1.log

echo ""
echo "================================================================================"
echo "=============================  FINAL EJECUCION  ================================"
echo "================================================================================"
echo ""
echo ""
