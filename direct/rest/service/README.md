# Direct REST Worker

Servicio REST para arquitectura directa.
Incluye healthcheck, modelo unnumbered y modelo numbered con control atomico en Redis.

## Ejecutar

1. Instalar dependencias
   pip install -r requirements.txt

2. Arrancar servicio
   uvicorn app:app --host 0.0.0.0 --port 8000

3. Probar healthcheck
   GET /health

Respuesta esperada:

{
   "status": "ok o degraded",
  "service": "direct-rest-worker",
   "phase": "part-2-unnumbered",
   "redis": "ok o unreachable"
}

## Endpoint de compra unnumbered

POST /buy/unnumbered

Body:

{
   "client_id": "c1",
   "request_id": "req-001"
}

Posibles estados:

- SUCCESS
- SOLD_OUT
- DUPLICATE

## Endpoint de compra numbered

POST /buy/numbered

Body:

{
   "client_id": "c1",
   "seat_id": 150,
   "request_id": "req-900"
}

Posibles estados:

- SUCCESS
- SEAT_TAKEN
- DUPLICATE

## Reset para pruebas

POST /admin/reset/unnumbered

Uso: limpiar estado entre ejecuciones de benchmark.

POST /admin/reset/numbered

Uso: limpiar estado de asientos/requests entre benchmarks numbered.
