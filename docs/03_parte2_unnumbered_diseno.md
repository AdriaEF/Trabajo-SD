# Parte 2 - Diseno de unnumbered (antes de codificar)

## Requisito de correccion

Deben existir exactamente 20.000 compras exitosas.
Todas las compras adicionales deben fallar.

## API propuesta

POST /buy/unnumbered

Body JSON:

- client_id: string
- request_id: string

## Respuestas

- SUCCESS: compra aceptada
- SOLD_OUT: no hay stock
- DUPLICATE: request_id ya procesado

## Estado en Redis (propuesto)

- counter key: `tickets:unnumbered:sold`
- request registry key: `tickets:unnumbered:requests`

## Logica atomica esperada

1. Si request_id ya existe, devolver DUPLICATE
2. Leer contador actual
3. Si contador >= 20.000, devolver SOLD_OUT
4. Incrementar contador
5. Registrar request_id como SUCCESS

Nota:
Para evitar carreras, estos pasos deben estar en una operacion atomica (Lua script o transaccion WATCH/MULTI).

## Metricas minimas por ejecucion

- total_ops
- success_count
- sold_out_count
- duplicate_count
- elapsed_seconds
- throughput_ops_per_sec

## Criterio de hecho Parte 2

- Success exacto: 20.000
- Overselling: 0
- Duplicates gestionados sin doble venta
