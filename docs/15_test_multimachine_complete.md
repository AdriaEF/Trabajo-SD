# Test completo Multi-Máquina con Ambas Arquitecturas

Este documento explica cómo ejecutar un test completo de ambas arquitecturas (Direct REST y RabbitMQ indirecto) en 2 máquinas diferentes usando los scripts mejorados.

## Configuración

### VM1 (tu PC)
- IP puente: `10.54.10.105` (reemplaza con tu IP real)
- Servicios: Redis, NGINX, servidor de benchmark
- Workers: 0 locales (los 4 vienen desde VM2)

### VM2 (otra PC)
- IP puente: `10.54.10.XXX` (recibirás esta del compañero)
- Servicios: Workers REST + Workers RabbitMQ
- Workers: 4 locales (2 para cada arquitectura)

## Requisitos Previos

1. **VM1 y VM2 pueden hacer ping entre sí**
   ```bash
   # En VM1:
   ping 10.54.10.XXX
   
   # En VM2:
   ping 10.54.10.105
   ```

2. **Redis accessible desde VM2**
   ```bash
   # En VM2:
   bash scripts/diagnose_redis.sh 10.54.10.105 6379
   ```

3. **RabbitMQ accessible desde VM2**
   - RabbitMQ debe estar activo en VM1 con usuario guest:guest

## Paso a Paso

### Paso 1: En VM2 - Arrancar workers (direct REST + RabbitMQ)

```bash
cd ~/Escriptori/Trabajo-SD

# Opción A: Solo 1 worker de cada tipo
bash scripts/test_start_workers.sh 10.54.10.105 10.54.10.105 1

# Opción B: 4 workers de cada tipo (recomendado)
bash scripts/test_start_workers.sh 10.54.10.105 10.54.10.105 4
```

**Qué hace este script:**
1. Crea/activa venv
2. Instala dependencias (direct REST + RabbitMQ worker)
3. Verifica conexión a Redis
4. Verifica conexión a RabbitMQ
5. Lanza 4 workers de RabbitMQ
6. Verifica que RabbitMQ workers enviaron heartbeat
7. Lanza 4 workers de REST en puertos 8001-8004
8. Verifica que los workers REST responden a `/health`

**Salida esperada:**
```
=== Installing Direct REST dependencies ===
=== Installing RabbitMQ worker dependencies ===
=== Precheck: Redis redis://10.54.10.105:6379/0 ===
✓ Redis ping OK: redis://10.54.10.105:6379/0
=== Precheck: RabbitMQ amqp://guest:guest@10.54.10.105:5672/%2F ===
✓ RabbitMQ connection OK: amqp://guest:guest@10.54.10.105:5672/%2F
=== Starting RabbitMQ workers ===
Started rabbit-worker-1 (PID: 12345)
...
=== Postcheck: RabbitMQ worker heartbeat ===
RabbitMQ worker 1: heartbeat detected in log
...
=== Starting Direct REST workers ===
Started direct-worker-1 on port 8001 (PID: 12346)
...
=== Postcheck: Direct REST worker health ===
Health OK: http://127.0.0.1:8001/health
...
✓ All workers started successfully!
```

### Paso 2: En VM1 - Obtener IP de VM2

```bash
# El compañero ejecutará en VM2:
ip a

# Y te dará la IP del adaptador puente (ej: 10.54.10.220)
```

### Paso 3: En VM1 - Arrancar servidor y benchmark

```bash
cd ~/Escriptori/Trabajo-SD

# Reemplaza 10.54.10.220 con la IP real de VM2
bash scripts/test_run_server.sh 10.54.10.105 "10.54.10.220:8001 10.54.10.220:8002 10.54.10.220:8003 10.54.10.220:8004" 4
```

**Qué hace este script:**
1. Activa venv
2. Instala dependencias
3. Verifica que Redis está activo
4. Verifica que NGINX está activo (lo arrancan si está parado)
5. Verifica que los 4 workers remotos responden a `/health`
6. Ejecuta El test Part 4 (Direct REST scaling con NGINX)
7. Ejecuta el test Part 5 (RabbitMQ scaling distribution)
8. Genera archivos de resultado en `results/`

## Monitoreo En Tiempo Real

### Ver logs de workers REST (VM2)
```bash
tail -f scripts/worker_*.log
```

### Ver logs de workers RabbitMQ (VM2)
```bash
tail -f scripts/rabbitmq_worker_*.log
```

### Ver status de Redis (VM1)
```bash
redis-cli ping
redis-cli DBSIZE
redis-cli FLUSHALL  # Limpiar si necesitas hacer reset
```

### Ver status de RabbitMQ (VM1)
```bash
sudo rabbitmqctl list_queues
sudo rabbitmqctl status
```

## Troubleshooting

### "connection refused" en VM2

Verifica conectividad:
```bash
# En VM2
nc -vz 10.54.10.105 6379    # Redis
nc -vz 10.54.10.105 5672    # RabbitMQ
```

Si falla, revisa firewall en VM1:
```bash
# En VM1
sudo ufw status
sudo ufw allow 6379/tcp     # Redis
sudo ufw allow 5672/tcp     # RabbitMQ
```

### Workers listos pero benchmark falla

Verifica que hay 4 workers en VM2:
```bash
# En VM2
curl http://127.0.0.1:8001/health
curl http://127.0.0.1:8002/health
curl http://127.0.0.1:8003/health
curl http://127.0.0.1:8004/health
```

### "no module named redis" o "no module named pika"

El script debería haber instalado las dependencias automáticamente. Si falla:
```bash
# En VM2
source /path/to/.venv/bin/activate
pip install redis pika
```

## Resultados

Los resultados se guardan automáticamente en:
- **Part 4 (Direct REST)**: `results/direct_scaling_results.csv`
- **Part 5 (RabbitMQ)**: `results/indirect_scaling_results.csv`

Para analizar:
```bash
cat results/direct_scaling_results.csv
cat results/indirect_scaling_results.csv
```

## Limpiar/Parar

### Parar workers en VM2
```bash
bash scripts/stop_direct_workers.sh
bash scripts/stop_rabbitmq_workers.sh
```

### Limpiar state en VM1
```bash
redis-cli FLUSHALL
```

## Notas Importantes

1. El script `test_start_workers.sh` ahora levanta **ambos tipos de workers** (4 REST + 4 RabbitMQ).
2. El script `test_run_server.sh` ejecuta automáticamente ambos benchmarks (Part 4 y Part 5).
3. Si no especificas la IP de RabbitMQ, asume que es la misma que la de Redis.
4. Los workers se quedan en escucha indefinidamente esperando requests del benchmark.

## Ejemplo Completo

**Terminal VM2:**
```bash
$ bash scripts/test_start_workers.sh 10.54.10.105 10.54.10.105 4
✓ All workers started successfully!
Logs:
  Direct REST: tail -f scripts/worker_*.log
  RabbitMQ:    tail -f scripts/rabbitmq_worker_*.log
```

**Terminal VM1:**
```bash
$ bash scripts/test_run_server.sh 10.54.10.105 "10.54.10.220:8001 10.54.10.220:8002 10.54.10.220:8003 10.54.10.220:8004" 4
# Ejecuta los benchmarks automáticamente...
```

Los resultados aparecerán en `results/direct_scaling_results.csv` y `results/indirect_scaling_results.csv`.
