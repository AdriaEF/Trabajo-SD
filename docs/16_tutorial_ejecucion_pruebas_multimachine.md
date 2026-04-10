# Tutorial de Ejecución Paso a Paso - Pruebas Multimachine

## Resumen General

Este tutorial explica cómo ejecutar el test completo del sistema distribuido entre varias máquinas:

Para simplificar, se explicará con dos máquinas. En caso de usar más, se dispone de la versión de los comandos adaptada a ello.

- **VM1 (Servidor central)**: Redis, RabbitMQ, NGINX, benchmark cliente
- **VM2 (Workers remotos)**: workers REST y workers RabbitMQ

El test incluye:
- Part 4: Escalado directo con 1, 2 y 4 workers REST
- Part 5: Escalado indirecto con 1, 2 y 4 workers RabbitMQ
- Part 6: Escenario hotspot (80/5) comparando ambas arquitecturas
- Part 7: Inyección de fallos

## Requisitos Previos

### En ambas máquinas:
- Python 3.10+
- Proyecto ya disponible en `~/Trabajo-SD`

### En VM1 (servidor central):
- Redis server activo
- RabbitMQ server activo
- NGINX instalado
- netcat-openbsd (para verificaciones de conectividad)

`start_services.sh` se ejecuta solo en VM1 (servidor central).

### En VM2 (workers):
- Acceso por red a VM1
- Puertos 8001-8004 disponibles para workers REST

### Conectividad:
- VM1 y VM2 deben hacer ping entre sí
- VM2 debe poder alcanzar Redis en VM1:6379
- VM2 debe poder alcanzar RabbitMQ en VM1:5672

## Primera Acción Obligatoria (Todas las Máquinas)

Antes de cualquier otro paso, ejecuta esto en **todas** las máquinas (VM1, VM2, VM3...):

```bash
cd ~/Trabajo-SD
bash scripts/setup_debian.sh
```

Este script prepara paquetes del sistema, servicios base y entornos Python.

---

## PASO 0: Identificar IPs

Antes de empezar, obtén las IPs de las máquinas en la red compartida.

### En VM1:
```bash
ip a
# Busca una línea como: inet 192.168.1.100/24 brd ...
# Obtén la IP de la red compartida (no 127.0.0.1)
VM1_IP="192.168.1.100"  # REEMPLAZA CON TU IP DE VM1
```

### En VM2:
```bash
ip a
# Busca una línea como: inet 192.168.1.101/24 brd ...
# Obtén la IP de la red compartida (no 127.0.0.1)
VM2_IP="192.168.1.101"  # REEMPLAZA CON TU IP DE VM2
```

**Si tienes más máquinas (VM3, VM4, etc.) para workers adicionales:**
```bash
# VM3, VM4, etc. también necesitan su IP
VM3_IP="192.168.1.102"
VM4_IP="192.168.1.103"
# ... y así sucesivamente
```

Anota **todas** las IPs, las usarás en los comandos posteriores.

---

## PASO 1: Preparar VM1 (Servidor Central)

### 1.1 Instalar y configurar servicios base

En VM1, ejecuta el script de setup que configura todo automáticamente:

```bash
cd ~/Trabajo-SD
sudo bash scripts/start_services.sh
```

Este script:
- Instala Redis, RabbitMQ, NGINX, netcat, Python dependencies
- Configura Redis para escuchar en la red (bind 0.0.0.0, protected-mode no)
- Arranca y habilita todos los servicios
- Verifica que Redis responde localmente

### 1.2 Crear usuario remoto para RabbitMQ

En VM1, ejecuta el script para crear un usuario RemotePool para acceso remoto:

```bash
# Crear usuario (reemplaza 'myuser' y 'mypass' con tus credenciales)
sudo bash scripts/setup_rabbitmq_remote_user.sh myuser mypass
```

Ejemplo con credenciales específicas:
```bash
sudo bash scripts/setup_rabbitmq_remote_user.sh sduser sdpass123
```

**Anota las credenciales**, las usarás al arrancar workers en VM2.

### 1.3 Verificar conectividad desde VM2

Desde VM2, usa los scripts de diagnóstico para verificar que alcanzas los servicios de VM1:

```bash
# En VM2, reemplaza $VM1_IP con tu IP real (ej: 192.168.1.100)
cd ~/Trabajo-SD

# Verificar Redis
bash scripts/diagnose_redis.sh $VM1_IP 6379

# Verificar RabbitMQ
bash scripts/diagnose_rabbitmq.sh $VM1_IP 5672 myuser mypass
# (reemplaza myuser y mypass con las que creaste en 1.2)
```

---

## PASO 2: En VM2 - Arrancar Workers

