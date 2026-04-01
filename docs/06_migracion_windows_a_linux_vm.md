# Windows -> Linux VM (paso rapido)

## 1. Copiar proyecto a la VM

Opciones comunes:

- git clone del repositorio en la VM
- scp/rsync desde Windows al usuario de la VM

## 2. Instalar dependencias en Linux VM

Desde direct/rest/service:

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

## 3. Arrancar Redis (si no esta como servicio)

redis-server

## 4. Arrancar API

uvicorn app:app --host 0.0.0.0 --port 8000

## 5. Probar healthcheck en Linux

bash scripts/run_direct_healthcheck.sh 127.0.0.1 8000

## 6. Ejecutar benchmark

python3 scripts/benchmark_unnumbered_rest.py --file benchmarks/benchmark_unnumbered.txt --base-url http://127.0.0.1:8000 --concurrency 128

## 7. Comprobaciones para el informe

- SUCCESS debe ser exactamente 20.000 en unnumbered
- No overselling
- Guardar tiempo total y throughput

## 8. Errores frecuentes al migrar

- Faltan puertos abiertos en firewall/security group
- REDIS_URL apunta a localhost pero Redis esta en otra VM
- Archivo benchmark no copiado a la VM
