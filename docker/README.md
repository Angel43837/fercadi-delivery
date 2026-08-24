# Docker — Fercadi Server

Servicios que corren en el VPS con Docker.

## Requisitos

- VPS con Ubuntu 22.04 (Hetzner CX22 o similar)
- Docker y Docker Compose instalados
- Dominio apuntando a la IP del VPS

## Instalación en el VPS (primera vez)

```bash
# 1. Conectarte al VPS
ssh root@IP-DEL-VPS

# 2. Instalar Docker
curl -fsSL https://get.docker.com | sh

# 3. Copiar la carpeta docker/ al VPS
# (desde tu computadora)
scp -r docker/ root@IP-DEL-VPS:/opt/fercadi

# 4. Entrar al VPS y configurar
ssh root@IP-DEL-VPS
cd /opt/fercadi

# 5. Crear el .env con tus valores reales
cp .env.example .env
nano .env   # editar con tus claves

# 6. Cambiar "tudominio.com" en nginx.conf por tu dominio real
nano nginx/nginx.conf

# 7. Obtener certificado SSL (primera vez)
docker run --rm -p 80:80 \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  certbot/certbot certonly --standalone \
  -d tudominio.com \
  -d monitor.tudominio.com \
  --email tu@email.com \
  --agree-tos --no-eff-email

# 8. Levantar todo
docker compose up -d

# 9. Verificar que todo esté corriendo
docker compose ps
```

## Comandos del día a día

```bash
# Ver qué está corriendo
docker compose ps

# Ver logs en tiempo real
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f nginx
docker compose logs -f uptime-kuma

# Reiniciar un servicio
docker compose restart nginx

# Actualizar a la última versión
docker compose pull && docker compose up -d

# Apagar todo
docker compose down
```

## Servicios incluidos

| Servicio | URL | Para qué |
|---|---|---|
| Uptime Kuma | https://monitor.tudominio.com | Monitoreo — avisa si algo se cae |
| NGINX | Puerto 80/443 | Proxy inverso y SSL |
| Certbot | Automático | Renueva SSL cada 12h |

## Estructura de carpetas

```
docker/
├── docker-compose.yml    ← orquesta los servicios
├── .env                  ← tus claves (NO va a Git)
├── .env.example          ← plantilla del .env
├── nginx/
│   └── nginx.conf        ← configuración del proxy
├── certbot/
│   ├── conf/             ← certificados SSL
│   └── www/              ← challenge de renovación
└── data/
    └── uptime-kuma/      ← datos del monitoreo
```
