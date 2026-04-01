# Parte 1 - Arquitectura base (explicada)

## 1. Problema

Hay 20.000 entradas y muchos clientes intentando comprar al mismo tiempo.
El sistema debe mantener correccion incluso cuando hay contencion.

Correccion significa:

- Unnumbered: nunca vender mas de 20.000
- Numbered: cada asiento se vende como maximo una vez

## 2. Dos arquitecturas a comparar

### 2.1 Directa (REST)

Flujo:
Cliente -> Balanceador -> API Worker -> Redis/DB

Ventajas:

- Menor latencia en condiciones normales
- Modelo simple de request/response
- Debug mas directo

Riesgos:

- Si hay picos, el balanceador y API pueden saturarse
- Alta contencion puede reducir mucho throughput

### 2.2 Indirecta (RabbitMQ)

Flujo:
Cliente -> Cola RabbitMQ -> Worker -> Redis/DB

Ventajas:

- Absorbe picos mediante cola
- Escalado de workers mas flexible
- Desacopla productor y consumidor

Riesgos:

- Mayor complejidad operacional
- Gestion de idempotencia y reintentos mas delicada

## 3. Backend de consistencia

Para esta primera version se propone Redis por simplicidad y atomicidad.

- Unnumbered: contador atomico con limite 20.000
- Numbered: estructura por asiento (set/hash) y operacion atomica de asignacion
- Idempotencia: registro por request_id

Si despues quereis comparar, se puede implementar variante SQL transaccional.

## 4. Balanceo en arquitectura directa

Se recomienda NGINX (server-side load balancing) porque:

- Es facil de desplegar
- Reparte carga entre multiples workers
- Es comun en entornos reales

Alternativa valida del enunciado:

- Round-robin en cliente con lista estatica

## 5. Metricas a recoger desde el principio

- Tiempo total de ejecucion
- Throughput (ops/s)
- Exitos y fallos
- Evolucion con numero de workers

## 6. Contencion 80/5 (hotspot)

Si 80% de compras van al 5% de asientos, aparecen:

- Colisiones sobre las mismas claves
- Mas bloqueos o reintentos
- Menor throughput efectivo
- Acumulacion de cola en arquitectura indirecta

Esta prueba es clave para comparar consistencia vs rendimiento.
