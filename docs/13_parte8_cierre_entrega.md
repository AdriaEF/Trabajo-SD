# Parte 8 - Cierre de resultados y entrega

## Objetivo

Consolidar resultados, generar graficas y cerrar memoria tecnica.

## Scripts y artefactos

- Dependencias para graficas: scripts/requirements_report.txt
- Generador de graficas: scripts/build_plots.py

## Ejecucion (Linux VM)

1. Instalar dependencias:

pip install -r scripts/requirements_report.txt

2. Generar graficas:

python3 scripts/build_plots.py --results-dir results --plots-dir results/plots

## Graficas generadas

- results/plots/throughput_vs_workers_unnumbered.png
- results/plots/throughput_vs_workers_numbered.png
- results/plots/model_comparison.png
- results/plots/hotspot_80_5_comparison.png

## Checklist de entrega

1. Codigo fuente completo
2. Instrucciones de despliegue en AWS Academy / laboratorio
3. CSVs y graficas de resultados
4. Reporte PDF con comparativa directa vs indirecta

## Estructura minima sugerida del PDF

1. Introduccion y objetivos
2. Descripcion de arquitectura directa e indirecta
3. Garantias de consistencia y diseno de concurrencia
4. Metodologia experimental
5. Resultados base (1/2/4 workers)
6. Resultados hotspot 80/5
7. Resultados de fallos (opcional)
8. Discusion de tradeoffs
9. Conclusiones

## Frase de conclusion recomendada (base)

No existe una arquitectura universalmente superior: directa e indirecta muestran ventajas distintas segun carga, nivel de contencion y requisitos de resiliencia.
