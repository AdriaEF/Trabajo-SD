# Parte 6 - Escenario de alta contencion 80/5

## Objetivo

Forzar hotspots para estudiar como cae la escalabilidad cuando muchas peticiones
compiten por pocos asientos.

Regla usada:

- 80% de las operaciones apuntan al 5% de asientos
- En 20.000 asientos, zona caliente = asientos 1..1000

## Scripts agregados

- Generador de benchmark hotspot:
  - `scripts/generate_hotspot_numbered.py`
- Experimento comparativo directa vs indirecta:
  - `scripts/run_part6_hotspot_experiment.sh`

## Ejecucion en Linux VM

1. Generar benchmark hotspot:

python3 scripts/generate_hotspot_numbered.py --input benchmarks/benchmark_numbered.txt --output benchmarks/benchmark_numbered_hotspot_80_5.txt --hot-ratio 0.8 --hot-seat-ratio 0.05 --seed 42

2. Ejecutar experimento completo:

bash scripts/run_part6_hotspot_experiment.sh

3. Revisar salida:

results/hotspot_comparison_results.csv

## Que mide este experimento

- Throughput por arquitectura con 1/2/4 workers
- Impacto de contencion alta en colisiones (`SEAT_TAKEN`)
- Sensibilidad a escalado bajo hotspot

## Lectura tecnica esperada

1. Por que contencion alta reduce throughput:

- Muchas operaciones caen en las mismas claves de Redis
- Aumentan rechazos por asiento ocupado
- La utilidad de agregar workers se reduce antes

2. Diferencias tipicas entre arquitecturas:

- Directa: respuesta inmediata, pero puede saturarse rapido en picos
- Indirecta: cola amortigua picos, pero puede acumular backlog

3. Riesgos observables:

- Queue buildup en indirecta
- Throughput collapse en ambas si la contencion domina
