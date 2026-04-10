# Parte 4 - Balanceo en arquitectura directa (NGINX)

## Objetivo

Comparar rendimiento al escalar workers REST: 1, 2 y 4.

## Componentes agregados

- Config de NGINX: `direct/rest/nginx/ticket_lb.conf`
- Arranque multi-worker: `scripts/start_direct_workers.sh`
- Parada de workers: `scripts/stop_direct_workers.sh`
- Experimento automatizado: `scripts/run_part4_scaling_redis.sh`

## Flujo

Cliente benchmark -> NGINX (8080) -> workers REST (8001..8004) -> Redis

## Despliegue rapido en Linux VM

1. Copiar `direct/rest/nginx/ticket_lb.conf` a `/etc/nginx/conf.d/ticket_lb.conf` (opcional como base)
2. Verificar NGINX:

sudo nginx -t
sudo systemctl restart nginx

3. Lanzar experimento:

bash scripts/run_part4_scaling_redis.sh

4. Revisar CSV:

results/direct_scaling_results.csv

## Que valida esta fase

- El sistema sigue correcto al aumentar workers
- Throughput mejora al pasar de 1 a 2 y 4 workers (hasta cuellos de botella)
- Comparacion unnumbered vs numbered bajo misma infraestructura

## Nota

El script de experimento ya genera dinamicamente la config de upstream para 1/2/4 workers
y recarga NGINX automaticamente en cada iteracion.
