# Parte 5 - Arquitectura indirecta con RabbitMQ

## Objetivo

Implementar el flujo asincrono obligatorio:

Cliente -> RabbitMQ -> Worker -> Redis

## Componentes creados

- Worker RabbitMQ: `indirect/rabbitmq/worker/worker.py`
- Dependencias worker: `indirect/rabbitmq/worker/requirements.txt`
- Benchmark cliente RPC concurrente: `scripts/benchmark_rabbitmq.py`
- Arranque/parada workers: `scripts/start_rabbitmq_workers.sh`, `scripts/stop_rabbitmq_workers.sh`
- Reset estado Redis: `scripts/reset_ticket_state.sh`
- Experimento 1/2/4 workers: `scripts/run_part5_scaling_experiment.sh`

## Modo de trabajo actual

Se implemento modo RPC sobre cola:

1. Cliente publica request en `tickets.buy`
2. Worker procesa contra Redis con logica atomica
3. Worker responde por `reply_to`
4. Cliente mantiene ventana de requests en vuelo (inflight) para throughput alto
5. Cliente cuenta estados para metricas

## Modelos soportados

- unnumbered
- numbered

Ambos reutilizan la misma logica atomica de Redis usada en REST.

## Ejecucion minima en Linux VM

1. Instalar dependencias worker:

cd indirect/rabbitmq/worker
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

Tambien para el benchmark RabbitMQ:

pip install -r scripts/requirements_indirect.txt

2. Arrancar worker:

python3 worker.py

3. Benchmark unnumbered:

python3 scripts/benchmark_rabbitmq.py --model unnumbered --file benchmarks/benchmark_unnumbered.txt --rabbitmq-url amqp://guest:guest@<RABBIT_IP>:5672/%2F --inflight 256

4. Benchmark numbered:

python3 scripts/benchmark_rabbitmq.py --model numbered --file benchmarks/benchmark_numbered.txt --rabbitmq-url amqp://guest:guest@<RABBIT_IP>:5672/%2F --inflight 256

5. Experimento automatizado de escalado:

bash scripts/run_part5_scaling_experiment.sh

## Escalado dinamico

Para escalar, arrancad multiples procesos worker.py (en misma o distintas VMs).
RabbitMQ repartira mensajes entre consumidores activos.

## Resultado esperado de esta fase

- CSV generado en `results/indirect_scaling_results.csv`
- Comparacion directa vs indirecta lista para graficas del informe
