# Planning por fases - Scalable Concert Ticket Acquisition System

## Objetivo global
Construir, comparar y medir 2 arquitecturas (directa e indirecta) para venta de 20.000 entradas, garantizando corrección bajo alta concurrencia y analizando escalabilidad.

## Reglas de trabajo (cómo lo haremos)
- Se implementa por partes, no todo de golpe.
- Cada parte incluye:
  - Objetivo
  - Entregables
  - Criterio de "hecho"
  - Prueba minima
- Se documenta cada decision en archivos `.md` para el informe final.
- Desarrollo local: Windows.
- Validacion oficial: Linux VM (AWS Academy/laboratorio).

---

## Parte 1 - Diseno base y entorno
### Objetivo
Definir arquitectura, tecnologias y preparar entorno reproducible en VMs.

### Entregables
- Estructura de proyecto
- Decisiones tecnologicas (REST + RabbitMQ + Redis)
- Formato de logs y metricas
- Script de despliegue basico por VM

### Hecho cuando
- Se puede levantar un entorno minimo con servicios arrancando
- Todos los componentes tienen direccion/configuracion clara

### Prueba minima
- `healthcheck` de cada servicio responde OK

---

## Parte 2 - Modelo unnumbered (REST, comunicacion directa)
### Objetivo
Vender como maximo 20.000 entradas sin numerar con alto throughput.

### Entregables
- API `BUY <client_id> <request_id>`
- Mecanismo atomico (counter en Redis o transaccion en DB)
- Rechazo correcto al superar 20.000

### Hecho cuando
- Exactamente 20.000 exitos en benchmark unnumbered
- No hay overselling

### Prueba minima
- Ejecutar benchmark unnumbered en 1 VM con N workers

---

## Parte 3 - Modelo numbered (REST, comunicacion directa)
### Objetivo
Garantizar que cada asiento (1..20.000) se vende como maximo una vez.

### Entregables
- API `BUY <client_id> <seat_id> <request_id>`
- Control de concurrencia por asiento (SETNX/lock/transaccion)
- Manejo de conflictos concurrentes

### Hecho cuando
- Ningun asiento se vende dos veces
- Benchmark numbered pasa sin violaciones

### Prueba minima
- Contencion sintetica sobre pocas butacas

---

## Parte 4 - Balanceo de carga en directa
### Objetivo
Comparar estrategia de balanceo (NGINX o cliente round-robin).

### Entregables
- Configuracion NGINX o cliente RR
- Escalado horizontal de workers REST

### Hecho cuando
- Entradas se reparten entre workers
- Mejora de throughput al aumentar workers

### Prueba minima
- Experimento con 1, 2, 4 workers

---

## Parte 5 - Arquitectura indirecta (RabbitMQ)
### Objetivo
Implementar flujo asincrono cliente -> cola -> workers.

### Entregables
- Productor de solicitudes (cliente)
- Cola(s) RabbitMQ
- Consumidores workers
- Confirmacion de procesamiento (ack) y deduplicacion por request_id

### Hecho cuando
- Correccion mantenida en ambos modelos (unnumbered/numbered)
- Sistema sigue funcionando al variar workers en caliente

### Prueba minima
- Agregar y quitar workers durante benchmark

---

## Parte 6 - Escalado dinamico y contencion 80/5
### Objetivo
Evaluar comportamiento bajo hotspots y lock contention.

### Entregables
- Generador o transformador de carga 80% solicitudes sobre 5% asientos
- Graficas y analisis de colas/latencias/throughput

### Hecho cuando
- Se observa impacto de contencion y se explica tecnicamente
- Comparacion directa vs indirecta bajo hotspot

### Prueba minima
- 3 ejecuciones por arquitectura (promedio)

---

## Parte 7 - Fallos (opcional recomendado)
### Objetivo
Probar tolerancia a fallos (kill worker, kill Redis/DB, restart).

### Entregables
- Procedimiento de prueba de fallos
- Evidencia de no overselling y no doble procesamiento

### Hecho cuando
- Se documentan tradeoffs de fault tolerance

### Prueba minima
- Inyectar 1 fallo por escenario

---

## Parte 8 - Medicion, graficas, informe final
### Objetivo
Consolidar resultados y comparativas para entrega.

### Entregables
- CSV de resultados por experimento
- Graficas:
  - Throughput vs workers
  - Directa vs indirecta
  - Unnumbered vs numbered
- Informe PDF final
- Instrucciones de despliegue en AWS Academy

### Hecho cuando
- Informe responde a todos los puntos del enunciado
- Resultados son reproducibles

---

## Criterios de correccion obligatorios (recordatorio)
- Unnumbered: exactamente 20.000 compras exitosas
- Numbered: cada asiento vendido como maximo una vez
- Cualquier violacion invalida el sistema

## Siguiente paso recomendado
Comenzar por la Parte 1: diseno base + stack tecnico + estructura del repo.

---

## Estado de avance (actual)

- Parte 1 iniciada
- Estructura base de repo creada
- Documentacion inicial creada
- Servicio REST minimo con healthcheck creado
- Parte 2 implementada en version inicial (unnumbered REST + Redis atomico)
- Runner de benchmark unnumbered creado
- Parte 3 implementada en version inicial (numbered REST + control atomico por asiento)
- Runner de benchmark numbered creado
- Parte 4 preparada (NGINX + scripts de escalado + salida CSV)
- Parte 5 iniciada (worker RabbitMQ + benchmark RPC basico)
- Parte 5 mejorada (benchmark concurrente + experimento 1/2/4 workers)
- Parte 6 implementada (generador hotspot 80/5 + experimento comparativo directa/indirecta)
- Parte 7 implementada (fault injection script + guia)
- Parte 8 preparada (script de graficas + guia de cierre)

## Siguiente accion inmediata

Ejecutar en VM Partes 4-7, generar graficas de Parte 8 y redactar informe PDF final.
