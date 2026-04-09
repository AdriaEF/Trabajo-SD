# Scalable Concert Ticket Acquisition System

Proyecto por fases para disenar, implementar y evaluar un sistema de venta de entradas bajo alta concurrencia.

Se comparan dos arquitecturas:

- Directa: cliente -> REST workers (con y sin balanceo)
- Indirecta: cliente -> RabbitMQ -> workers

## Objetivo

Validar correccion y escalabilidad para 20.000 entradas en dos modelos:

- Unnumbered: maximo 20.000 compras exitosas
- Numbered: cada asiento se vende como maximo una vez

## Estado del proyecto

Implementacion y documentacion completas por fases:

- Parte 1: arquitectura base y entorno
- Parte 2: unnumbered por REST
- Parte 3: numbered por REST
- Parte 4: balanceo en arquitectura directa
- Parte 5: arquitectura indirecta con RabbitMQ
- Parte 6: experimento hotspot 80/5
- Parte 7: inyeccion de fallos
- Parte 8: cierre, resultados y soporte para reporte final

## Estructura del repositorio

- `docs/`: guias tecnicas por fase y procedimientos de ejecucion
- `direct/`: servicio REST y configuracion de NGINX para balanceo
- `indirect/`: workers RabbitMQ
- `benchmarks/`: archivos de carga para pruebas
- `scripts/`: automatizacion de benchmarks, escalado, fallos y graficas
- `PLAN_TRABAJO.md`: plan general por partes

## Requisitos

- Python 3.10+
- Linux VM para validacion final (recomendado por el enunciado)
- `nc` (paquete `netcat-openbsd`) para checks TCP en scripts de prueba
- Para Parte 5 en adelante: RabbitMQ disponible

Dependencias Python principales:

- Arquitectura directa (REST): `direct/rest/service/requirements.txt`
- Arquitectura indirecta: `scripts/requirements_indirect.txt`
- Reporte y graficas: `scripts/requirements_report.txt`

## Inicio rapido

1. Instalar dependencias del servicio REST.
2. Levantar workers REST.
3. Ejecutar benchmark unnumbered y/o numbered.

Ejemplo:

```bash
pip install -r direct/rest/service/requirements.txt
bash scripts/start_direct_workers.sh 4
python scripts/benchmark_unnumbered_rest.py --help
python scripts/benchmark_numbered_rest.py --help
```

Para RabbitMQ:

```bash
pip install -r scripts/requirements_indirect.txt
python scripts/benchmark_rabbitmq.py --help
```

## Scripts principales

- `scripts/start_direct_workers.sh`: arranque de workers REST (puertos 8001..N)
- `scripts/stop_direct_workers.sh`: parada de workers REST
- `scripts/run_part4_scaling_experiment.sh`: experimento directa 1/2/4 workers
- `scripts/run_part5_scaling_experiment.sh`: experimento indirecta 1/2/4 workers
- `scripts/generate_hotspot_numbered.py`: generador de carga hotspot 80/5
- `scripts/run_part6_hotspot_experiment.sh`: comparativa directa vs indirecta en hotspot
- `scripts/run_part7_fault_injection.sh`: escenarios de fallo controlado
- `scripts/build_plots.py`: generacion de graficas finales

## Documentacion recomendada

- `docs/05_como_ejecutar_parte2.md`
- `docs/08_parte4_balanceo_directo.md`
- `docs/09_parte5_rabbitmq.md`
- `docs/11_parte6_hotspot_80_5.md`
- `docs/12_parte7_fallos.md`
- `docs/13_parte8_cierre_entrega.md`

## Notas de trabajo

- Desarrollo diario en Windows.
- Validacion y evidencia final en Linux VM.
- Los resultados (CSV/PNG) se generan al ejecutar los scripts de experimento.
