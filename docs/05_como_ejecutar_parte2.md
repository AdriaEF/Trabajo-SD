# Parte 2 y 3 - Como ejecutar (REST unnumbered + numbered)

## 1. Arrancar Redis

Ejemplo local:

redis-server

## 2. Arrancar API

Desde direct/rest/service:

pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000

## 3. Resetear estado antes del benchmark

POST /admin/reset/unnumbered

Ejemplo PowerShell:

Invoke-RestMethod -Uri http://127.0.0.1:8000/admin/reset/unnumbered -Method Post

## 4. Ejecutar benchmark

python scripts/benchmark_unnumbered_rest.py --file benchmarks/benchmark_unnumbered.txt --base-url http://127.0.0.1:8000 --concurrency 128

Para numbered:

python scripts/benchmark_numbered_rest.py --file benchmarks/benchmark_numbered.txt --base-url http://127.0.0.1:8000 --concurrency 128

## 5. Validacion esperada

- SUCCESS debe ser exactamente 20.000
- No debe haber overselling
- SOLD_OUT representa intentos posteriores sin stock

Para numbered:

- No se puede vender el mismo asiento dos veces
- `SEAT_TAKEN` representa colisiones bajo contencion

## 6. Si se ejecuta en varias VMs

- Exponer API por IP publica/privada de la VM
- Mantener Redis accesible para workers
- Ajustar --base-url al balanceador o endpoint compartido
