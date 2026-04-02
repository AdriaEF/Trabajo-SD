# Parte 4 Multi-Maquina (2 VMs) - Paso a Paso

Este documento describe como ejecutar la Parte 4 (arquitectura directa con NGINX) en 2 maquinas virtuales.

## Objetivo

- VM1: NGINX + benchmark + Redis + worker local
- VM2: worker remoto
- Resultado esperado: `results/direct_scaling_results.csv` generado en VM1

## 1) Arreglar red para pruebas mutlimáquina

Si tiene la IP duplicada entre VM1 y VM2 en la red interna.

1. Apaga VM1 y VM2.
2. En VirtualBox, en VM2, genera nueva MAC en cada adaptador de red.
3. Arranca VM2 y renueva DHCP:

```bash
sudo dhclient -r enp0s8
sudo dhclient enp0s8
```

4. Verifica IPs con `ip a`:
- VM1 en `enp0s8`: por ejemplo `192.168.1.10`
- VM2 en `enp0s8`: por ejemplo `192.168.1.11`

Deben ser distintas.

## 2) Comprobar conectividad entre VMs

Desde VM1:

```bash
ping -c 3 192.168.1.10
```

Desde VM2:

```bash
ping -c 3 192.168.1.11
```

## 3) Preparar Redis en VM1 para acceso remoto

En VM1, edita Redis para aceptar conexiones de VM2.

Archivo habitual:

```bash
sudo nano /etc/redis/redis.conf
```

Ajuste recomendado para laboratorio:

```conf
bind 0.0.0.0
protected-mode no
port 6379
```

Reinicia Redis:

```bash
sudo systemctl restart redis-server
sudo systemctl status redis-server --no-pager
```
Nota: En las dos vm, ejecutar venv y comporbar requerimientos antes de ejcutar comandos:

python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r direct/rest/service/requirements.txt

## 4) Arrancar worker remoto en VM2

En VM2, dentro del repo, ejecuta:

```bash
REDIS_URL="redis://192.168.1.10:6379/0" WORKERS=1 bash scripts/start_direct_workers_multimachine.sh
```

Notas:
- Sustituye `192.168.1.10` por la IP real de VM1.
- Este script escribe logs en `scripts/worker_1.log` de VM2.

## 5) Verificar desde VM1 que VM2 responde

Desde VM1:

```bash
curl -s http://192.168.1.11:8001/health
```

Debes ver un JSON con `status` y `redis`.

## 6) Ejecutar Parte 4 multi-maquina en VM1

En VM1:

```bash
sudo env LOCAL_UPSTREAM_HOST="192.168.1.10" DIRECT_UPSTREAM_SERVERS="192.168.1.11:8001" LOCAL_WORKER_COUNT=1 bash scripts/run_part4_multimachine_experiment.sh
```

Que significa:
- `LOCAL_UPSTREAM_HOST`: IP de VM1
- `DIRECT_UPSTREAM_SERVERS`: workers remotos (VM2)
- `LOCAL_WORKER_COUNT=1`: worker local en VM1

## 7) Revisar resultados y logs

En VM1:

```bash
ls -lh results/direct_scaling_results.csv
head -n 5 results/direct_scaling_results.csv
```

Logs en VM1:

```bash
tail -n 100 scripts/worker_1.log
```

Logs en VM2:

```bash
tail -n 100 scripts/worker_1.log
```

## 8) Parar workers al terminar

En VM1 y VM2:

```bash
bash scripts/stop_direct_workers.sh
```

Si fueron arrancados con sudo:

```bash
sudo bash scripts/stop_direct_workers.sh
```

## Troubleshooting rapido

- Error de conexion a VM2: revisa IPs, ping y firewall.
- `/health` responde pero benchmark falla: revisa `REDIS_URL` en VM2.
- Puertos ocupados: para workers previos con `stop_direct_workers.sh`.
- Variables no aplican con sudo: usa `sudo env ...` como en el paso 6.