Este script arranca automáticamente:
- N workers REST (puertos 8001 a 8000+N)
- N workers RabbitMQ

### Ejecutar script de arranque de workers

Reemplaza `$VM1_IP` con tu IP real de VM1 y usa las credenciales creadas en PASO 1.2. El comando arranca 4 workers de cada tipo (2 workers REST + 2 workers RabbitMQ):

```bash
# En VM2
cd ~/Trabajo-SD

# Uso:
# bash scripts/test_start_workers.sh <ip_redis> <ip_rabbit> [num_workers] [rabbit_user] [rabbit_pass]

# Ejemplo con usuario personalizado (ej: sduser / sdpass123)
bash scripts/test_start_workers.sh $VM1_IP $VM1_IP 4 sduser sdpass123
# Comando real:
# bash scripts/test_start_workers.sh 192.168.1.100 192.168.1.100 4 sduser sdpass123
```

**Nota:** Si tienes múltiples máquinas (VM2, VM3, VM4...) con workers, ejecuta este comando en **cada una** para distribuir los workers.

El script realiza estos pasos automáticamente:
1. Crea venv si no existe
2. Instala dependencias (REST + RabbitMQ)
3. Verifica conexión a Redis (en VM1)
4. Verifica conexión a RabbitMQ (en VM1) con las credenciales proporcionadas
5. Arranca 4 workers RabbitMQ
6. Verifica heartbeat de workers RabbitMQ
7. Arranca 4 workers REST (puertos 8001-8004)
8. Verifica health de workers REST

**Salida esperada al final:**

```
All workers started successfully!

Logs:
  Direct REST: tail -f scripts/worker_*.log
  RabbitMQ:    tail -f scripts/rabbitmq_worker_*.log
```

Puedes monitorizar los workers observando los archivos de log.

---

## PASO 3: En VM1 - Ejecutar Benchmark Completo

El script `test_run_server.sh` ejecuta todos los tests automáticamente.

### 3.1 Preparar VM1

```bash
# En VM1
cd ~/Trabajo-SD
```

### 3.2 Obtener IPs y lista de workers remotos

```bash
# Ejemplo con 2 máquinas (VM1 = 192.168.1.100, VM2 = 192.168.1.101):
SERVER_IP="192.168.1.100"    # IP de VM1 (Redis/RabbitMQ)
REMOTE_SERVERS="192.168.1.101:8001 192.168.1.101:8002 192.168.1.101:8003 192.168.1.101:8004"

# Si tienes más máquinas con workers simultáneamente:
# REMOTE_SERVERS="192.168.1.101:8001 192.168.1.101:8002 192.168.1.102:8001 192.168.1.102:8002"
# (aquí mezclamos workers de VM2 y VM3)
```

### 3.3 Ejecutar test completo

```bash
# En VM1, reemplaza IPs y credenciales con las tuyas
# Uso:
# bash scripts/test_run_server.sh <server_ip> <remote_servers> [total_workers] [rabbitmq_ip] [rabbitmq_user] [rabbitmq_pass]

bash scripts/test_run_server.sh \
  $SERVER_IP \
  "$REMOTE_SERVERS" \
  4 \
  $SERVER_IP \
  sduser \
  sdpass123

# Ejemplo real con IPs (usa las credenciales que creaste en PASO 1.2):
# bash scripts/test_run_server.sh \
#   192.168.1.100 \
#   "192.168.1.101:8001 192.168.1.101:8002 192.168.1.101:8003 192.168.1.101:8004" \
#   4 \
#   192.168.1.100 \
#   sduser \
#   sdpass123
```

**Parámetros:**
- `$SERVER_IP`: IP de VM1 (servidor central con Redis/RabbitMQ)
- `"$REMOTE_SERVERS"`: Lista de workers REST remotos (puede incluir múltiples máquinas)
- `4`: número total de workers simultáneamente
- IP de RabbitMQ (usualmente igual a Redis)
- usuario RabbitMQ (el que creaste en PASO 1.2)
- contraseña RabbitMQ (la que creaste en PASO 1.2)

**Para múltiples máquinas:**
```bash
# Si tienes workers en VM2, VM3 y VM4:
REMOTE_SERVERS="\
192.168.1.101:8001 192.168.1.101:8002 \
192.168.1.102:8001 192.168.1.102:8002 \
192.168.1.103:8001 192.168.1.103:8002"

bash scripts/test_run_server.sh \
  192.168.1.100 \
  "$REMOTE_SERVERS" \
  6 \
  192.168.1.100
```

**El script tardará 15-30 minutos aprox.** y ejecutará automáticamente:

