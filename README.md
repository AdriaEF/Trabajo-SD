# Scalable Concert Ticket Acquisition System

Proyecto por fases para comparar dos arquitecturas de compra de entradas bajo alta concurrencia:

- Arquitectura directa: REST + balanceo
- Arquitectura indirecta: RabbitMQ + workers

Este repositorio esta organizado para entregar:

- Codigo fuente
- Instrucciones de despliegue en VMs
- Resultados de benchmark y graficas
- Reporte tecnico

## Estado actual

- Parte 1 en progreso: diseno base y entorno
- Healthcheck inicial disponible para arquitectura directa
- Parte 2 y 3 base implementadas (unnumbered y numbered en REST)
- Parte 4 preparada (balanceo con NGINX + experimento de escalado)
- Parte 5 inicial implementada (RabbitMQ worker + benchmark RPC)

## Flujo de trabajo acordado

- Desarrollo en Windows (este equipo)
- Validacion final en Linux VM (AWS Academy/laboratorio)

Importante: el enunciado exige evaluar en VMs. El trabajo local en Windows se usa para avanzar implementacion y depuracion.

## Estructura

- `docs/`: explicaciones tecnicas para cada fase
- `direct/`: implementacion de comunicacion directa
- `indirect/`: implementacion de comunicacion indirecta
- `benchmarks/`: archivos de carga (sin modificar)
- `scripts/`: automatizacion de despliegue y ejecucion
- `results/`: salidas de experimentos

## Scripts clave

- `scripts/start_direct_workers.sh`: arranca workers REST en puertos 8001..N
- `scripts/stop_direct_workers.sh`: detiene workers REST arrancados por script
- `scripts/run_part4_scaling_experiment.sh`: corre experimento 1/2/4 workers y genera CSV
- `scripts/benchmark_rabbitmq.py`: benchmark para arquitectura indirecta (RabbitMQ)
- `scripts/run_part5_scaling_experiment.sh`: corre experimento indirecto 1/2/4 workers y genera CSV
- `docs/10_plantilla_resultados.md`: plantilla para consolidar resultados y redactar analisis
- `scripts/generate_hotspot_numbered.py`: genera benchmark numbered con contencion 80/5
- `scripts/run_part6_hotspot_experiment.sh`: compara directa vs indirecta bajo hotspot y genera CSV
- `scripts/run_part7_fault_injection.sh`: inyecta fallos controlados y genera CSV de resiliencia
- `scripts/build_plots.py`: genera graficas PNG para la memoria final
- `scripts/requirements_report.txt`: dependencias para generacion de graficas

Dependencia adicional para benchmark RabbitMQ:

- `pip install -r scripts/requirements_indirect.txt`

## Proximo paso

Implementar modelo unnumbered en REST con garantia de no overselling.
