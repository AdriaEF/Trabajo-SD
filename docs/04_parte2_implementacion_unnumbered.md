# Parte 2 - Implementacion unnumbered (explicacion)

## Que se implemento

En el servicio REST se anadio:

- Endpoint de compra: POST /buy/unnumbered
- Persistencia en Redis
- Idempotencia por request_id
- Control atomico para no superar 20.000 ventas

## Por que se usa Lua en Redis

Con mucha concurrencia, hacer varios pasos separados en la API puede generar carreras.
El script Lua ejecuta todos los pasos de validacion/actualizacion de forma atomica dentro de Redis.

Asi evitamos:

- Overselling por carreras
- Inconsistencias entre contador y registro de request_id

## Logica funcional resumida

1. Si request_id ya existe, respuesta DUPLICATE
2. Si sold >= 20.000, respuesta SOLD_OUT
3. Si hay cupo, incrementar sold y devolver SUCCESS
4. Guardar resultado por request_id para idempotencia

## Nota de idempotencia

Si el cliente reintenta el mismo request_id por timeout, no se procesa dos veces.
Esto evita dobles ventas por reintentos de red.

## Endpoint de reset

Se incluyo POST /admin/reset/unnumbered para limpiar estado en pruebas.
En produccion real se protegeria con autenticacion o se eliminaria.
