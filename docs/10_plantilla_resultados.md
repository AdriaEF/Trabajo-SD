# Plantilla de resultados y analisis

## Archivos de salida esperados

- Directa: results/direct_scaling_results.csv
- Indirecta: results/indirect_scaling_results.csv

## Tabla minima para el informe

| Arquitectura | Workers | Modelo      | Ops totales | Tiempo (s) | Throughput (ops/s) | SUCCESS | Rechazos/Conflictos |
|--------------|---------|-------------|-------------|------------|--------------------|---------|---------------------|
| direct       | 1       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| direct       | 2       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| direct       | 4       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| direct       | 1       | numbered    |             |            |                    |         | SEAT_TAKEN          |
| direct       | 2       | numbered    |             |            |                    |         | SEAT_TAKEN          |
| direct       | 4       | numbered    |             |            |                    |         | SEAT_TAKEN          |
| indirect     | 1       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| indirect     | 2       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| indirect     | 4       | unnumbered  |             |            |                    |         | SOLD_OUT            |
| indirect     | 1       | numbered    |             |            |                    |         | SEAT_TAKEN          |
| indirect     | 2       | numbered    |             |            |                    |         | SEAT_TAKEN          |
| indirect     | 4       | numbered    |             |            |                    |         | SEAT_TAKEN          |

## Graficas obligatorias

1. Throughput vs workers (direct vs indirect) en unnumbered
2. Throughput vs workers (direct vs indirect) en numbered
3. Comparacion unnumbered vs numbered por arquitectura

## Preguntas de analisis (para redactar)

1. Donde aparece el cuello de botella al subir workers?
2. En que modelo cae mas el throughput y por que?
3. Como cambia la cola en RabbitMQ bajo contencion?
4. Que tradeoff principal observas entre latencia y absorcion de picos?
