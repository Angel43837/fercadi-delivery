# Grupo Fercadi — Hoja de Ruta Técnica V1.0
### Documento Técnico Oficial · Versión 1.0 Local — Maravatío, Michoacán
**Fecha:** 2026-06-12 · **Enfoque:** Lanzar y operar en Maravatío con clientes reales

---

## Tabla de Contenidos

1. [Estado Actual del Proyecto](#1-estado-actual-del-proyecto)
2. [Arquitectura General](#2-arquitectura-general)
3. [Despliegue y Hosting](#3-despliegue-y-hosting)
   - [3.7 Docker — Por qué importa y cómo usarlo](#37-docker--por-qué-importa-y-cómo-usarlo-en-v10)
4. [Base de Datos](#4-base-de-datos)
5. [Sistema de Pagos](#5-sistema-de-pagos)
6. [Seguridad](#6-seguridad)
7. [Operación y Soporte](#7-operación-y-soporte)
8. [Roadmap V1.0](#8-roadmap-v10)
9. [Costos Reales del Proyecto](#9-costos-reales-del-proyecto)
10. [Checklist Antes de Lanzar](#10-checklist-antes-de-lanzar)
11. [Qué hacer primero](#11-qué-hacer-primero)

---

# 1. Estado Actual del Proyecto

## 1.1 Resumen

**Grupo Fercadi** es una app de delivery local para Maravatío, Michoacán. Conecta restaurantes del municipio con clientes a través de repartidores independientes. Está construida en **Flutter** (Android + Web) con **Supabase** como backend.

El proyecto está en estado **MVP avanzado** — la mayoría de las funciones están implementadas. Lo que falta no es código nuevo sino afinar, asegurar y lanzar lo que ya existe.

---

## 1.2 Funcionalidades Implementadas

| Módulo | Estado | Notas |
|---|---|---|
| Login con email y contraseña | ✅ Listo | |
| Login con Google | ✅ Listo | |
| Pantalla de restaurantes | ✅ Listo | Acordeón, likes en tiempo real |
| Categorías con íconos 2D | ✅ Listo | |
| Detalle de producto + carrusel de fotos | ✅ Listo | |
| Carrito de compras | ✅ Listo | Solo un restaurante a la vez |
| Checkout con dirección de entrega | ✅ Listo | |
| Pago con tarjeta (Android) | ✅ Listo | Stripe + Edge Function |
| Pago con tarjeta (Web) | ⚠️ No funciona | flutter_stripe no corre en web |
| Tracking del repartidor en mapa | ✅ Listo | |
| Notificaciones push FCM | ✅ Listo | Al cambiar estado del pedido |
| Historial de pedidos | ✅ Listo | |
| Perfil de usuario con foto | ✅ Listo | |
| Compresión WebP en imágenes subidas | ✅ Listo | ~50% más ligeras |
| Panel de Administrador | ✅ Listo | Dashboard, pedidos, restaurantes, usuarios |
| Panel del Dueño del restaurante | ✅ Listo | Menú, productos, fotos |
| Panel del Repartidor | ✅ Listo | Ver pedidos, aceptar, entregar |
| Registro de repartidores | ✅ Listo | |
| Registro de restaurantes | ✅ Listo | |
| Zona de servicio (30 km radio) | ✅ Listo | Centrado en Maravatío |
| Selección de dirección en mapa | ✅ Listo | GPS preciso |
| Despliegue web en Vercel | ✅ Listo | |

---

## 1.3 Lo que Falta para V1.0

Estas son las únicas cosas que se necesitan antes de tener clientes reales. No son funciones nuevas complicadas — son ajustes y configuraciones.

| Qué falta | Por qué importa | Tiempo estimado |
|---|---|---|
| **RLS en Supabase** | Sin esto cualquier usuario ve datos de otros. Crítico. | 1–2 días |
| **APK release firmado** | El debug APK no sirve para distribución real | 1 día |
| **Stripe en modo live** | Ahorita está en modo test, los pagos no son reales | 2 horas |
| **Pago en efectivo** | Mucha gente en Maravatío no tiene tarjeta | 1 día |
| **Opción de calificar el pedido** | Retroalimentación básica para el restaurante | 2 días |
| **Dominio propio** | Profesionalismo, no usar `.vercel.app` | 1 hora |
| **Email transaccional** | Confirmación de pedido por correo | 1 día |
| **Restaurantes reales onboarding** | Necesitas al menos 3 restaurantes activos | 1 semana |
| **Repartidores reales** | Al menos 5 listos antes de lanzar | 1 semana |

---

## 1.4 Riesgos Reales (los que afectan hoy)

| Riesgo | Qué tan grave | Qué hacer |
|---|---|---|
| Sin RLS en la base de datos | 🔴 Crítico | Implementar esta semana |
| APK en modo debug | 🔴 Crítico | Generar release firmado |
| Stripe en modo test | 🔴 Crítico | Activar modo live |
| Sin pago en efectivo | 🟡 Importante | Muchos usuarios locales no tienen tarjeta |
| Tracking por polling cada 5s | 🟡 Importante | Gasta créditos de Supabase. Migrar a Realtime |
| Sin correo de confirmación | 🟡 Importante | Usuarios no saben que su pedido llegó |
| Google Maps API sin restricciones | 🟡 Importante | Alguien podría abusar de tu API key |

---

# 2. Arquitectura General

## 2.1 Cómo está montado el sistema

```mermaid
graph TB
    subgraph Usuarios
        A[📱 App Android\nAPK / Play Store]
        B[🌐 App Web\nVercel]
    end

    subgraph Backend
        C[🔐 Supabase Auth\nLogin y roles]
        D[🗄️ PostgreSQL\nBase de datos]
        E[⚡ Edge Functions\nStripe, notificaciones]
        F[📡 Realtime\nLikes en vivo]
        G[🗃️ Storage\nFotos de productos]
    end

    subgraph Externos
        H[💳 Stripe\nPagos con tarjeta]
        I[🔔 Firebase FCM\nNotificaciones push]
        J[🗺️ Google Maps\nTracking y mapa]
    end

    A --> C
    B --> C
    C --> D
    A --> D
    B --> D
    A --> E
    E --> H
    E --> I
    A --> F
    A --> G
    A --> J
```

**En palabras simples:** La app Flutter habla directamente con Supabase. Supabase maneja login, base de datos, almacenamiento de fotos y notificaciones en tiempo real. Para pagos, una Edge Function (mini-servidor en la nube de Supabase) se comunica con Stripe de forma segura.

---

## 2.2 Los 4 tipos de usuario

```mermaid
graph TD
    A[App Fercadi] --> B{¿Cuál es tu rol?}
    B --> C[👤 Cliente\nPide comida]
    B --> D[🛵 Repartidor\nEntrega pedidos]
    B --> E[🍽️ Dueño\nGestiona su restaurante]
    B --> F[⚙️ Admin\nVe todo, gestiona la plataforma]
```

| Rol | Accede a | Lo que puede hacer |
|---|---|---|
| **Cliente** | App normal | Ver restaurantes, pedir, rastrear, historial |
| **Repartidor** | Panel repartidor | Ver pedidos disponibles, aceptar, marcar entregado |
| **Dueño** | Panel dueño | Gestionar su menú, ver sus pedidos, subir fotos |
| **Admin** | Panel admin | Ver todo, cambiar estados, gestionar usuarios |

---

## 2.3 Flujo de un pedido (de punta a punta)

```mermaid
sequenceDiagram
    participant C as Cliente
    participant App
    participant DB as Supabase DB
    participant R as Repartidor
    participant D as Dueño

    C->>App: Elige platillo y paga
    App->>DB: Crea pedido (status: pending)
    DB->>D: Notificación: nuevo pedido
    DB->>R: Pedido disponible visible
    R->>App: Acepta el pedido
    DB->>C: Notificación: repartidor en camino
    R->>App: Marca como entregado
    DB->>C: Notificación: pedido entregado
```

---

## 2.4 Tecnologías usadas

| Tecnología | Para qué sirve |
|---|---|
| Flutter 3 / Dart | La app completa (Android + Web) |
| Supabase | Base de datos, login, archivos, tiempo real |
| Stripe | Pagos con tarjeta |
| Firebase FCM | Notificaciones push al celular |
| Google Maps Flutter | Mapa de tracking y selección de dirección |
| Vercel | Hosting de la versión web |
| flutter_image_compress | Comprimir fotos a WebP antes de subirlas |

---

# 3. Despliegue y Hosting

## 3.1 Situación actual

| Componente | Dónde vive | Costo |
|---|---|---|
| App Web | Vercel (hobby) | Gratis |
| Base de datos y backend | Supabase (free) | Gratis hasta cierto punto |
| Fotos | Supabase Storage | Incluido |
| Notificaciones | Firebase (Spark) | Gratis |

Para V1.0 local en Maravatío **no necesitas un servidor propio**. Supabase + Vercel es suficiente mientras tengas menos de ~500 pedidos al mes.

---

## 3.2 Qué cambiar para producción

### Supabase: pasar de Free a Pro ($25 USD/mes)

El plan gratuito tiene estos límites que se van a romper rápido:

| Límite | Plan Free | Plan Pro |
|---|---|---|
| Almacenamiento DB | 500 MB | 8 GB |
| Ancho de banda | 5 GB/mes | 250 GB/mes |
| Backups automáticos | ❌ No | ✅ Diario (7 días) |
| Soporte | Comunidad | Email |
| Conexiones simultáneas | 60 | 200 |

**Cuándo subir a Pro:** Cuando tengas restaurantes reales o antes de lanzar públicamente. Los backups automáticos son esenciales.

### Vercel: quedarse en Hobby por ahora

El plan gratuito de Vercel aguanta bien la versión web. Solo necesitarás subir si tienes miles de visitas simultáneas, lo cual no pasa en V1.0 local.

---

## 3.3 Dominio propio

Registra un dominio como `fercadi.com` o `gofercadi.com.mx`:

| Registrador | Precio anual | Nota |
|---|---|---|
| GoDaddy | ~$150 MXN/año (.com.mx) | Conocido, fácil |
| Namecheap | ~$100 MXN/año (.com) | Más barato |
| Google Domains | ~$180 MXN/año | Simple, integrado |

Después de comprar el dominio:
1. En Vercel: Settings → Domains → agregar tu dominio
2. En tu registrador: apuntar DNS a los servidores de Vercel
3. En Supabase: Authentication → URL Configuration → cambiar Site URL a tu dominio

---

## 3.4 Google OAuth con dominio propio

Cuando cambies el dominio, actualizar en Supabase:
```
Authentication → URL Configuration
Site URL: https://tudominio.com
Redirect URLs: https://tudominio.com/**
```

Y en Google Cloud Console (el OAuth):
```
Authorized redirect URIs: 
  https://mmjzyqvjdwhzefbaiums.supabase.co/auth/v1/callback
  https://tudominio.com
```

---

## 3.5 Compilar el APK de producción (release)

El APK debug que tienes ahorita no sirve para distribución real. Para generar el release:

**Paso 1:** Crear keystore (solo una vez — guárdalo en lugar seguro)
```bash
keytool -genkey -v -keystore fercadi-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias fercadi
```

**Paso 2:** Crear `android/key.properties`
```properties
storePassword=tu_contraseña
keyPassword=tu_contraseña
keyAlias=fercadi
storeFile=../fercadi-release.jks
```

**Paso 3:** Compilar release
```bash
flutter build apk --release
# El APK queda en: build/app/outputs/flutter-apk/app-release.apk
```

> ⚠️ El archivo `fercadi-release.jks` y `key.properties` **NUNCA** van al repositorio de Git. Si los pierdes no puedes actualizar la app en Play Store.

---

## 3.6 Variables de entorno (mover secretos fuera del código)

Actualmente las credenciales están hardcodeadas en `constants.dart`. Para producción, compilar así:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://mmjzyqvjdwhzefbaiums.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=STRIPE_PK=pk_live_...
```

Y en `constants.dart`:
```dart
static const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
static const String stripePublishableKey =
    String.fromEnvironment('STRIPE_PK', defaultValue: '');
```

---

## 3.7 Docker — Por qué importa y cómo usarlo en V1.0

### ¿Para qué sirve Docker?

Docker empaqueta una aplicación junto con todo lo que necesita para correr (sistema operativo, dependencias, configuración) dentro de un **contenedor**. Ese contenedor corre igual en tu computadora, en un VPS barato o en cualquier servidor del mundo.

```
Sin Docker:                    Con Docker:
─────────────────              ─────────────────────────────
"En mi máquina sí corre"  →   "Corre igual en cualquier lado"
Instalar dependencias a mano   docker compose up  ← listo
Configuración manual           Variables de entorno en .env
Difícil de actualizar          docker compose pull && up -d
```

---

### ¿Qué se dockeriza en V1.0?

En V1.0 **no dockerizas la app Flutter** (eso va a Vercel o como APK). Docker se usa para los **servicios propios** que corren en un VPS. Para Fercadi, estos son:

| Servicio | ¿Para qué? | ¿Necesita VPS? |
|---|---|---|
| **Uptime Kuma** | Monitoreo — te avisa si algo cae | Sí (o usar BetterStack gratis) |
| **Panel Admin** (futuro Next.js) | Interfaz web de administración | Sí |
| **NGINX** | Proxy inverso + SSL para lo de arriba | Sí |
| **Certbot** | Renueva el certificado SSL automático | Sí |

> **Si ahorita usas Supabase Cloud + Vercel:** No necesitas un VPS todavía. Docker entra cuando quieras montar tu propio servidor para el panel admin o para controlar más los costos.

---

### VPS recomendado para empezar

Para V1.0 local, el servidor más barato que funciona bien:

| Proveedor | Plan | CPU | RAM | Disco | Precio/mes |
|---|---|---|---|---|---|
| **Hetzner** (recomendado) | CX22 | 2 vCPU | 4 GB | 40 GB SSD | ~$4–8 USD |
| DigitalOcean | Droplet Basic | 1 vCPU | 1 GB | 25 GB SSD | ~$6 USD |
| Contabo | VPS S | 4 vCPU | 8 GB | 100 GB | ~$8 USD |

Con Hetzner CX22 tienes suficiente para correr el panel admin + Uptime Kuma + NGINX sin problema.

---

### Estructura de carpetas en el VPS

```
/opt/fercadi/
├── docker-compose.yml       ← orquesta todos los servicios
├── .env                     ← variables de entorno (no va a Git)
├── nginx/
│   └── nginx.conf           ← configuración del proxy inverso
├── certbot/
│   ├── conf/                ← certificados SSL (Let's Encrypt)
│   └── www/                 ← challenge de renovación
└── data/
    └── uptime-kuma/         ← datos de monitoreo
```

---

### docker-compose.yml para V1.0

```yaml
version: '3.8'

services:

  # ── Proxy inverso + SSL ───────────────────────────────────────
  nginx:
    image: nginx:alpine
    container_name: fercadi-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - uptime-kuma
    restart: always

  # ── Monitoreo de servicios ────────────────────────────────────
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: fercadi-uptime
    volumes:
      - ./data/uptime-kuma:/app/data
    restart: always
    # No exponer al exterior directamente — pasa por NGINX

  # ── Renovación automática de SSL ─────────────────────────────
  certbot:
    image: certbot/certbot
    container_name: fercadi-certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    # Se ejecuta cada 12h e intenta renovar el certificado
    entrypoint: >
      /bin/sh -c "trap exit TERM;
      while :; do
        certbot renew --webroot -w /var/www/certbot --quiet;
        sleep 12h & wait $${!};
      done;"
    restart: always

# ── Cuando agregues el panel admin (futuro) ───────────────────
#  admin-panel:
#    image: ghcr.io/fercadi/admin-panel:latest
#    container_name: fercadi-admin
#    env_file: .env
#    restart: always
```

---

### nginx/nginx.conf

```nginx
# Redirigir todo HTTP → HTTPS
server {
    listen 80;
    server_name monitor.tudominio.com;

    # Necesario para que Certbot renueve el certificado
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# Panel de monitoreo con HTTPS
server {
    listen 443 ssl http2;
    server_name monitor.tudominio.com;

    ssl_certificate /etc/letsencrypt/live/tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tudominio.com/privkey.pem;

    # Headers de seguridad básicos
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Strict-Transport-Security "max-age=31536000";

    location / {
        proxy_pass http://uptime-kuma:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

### .env — variables de entorno del servidor

```bash
# Este archivo va en el VPS, NUNCA en el repositorio de Git
# Agregar al .gitignore: echo ".env" >> .gitignore

SUPABASE_URL=https://mmjzyqvjdwhzefbaiums.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

---

### Comandos del día a día en el VPS

```bash
# Conectarse al VPS
ssh root@IP-DEL-VPS

# Primera vez — levantar todo
cd /opt/fercadi
docker compose up -d

# Ver qué está corriendo
docker compose ps

# Ver logs en tiempo real (Ctrl+C para salir)
docker compose logs -f --tail=50

# Ver logs de un servicio específico
docker compose logs -f nginx

# Reiniciar un servicio
docker compose restart nginx

# Actualizar imágenes y reiniciar
docker compose pull && docker compose up -d

# Apagar todo
docker compose down

# Apagar y borrar datos (¡CUIDADO!)
docker compose down -v
```

---

### Obtener el certificado SSL (primera vez)

```bash
# 1. Apagar nginx momentáneamente
docker compose stop nginx

# 2. Obtener el certificado con Certbot standalone
docker run --rm -p 80:80 \
  -v /opt/fercadi/certbot/conf:/etc/letsencrypt \
  certbot/certbot certonly --standalone \
  -d tudominio.com \
  -d monitor.tudominio.com \
  --email tu@email.com \
  --agree-tos --no-eff-email

# 3. Volver a levantar todo
docker compose up -d
```

A partir de ahí, el contenedor `certbot` renueva automáticamente el certificado cada 12 horas si está a punto de vencer (Let's Encrypt vence cada 90 días).

---

### Flujo de despliegue con Docker (cuando hagas cambios)

```mermaid
graph LR
    A[Cambios en el código] --> B[git push a main]
    B --> C{¿Qué cambió?}
    C --> D[App Flutter\nflutter build web\nVercel lo publica solo]
    C --> E[Panel Admin / servicios\nSSH al VPS\ndocker compose pull\ndocker compose up -d]
```

---

### Checklist Docker antes de poner en producción

- [ ] VPS contratado (Hetzner CX22 o similar)
- [ ] Docker y Docker Compose instalados en el VPS
- [ ] Carpeta `/opt/fercadi/` creada con la estructura de archivos
- [ ] Archivo `.env` creado con las variables reales (no de prueba)
- [ ] DNS del dominio apuntando a la IP del VPS
- [ ] Certificado SSL obtenido con Certbot
- [ ] `docker compose up -d` corriendo sin errores
- [ ] `docker compose ps` muestra todos los servicios como `Up`
- [ ] Uptime Kuma accesible en `https://monitor.tudominio.com`
- [ ] Uptime Kuma configurado con alertas a Telegram/email
- [ ] `.env` y `fercadi-release.jks` NO están en el repositorio de Git

---

# 4. Base de Datos

## 4.1 Tablas que necesita V1.0

```mermaid
erDiagram
    RESTAURANTS {
        uuid id PK
        uuid owner_id FK
        text name
        text description
        text address
        text emoji_icon
        bool is_open
        float rating
        timestamp created_at
    }
    CATEGORIES {
        uuid id PK
        uuid restaurant_id FK
        text name
        text icon
        int sort_order
    }
    PRODUCTS {
        uuid id PK
        uuid category_id FK
        text name
        text description
        float price
        text image_url
        bool is_available
    }
    ORDERS {
        uuid id PK
        uuid user_id FK
        uuid restaurant_id FK
        uuid repartidor_id FK
        float total
        text status
        text payment_method
        jsonb customer_info
        timestamp created_at
    }
    ORDER_ITEMS {
        uuid id PK
        uuid order_id FK
        uuid product_id FK
        int quantity
        float price
    }
    REPARTIDOR_LOCATIONS {
        uuid repartidor_id PK
        float lat
        float lng
        timestamp updated_at
    }

    RESTAURANTS ||--o{ CATEGORIES : tiene
    CATEGORIES ||--o{ PRODUCTS : tiene
    ORDERS ||--o{ ORDER_ITEMS : contiene
    PRODUCTS ||--o{ ORDER_ITEMS : aparece_en
```

---

## 4.2 Lo más urgente: RLS (Row Level Security)

Sin RLS, un usuario puede hacer una petición directa a Supabase y ver los pedidos de todos los demás. Esto se llama data leak y es el riesgo más serio del proyecto ahorita.

Ejecutar esto en el SQL Editor de Supabase:

```sql
-- ══════════════════════════════════════════
-- HABILITAR RLS EN TODAS LAS TABLAS
-- ══════════════════════════════════════════

ALTER TABLE orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurants     ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories      ENABLE ROW LEVEL SECURITY;
ALTER TABLE products        ENABLE ROW LEVEL SECURITY;
ALTER TABLE repartidor_locations ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════
-- PEDIDOS: cada quien ve solo los suyos
-- ══════════════════════════════════════════

-- Cliente: ve sus propios pedidos
CREATE POLICY "cliente_ve_sus_pedidos"
ON orders FOR SELECT
USING (auth.uid() = user_id);

-- Repartidor: ve pedidos pending + los que ya aceptó él
CREATE POLICY "repartidor_ve_pedidos"
ON orders FOR SELECT
USING (
    status = 'pending'
    OR repartidor_id = auth.uid()
);

-- Repartidor puede actualizar status de sus pedidos
CREATE POLICY "repartidor_actualiza_pedidos"
ON orders FOR UPDATE
USING (repartidor_id = auth.uid() OR status = 'pending');

-- Dueño: ve pedidos de sus restaurantes
CREATE POLICY "dueno_ve_sus_pedidos"
ON orders FOR SELECT
USING (
    restaurant_id IN (
        SELECT id FROM restaurants WHERE owner_id = auth.uid()
    )
);

-- Admin: ve y modifica todo
CREATE POLICY "admin_todo_en_orders"
ON orders FOR ALL
USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
);

-- ══════════════════════════════════════════
-- RESTAURANTES: todos ven, solo el dueño edita
-- ══════════════════════════════════════════

CREATE POLICY "todos_ven_restaurantes"
ON restaurants FOR SELECT
USING (true);

CREATE POLICY "dueno_edita_su_restaurante"
ON restaurants FOR UPDATE
USING (owner_id = auth.uid());

CREATE POLICY "admin_gestiona_restaurantes"
ON restaurants FOR ALL
USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
);

-- ══════════════════════════════════════════
-- PRODUCTOS: todos ven, solo el dueño edita
-- ══════════════════════════════════════════

CREATE POLICY "todos_ven_productos"
ON products FOR SELECT
USING (true);

CREATE POLICY "dueno_edita_sus_productos"
ON products FOR ALL
USING (
    category_id IN (
        SELECT c.id FROM categories c
        JOIN restaurants r ON c.restaurant_id = r.id
        WHERE r.owner_id = auth.uid()
    )
);

-- ══════════════════════════════════════════
-- UBICACION DEL REPARTIDOR
-- ══════════════════════════════════════════

-- El repartidor solo puede actualizar su propia ubicación
CREATE POLICY "repartidor_su_ubicacion"
ON repartidor_locations FOR ALL
USING (repartidor_id = auth.uid());

-- Cliente puede leer ubicación del repartidor de su pedido activo
CREATE POLICY "cliente_ve_ubicacion_repartidor"
ON repartidor_locations FOR SELECT
USING (
    repartidor_id IN (
        SELECT repartidor_id FROM orders
        WHERE user_id = auth.uid()
        AND status IN ('accepted', 'delivering')
    )
);
```

---

## 4.3 Agregar columna de método de pago

Para soportar pago en efectivo, agregar esta columna:

```sql
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'card'
CHECK (payment_method IN ('card', 'cash'));

ALTER TABLE orders
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending'
CHECK (payment_status IN ('pending', 'paid', 'failed'));
```

---

## 4.4 Backups

Con Supabase Pro, los backups son automáticos (diario, 7 días de retención). Adicionalmente, hacer un backup manual antes de cualquier cambio grande:

```bash
# Desde tu computadora (necesitas psql instalado)
pg_dump "postgresql://postgres.[tu-ref]:[password]@aws-0-us-west-1.pooler.supabase.com:5432/postgres" \
  --file="backup-fercadi-$(date +%Y%m%d).sql"
```

La URL de conexión la encuentras en Supabase → Settings → Database → Connection string.

---

# 5. Sistema de Pagos

## 5.1 Estado actual

- ✅ Pago con tarjeta en Android (Stripe) — funcionando en modo test
- ⚠️ Pago con tarjeta en web — no funciona (limitación de flutter_stripe)
- ❌ Pago en efectivo — no existe todavía

## 5.2 Pasar Stripe a modo live

1. Entrar a [dashboard.stripe.com](https://dashboard.stripe.com)
2. Completar la verificación de negocio (nombre, RFC, cuenta bancaria)
3. Activar modo live (toggle arriba a la derecha del dashboard)
4. Copiar las nuevas claves `pk_live_...` y `sk_live_...`
5. Actualizar `pk_live_...` en la compilación de Flutter (`--dart-define=STRIPE_PK=pk_live_...`)
6. Actualizar `sk_live_...` como variable de entorno en la Edge Function de Supabase:
   - Supabase Dashboard → Edge Functions → create-payment-intent → Secrets → agregar `STRIPE_SECRET_KEY=sk_live_...`

> La clave `sk_live_...` NUNCA va en el código de la app. Solo en la Edge Function.

---

## 5.3 Implementar pago en efectivo

Es el cambio más importante para Maravatío — mucha gente no tiene tarjeta. El flujo es simple:

**En el checkout, agregar opción de método de pago:**

```dart
// checkout_screen.dart — agregar selector de método
String _paymentMethod = 'cash'; // 'cash' o 'card'

// Selector visual
Row(children: [
  _PaymentOption(
    label: 'Efectivo',
    icon: Icons.payments_outlined,
    selected: _paymentMethod == 'cash',
    onTap: () => setState(() => _paymentMethod = 'cash'),
  ),
  _PaymentOption(
    label: 'Tarjeta',
    icon: Icons.credit_card,
    selected: _paymentMethod == 'card',
    onTap: () => setState(() => _paymentMethod = 'card'),
  ),
]),

// Al crear el pedido, guardar el método:
await SupabaseService.createOrder(
  ...
  paymentMethod: _paymentMethod,
);
```

**En Supabase, el pedido en efectivo se crea con `payment_status: 'pending'`** y el repartidor lo marca como pagado al entregar.

---

## 5.4 Comisión de Fercadi

Define desde el inicio cuánto cobra Fercadi por pedido. Para V1.0 local, lo más simple:

| Modelo | Descripción | Ventaja |
|---|---|---|
| **% del pedido** (recomendado) | 15% de cada pedido va a Fercadi | Alineación — ganas cuando el restaurante gana |
| Cuota fija mensual | El restaurante paga $X/mes | Ingresos predecibles pero no escala |
| Cobro por pedido fijo | $X por cada pedido | Simple pero penaliza pedidos grandes |

Para V1.0: cobrar **15% de comisión** sobre cada pedido. El cobro puede ser manual al principio (el restaurante paga cada semana/quincena). Automatizar con Stripe Connect cuando haya más volumen.

---

## 5.5 Webhook de Stripe para confirmar pagos

```typescript
// supabase/functions/stripe-webhook/index.ts
// Cuando Stripe confirma un pago, actualizar el pedido en DB

import Stripe from 'https://esm.sh/stripe@13.0.0'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '')
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? ''

serve(async (req) => {
  const signature = req.headers.get('stripe-signature')!
  const body = await req.text()

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(body, signature, webhookSecret)
  } catch {
    return new Response('Firma inválida', { status: 400 })
  }

  if (event.type === 'payment_intent.succeeded') {
    const pi = event.data.object as Stripe.PaymentIntent
    const orderId = pi.metadata.orderId

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    await supabase.from('orders')
      .update({ payment_status: 'paid' })
      .eq('id', orderId)
  }

  return new Response('ok')
})
```

---

# 6. Seguridad

## 6.1 Lo que está bien

- ✅ Contraseñas nunca en texto plano (Supabase las hashea con bcrypt)
- ✅ Stripe secret key solo en Edge Function, nunca en la app
- ✅ El monto del pago se verifica contra la DB en la Edge Function
- ✅ Verificación de rol en tiempo real al abrir la app

## 6.2 Lo que hay que arreglar antes de lanzar

### RLS en Supabase (ver sección 4.2)
La más urgente. Sin esto los datos están expuestos.

### Mover credenciales de constants.dart a variables de entorno

Actualmente en `constants.dart` está hardcodeado:
```dart
// ❌ PROBLEMA — visible en el APK
static const String supabaseUrl = 'https://mmjzyqvjdwhzefbaiums.supabase.co';
static const String stripePublishableKey = 'pk_test_...';
```

Cambiar a (ver sección 3.6 para cómo compilar):
```dart
// ✅ CORRECTO — se inyecta al compilar
static const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
static const String stripePublishableKey =
    String.fromEnvironment('STRIPE_PK', defaultValue: '');
```

> **Nota:** La `supabase_anon_key` en la app es normal tenerla — está diseñada para ser pública. Lo que NUNCA debe estar en la app es la `service_role_key` y la `stripe_secret_key`.

### Restringir la API key de Google Maps

En [console.cloud.google.com](https://console.cloud.google.com):
- APIs & Services → Credentials → tu API key
- Application restrictions: **Android apps** → agregar tu fingerprint del APK
- API restrictions: solo Maps SDK for Android, Directions API

### Webhook de Stripe con firma

Al configurar el webhook en Stripe Dashboard, Stripe te da un `webhook_secret` (`whsec_...`). Usarlo para verificar que los eventos vienen realmente de Stripe (ver código en sección 5.5).

---

## 6.3 Protección básica que ya tienes sin hacer nada

| Ataque | Por qué no te afecta |
|---|---|
| SQL Injection | Supabase usa queries parametrizadas automáticamente |
| Acceso sin login | JWT requerido para toda la API |
| Manipular el monto de pago | Edge Function verifica contra DB |
| Escuchar el tráfico (MITM) | HTTPS obligatorio en Supabase y Vercel |

---

# 7. Operación y Soporte

## 7.1 Monitoreo básico que necesitas

Para V1.0 local no necesitas un sistema de monitoreo complejo. Esto es suficiente:

### Uptime Kuma (gratis, fácil de instalar)

Si tienes un servidor, instalar Uptime Kuma te avisa por Telegram si algo cae:

```bash
docker run -d \
  --name uptime-kuma \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  louislam/uptime-kuma:1
```

Agregar estos monitores:
- `https://mmjzyqvjdwhzefbaiums.supabase.co` — Supabase
- `https://tudominio.com` — tu app web
- `https://status.stripe.com` — Stripe

Alerta por Telegram en menos de 60 segundos si algo falla.

### Alternativamente: BetterStack (sin servidor)
[betterstack.com](https://betterstack.com) — plan gratuito monitorea hasta 10 sitios cada 3 minutos. Sin instalar nada.

---

## 7.2 Sentry para errores en la app

Cuando la app truena en el celular de un usuario, Sentry te avisa con el stack trace exacto.

```bash
flutter pub add sentry_flutter
```

```dart
// main.dart
await SentryFlutter.init(
  (options) {
    options.dsn = 'https://....@sentry.io/...';
    options.tracesSampleRate = 0.2; // 20% de sesiones con trazas
  },
  appRunner: () => runApp(const MyApp()),
);
```

Plan gratuito: 5,000 errores/mes. Suficiente para V1.0.

---

## 7.3 Cómo manejar un pedido que se atora

Cuando un pedido se queda en un estado intermedio (por ejemplo, el repartidor acepta pero luego ya no responde):

1. El admin entra al Panel de Administrador
2. Va a la pestaña "Pedidos"
3. Busca el pedido atascado
4. Usa los botones de acción para avanzar o cancelar el pedido manualmente
5. El cliente recibe notificación automática

Esta funcionalidad ya está implementada en el panel admin.

---

## 7.4 Soporte al cliente

Para V1.0 local, lo más práctico:

| Canal | Herramienta | Para quién |
|---|---|---|
| WhatsApp Business | Número dedicado de Fercadi | Clientes con problemas |
| WhatsApp directo | Número del admin | Dueños de restaurantes |
| Llamada | Número local | Repartidores en campo |

No necesitas sistema de tickets todavía. Un grupo de WhatsApp por tipo de usuario (clientes, restaurantes, repartidores) funciona perfectamente en esta etapa.

---

## 7.5 Qué revisar cada día

Crear un hábito diario de 10 minutos:

- [ ] Abrir Supabase → Table Editor → orders → ver pedidos del día
- [ ] Revisar si hay pedidos en estado `pending` de más de 30 minutos (señal de problema)
- [ ] Revisar Sentry si hay errores nuevos
- [ ] Ver Stripe Dashboard: ¿hubo pagos fallidos?
- [ ] Revisar el grupo de WhatsApp de repartidores

---

# 8. Roadmap V1.0

## 8.1 Semanas 1–2: Preparación técnica

```
Semana 1:
  □ Implementar RLS en Supabase (sección 4.2)
  □ Agregar opción de pago en efectivo
  □ Pasar Stripe a modo live
  □ Compilar APK release firmado
  □ Registrar dominio propio
  □ Configurar dominio en Vercel y Supabase

Semana 2:
  □ Configurar Supabase Pro (backups automáticos)
  □ Configurar webhook de Stripe
  □ Agregar email de confirmación de pedido (Resend)
  □ Subir a calificación de pedidos (1–5 estrellas)
  □ Prueba completa de flujo end-to-end con pago real
```

---

## 8.2 Semanas 3–4: Onboarding de operadores

```
Semana 3–4:
  □ Reunirse con 3–5 restaurantes de Maravatío
  □ Registrar cada restaurante en la app
  □ El dueño de cada restaurante sube su menú con fotos
  □ Reclutar y registrar 5–8 repartidores
  □ Hacer pedidos de prueba con los repartidores (end-to-end real)
  □ Definir horarios de operación
  □ Definir zonas de cobertura por repartidor
```

---

## 8.3 Semana 5–6: Beta cerrada

```
Beta cerrada (50–100 personas de confianza):
  □ Invitar a familia, amigos y conocidos a probar
  □ Hacer al menos 20 pedidos reales pagados
  □ Recolectar feedback: ¿qué confunde? ¿qué no funciona?
  □ Arreglar lo que salga
  □ Validar que los repartidores entienden el panel
  □ Validar que los dueños entienden su panel
```

---

## 8.4 Semana 7: Lanzamiento público en Maravatío

```
Lanzamiento:
  □ Publicar APK (Play Store o enlace directo de descarga)
  □ Publicar en redes sociales: Instagram, Facebook de Maravatío
  □ Grupos de WhatsApp locales
  □ Promoción de lanzamiento: primer pedido con descuento
  □ Monitoreo activo el primer día
```

---

## 8.5 Después del lanzamiento: V1.1

Una vez que el sistema esté estable y con pedidos reales diarios, agregar:

| Feature | Por qué | Cuándo |
|---|---|---|
| Calificaciones de repartidor | Saber quién está entregando bien | Mes 2 |
| Notificación cuando el restaurante acepta el pedido | Feedback más rápido al cliente | Mes 2 |
| Historial mejorado (repetir pedido) | Comodidad para clientes frecuentes | Mes 2 |
| Estadísticas para el dueño (ventas del mes) | Valor para el restaurante | Mes 3 |
| Segunda zona de cobertura | Si la demanda lo pide | Mes 3–4 |
| App iOS | Si hay demanda de usuarios iPhone | Mes 4+ |

---

# 9. Costos Reales del Proyecto

## 9.1 Costo mensual real para V1.0 en Maravatío

| Servicio | Plan | Costo/mes |
|---|---|---|
| **Supabase** | Pro | $25 USD (~$500 MXN) |
| **Vercel** | Hobby (gratuito) | $0 |
| **Firebase FCM** | Spark (gratuito) | $0 |
| **Google Maps** | Primeros $200 USD gratis/mes | $0 (por ahora) |
| **Stripe** | Sin cuota fija — 3.6% + $3 MXN por transacción | Variable |
| **Resend** (email) | Free: 100 emails/día | $0 |
| **Sentry** | Free: 5K errores/mes | $0 |
| **Dominio** | .com.mx / .com | ~$10 USD/año ≈ $1 USD/mes |
| **TOTAL fijo** | | **~$26 USD/mes (~$520 MXN)** |

---

## 9.2 Costo de Stripe por pedido

| Ticket promedio | Comisión Stripe | Lo que queda para Fercadi |
|---|---|---|
| $80 MXN | $2.88 + $3 = $5.88 MXN | $6.12 MXN (15% = $12 - $5.88) |
| $150 MXN | $5.40 + $3 = $8.40 MXN | $14.10 MXN (15% = $22.5 - $8.40) |
| $250 MXN | $9.00 + $3 = $12 MXN | $25.50 MXN (15% = $37.5 - $12) |

> Por eso el pago en efectivo es importante — sin Stripe, Fercadi se queda con el 15% completo.

---

## 9.3 Proyección de ingresos V1.0

Escenario conservador para los primeros 3 meses:

| Mes | Pedidos/día | Pedidos/mes | Ticket prom. | Comisión 15% | Costo infra | Ganancia neta |
|---|---|---|---|---|---|---|
| Mes 1 | 5 | 150 | $120 MXN | $2,700 MXN | $520 MXN | $2,180 MXN |
| Mes 2 | 15 | 450 | $130 MXN | $8,775 MXN | $520 MXN | $8,255 MXN |
| Mes 3 | 30 | 900 | $140 MXN | $18,900 MXN | $520 MXN | $18,380 MXN |

> A 30 pedidos/día el negocio ya es rentable cubriendo costos operativos básicos.

---

## 9.4 Cuándo necesitarás gastar más

| Situación | Acción | Costo adicional |
|---|---|---|
| > 500 pedidos/mes | Seguir en Supabase Pro | Sin cambio |
| > 2,000 pedidos/mes | Considerar Supabase Team | +$374 USD/mes |
| > 1,000 fotos subidas | Revisar Storage de Supabase | Incluido en Pro |
| > 50,000 calls/mes a Google Maps | Pagar Maps | ~$2 USD por cada 1,000 |
| App en iOS | Apple Developer Account | $99 USD/año |

---

# 10. Checklist Antes de Lanzar

Marcar cada item antes de abrir la app al público:

## Técnico

- [ ] RLS habilitado y probado en todas las tablas de Supabase
- [ ] APK release firmado compilado (no el debug)
- [ ] `useMock = false` en supabase_service.dart
- [ ] Stripe en modo **live** (no test)
- [ ] Stripe secret key actualizada en Edge Function (modo live)
- [ ] Webhook de Stripe configurado con firma verificada
- [ ] Dominio propio conectado en Vercel
- [ ] Google OAuth actualizado al dominio propio en Supabase y Google Cloud
- [ ] Google Maps API key restringida al APK firmado
- [ ] Subir a Supabase Pro (backups automáticos)
- [ ] Un pedido completo end-to-end probado con pago real en modo live
- [ ] Un pedido completo end-to-end probado con pago en efectivo
- [ ] Notificaciones push probadas (cliente recibe cuando repartidor acepta)
- [ ] Email de confirmación de pedido funcionando

## Datos y Contenido

- [ ] Al menos 3 restaurantes reales registrados con menú completo y fotos
- [ ] Al menos 5 repartidores registrados y con la app instalada
- [ ] Datos de prueba eliminados de la base de datos
- [ ] Logo y nombre final de la app (no placeholder)
- [ ] Versión de app correcta en pubspec.yaml (ej: 1.0.0+1)

## Operativo

- [ ] WhatsApp Business de Fercadi creado y publicado
- [ ] Horario de operación definido (ej: 10am–10pm)
- [ ] Acuerdos con restaurantes documentados (comisión, pagos)
- [ ] Repartidores entrenados: saben usar el panel
- [ ] Dueños entrenados: saben subir fotos y gestionar pedidos
- [ ] Plan de soporte definido: ¿quién responde si algo falla?

## Legal (mínimo para operar)

- [ ] Términos de Uso básicos publicados en la app
- [ ] Política de Privacidad publicada (requerida por Google Play)
- [ ] Política de reembolsos definida (¿qué pasa si el pedido llega mal?)

---

# 11. Qué hacer primero

En orden estricto de prioridad. No avanzar al siguiente hasta terminar el anterior.

```
ESTA SEMANA (antes de cualquier otra cosa):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Implementar RLS en Supabase (copiar el SQL de la sección 4.2)
   → Sin esto los datos de tus futuros clientes están expuestos

2. Agregar pago en efectivo al checkout
   → La mitad de tu mercado no tiene tarjeta

3. Compilar APK release firmado
   → El debug no sirve para usuarios reales

SIGUIENTE SEMANA:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
4. Pasar Stripe a modo live y actualizar claves
   → Los pagos de prueba no transfieren dinero real

5. Registrar dominio y configurar en Vercel + Supabase
   → Profesionalismo básico para restaurantes

6. Supabase Pro (backups automáticos)
   → Si pierdes la base de datos sin backup, pierdes todo

ANTES DE LANZAR AL PÚBLICO:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
7. Onboarding de 3 restaurantes reales con menú y fotos
8. Onboarding de 5 repartidores reales
9. Beta cerrada con 30–50 personas
10. Lanzamiento con promoción en redes sociales locales
```

---

*Documento actualizado: 2026-06-12. Enfocado en V1.0 local — Maravatío, Michoacán.*
*Cuando el proyecto supere 1,000 pedidos/mes, revisar arquitectura de escalabilidad.*
