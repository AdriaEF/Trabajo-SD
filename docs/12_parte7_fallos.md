# Parte 7 - Pruebas de fallos (opcional recomendado)

## Objetivo

Comprobar comportamiento del sistema cuando ocurren fallos durante carga.

Escenarios incluidos:

1. Caida de un worker en arquitectura directa
2. Caida de un worker en arquitectura indirecta (RabbitMQ)
3. Reinicio de Redis durante benchmark

## Script principal

- scripts/run_part7_fault_injection.sh

Salida:

- results/fault_injection_results.csv

## Requisitos previos (Linux VM)

- Redis y RabbitMQ activos
- NGINX configurado para arquitectura directa
- Benchmarks disponibles en carpeta benchmarks
- Permisos para reiniciar Redis si se usa scenario 3

## Ejecucion

bash scripts/run_part7_fault_injection.sh

Opcional para comando de reinicio Redis custom:

REDIS_RESTART_CMD="sudo systemctl restart redis-server" bash scripts/run_part7_fault_injection.sh

## Que mirar en resultados

- No overselling en unnumbered
- No doble venta de asiento en numbered
- Cambios de throughput/errores tras fallo
- Diferencia de degradacion entre directa e indirecta

## Tradeoffs para comentar en el informe

- Directa: menor latencia nominal, pero puede degradar mas abruptamente
- Indirecta: cola amortigua fallos parciales, pero puede acumular backlog
- Reinicio Redis: riesgo operativo alto si no hay estrategia de persistencia/replicacion

## Advertencia metodologica

El script inyecta fallos de forma controlada, pero la reproducibilidad depende del entorno VM.
Ejecutad al menos 3 repeticiones por escenario para conclusiones solidas.