1. **Part 4 - Direct REST scaling**: 1, 2, 4 workers (benchmark unnumbered + numbered)
2. **Part 5 - RabbitMQ scaling**: 1, 2, 4 workers (benchmark unnumbered + numbered)
3. **Part 6 - Hotspot experiment**: Comparativa directa vs indirecta con 80/5
4. **Part 7 - Fault injection**: Escenarios de fallo controlado

## PASO 4: Revisar Resultados

Una vez terminado, los resultados están en `results/` en VM1:

```bash
# En VM1, ver archivos generados
cd ~/Trabajo-SD/results
ls -lh *.csv

# Archivos generados:
# - direct_scaling_results.csv      (Part 4)
# - indirect_scaling_results.csv    (Part 5)
# - hotspot_comparison_results.csv  (Part 6)
# - fault_injection_results.csv     (Part 7)

# Ver contenido
cat direct_scaling_results.csv
cat indirect_scaling_results.csv
cat hotspot_comparison_results.csv
cat fault_injection_results.csv
```

Los CSVs incluyen columnas como:
- `workers`: número de workers (1, 2, 4)
- `elapsed_seconds`: tiempo total de ejecución
- `total_requests`: peticiones totales
- `successful`: compras exitosas
- `throughput_ops_sec`: operaciones por segundo
- `model`: unnumbered o numbered

---

## Ejemplo Completo Terminal a Terminal

### Terminal en VM2 (Tab 1):
```bash
$ bash scripts/test_start_workers.sh 192.168.1.100 192.168.1.100 4 sduser sdpass123
=== Installing Direct REST dependencies ===
...
✓ Redis ping OK: redis://192.168.1.100:6379/0
✓ RabbitMQ connection OK: amqp://sduser:sdpass123@192.168.1.100:5672/%2F
=== Starting RabbitMQ workers ===
Started rabbit-worker-1 (PID: 12345)
Started rabbit-worker-2 (PID: 12346)
Started rabbit-worker-3 (PID: 12347)
Started rabbit-worker-4 (PID: 12348)
=== Starting Direct REST workers ===
Started direct-worker-1 on port 8001 (PID: 12349)
Started direct-worker-2 on port 8002 (PID: 12350)
Started direct-worker-3 on port 8003 (PID: 12351)
Started direct-worker-4 on port 8004 (PID: 12352)
All workers started successfully!
```

### Terminal en VM2 (Tab 2 - Monitoreo):
```bash
$ tail -f scripts/worker_*.log
=== Direct Worker 1 startup at Thu Apr 10 14:32:01 CEST 2026 ===
INFO:     Uvicorn running on http://0.0.0.0:8001

=== Direct Worker 2 startup at Thu Apr 10 14:32:01 CEST 2026 ===
INFO:     Uvicorn running on http://0.0.0.0:8002
...
```

### Terminal en VM1 (Tab 1 - Benchmarks):
```bash
$ bash scripts/test_run_server.sh 192.168.1.100 "192.168.1.101:8001 192.168.1.101:8002 192.168.1.101:8003 192.168.1.101:8004" 4
Precheck: service status redis-server
...
Health OK: 192.168.1.101:8001
Health OK: 192.168.1.101:8002
Health OK: 192.168.1.101:8003
Health OK: 192.168.1.101:8004
Using remote upstream servers: 192.168.1.101:8001 192.168.1.101:8002 192.168.1.101:8003 192.168.1.101:8004

=== Running Part 4: Direct REST scaling (via NGINX) ===
...
[Progress] workers=1 model=unnumbered elapsed=45.23s throughput=442.5 ops/s ...
[Progress] workers=2 model=unnumbered elapsed=28.12s throughput=711.0 ops/s ...
[Progress] workers=4 model=unnumbered elapsed=18.45s throughput=1085.0 ops/s ...

=== Running Part 5: RabbitMQ scaling ===
...
[Progress] workers=1 model=unnumbered elapsed=52.1s throughput=384.1 ops/s ...
```

### Al terminar, resultados en VM1:
```bash
$ ls -lh results/*.csv
-rw-r--r-- 1 user user 2.3K Apr 10 15:42 direct_scaling_results.csv
-rw-r--r-- 1 user user 2.1K Apr 10 15:55 indirect_scaling_results.csv
-rw-r--r-- 1 user user 1.8K Apr 10 16:02 hotspot_comparison_results.csv
-rw-r--r-- 1 user user 3.2K Apr 10 16:15 fault_injection_results.csv

$ cat direct_scaling_results.csv
workers,model,elapsed_seconds,total_requests,successful,throughput_ops_sec
1,unnumbered,45.23,20000,20000,442.5
2,unnumbered,28.12,20000,20000,711.0
4,unnumbered,18.45,20000,20000,1085.0
...
```