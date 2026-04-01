# Parte 3 - Numbered REST (consistencia por asiento)

## Objetivo

Garantizar que cada asiento (1..20.000) se vende como maximo una vez,
incluso cuando muchos clientes compiten por el mismo asiento.

## Que se implemento

- Endpoint: POST /buy/numbered
- Validacion de seat_id por API (1..20.000)
- Operacion atomica en Redis para:
  - Idempotencia por request_id
  - Verificar si asiento ya estaba vendido
  - Reservar asiento si estaba libre

## Estados de salida

- SUCCESS: asiento vendido correctamente
- SEAT_TAKEN: el asiento ya fue vendido antes
- DUPLICATE: request_id repetido

## Claves Redis usadas

- `tickets:numbered:seats` (hash): seat_id -> client_id
- `tickets:numbered:requests` (hash): request_id -> resultado

## Por que esto evita doble venta

La decision de vender o rechazar un asiento se toma dentro de un script Lua
atomico en Redis. Eso elimina carreras de tipo:

- proceso A lee libre
- proceso B lee libre
- ambos intentan vender el mismo asiento

Con operacion atomica, solo uno puede ganar.

## Como probar rapido

1. Reset:

POST /admin/reset/numbered

2. Ejecutar benchmark:

python scripts/benchmark_numbered_rest.py --file benchmarks/benchmark_numbered.txt --base-url http://127.0.0.1:8000 --concurrency 128

3. Validar:

- Ningun asiento vendido dos veces
- `SEAT_TAKEN` refleja conflictos esperados
