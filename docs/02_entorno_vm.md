# Parte 1 - Entorno en VMs (guia practica)

## Contexto de trabajo

- Se desarrolla primero en Windows.
- La validacion oficial se ejecuta en Linux VM.
- Por tanto, hay que mantener comandos y rutas lo mas portables posible.

## Objetivo

Levantar un entorno minimo reproducible para validar servicios y preparar benchmarks.

## Topologia recomendada (minima)

- VM1: API REST + NGINX
- VM2: Redis
- VM3: RabbitMQ (para fase indirecta)

Tambien se puede empezar con 1 sola VM y separar despues.

## Requisitos base por VM

- Python 3.11+
- Git
- Redis server (si aplica)
- RabbitMQ server (si aplica)

## Nota Windows -> Linux

- Evitar dependencias exclusivas de Windows en el codigo principal.
- Mantener rutas relativas en scripts Python.
- Si se usan scripts `.ps1` en Windows, crear equivalente `.sh` para VM Linux.

## Checklist de validacion inicial

1. API responde healthcheck
2. Redis acepta conexiones
3. RabbitMQ acepta conexiones
4. Desde VM cliente se alcanza a todos por red

## Puertos tipicos

- API: 8000
- NGINX: 80 o 8080
- Redis: 6379
- RabbitMQ AMQP: 5672
- RabbitMQ panel: 15672

## Nota operativa importante

Toda validacion final debe ejecutarse en VMs/laboratorio, no solo local.

## Evidencia sugerida para el informe

- Capturas de comandos de arranque
- Tabla de IPs y roles por VM
- Resultado de healthchecks
