# GOGO Food — Documentación Completa
### Grupo Fercadi | Maravatío, Michoacán
### Versión: Junio 2026

---

> **¿Qué es GOGO Food?**  
> Aplicación de delivery de comida a domicilio para la ciudad de Maravatío, Michoacán. Permite a los clientes pedir comida desde su teléfono o navegador web, a los dueños de restaurante gestionar su menú y pedidos, y a los repartidores recibir y entregar pedidos con rastreo GPS en tiempo real. Incluye además un panel de administración para Fercadi y un panel de flota para empresarios con repartidores propios.

---

## Índice

1. [Arquitectura General del Sistema](#1-arquitectura-general-del-sistema)
2. [Stack Tecnológico](#2-stack-tecnológico)
3. [Estructura de Carpetas del Proyecto](#3-estructura-de-carpetas-del-proyecto)
4. [Roles y Flujo de Navegación](#4-roles-y-flujo-de-navegación)
5. [Base de Datos — Supabase PostgreSQL](#5-base-de-datos--supabase-postgresql)
6. [Flujo Completo de un Pedido](#6-flujo-completo-de-un-pedido)
7. [Sistema de Panel de Flota](#7-sistema-de-panel-de-flota)
8. [Despliegue Web en Vercel](#8-despliegue-web-en-vercel)
9. [Despliegue Android — APKs](#9-despliegue-android--apks)
10. [Sistema de Pagos con Stripe](#10-sistema-de-pagos-con-stripe)
11. [Actualizaciones y Versiones](#11-actualizaciones-y-versiones)
12. [Publicación en Tiendas](#12-publicación-en-tiendas)
13. [Costos de Cada Servicio](#13-costos-de-cada-servicio)
14. [Problemas Conocidos y Soluciones](#14-problemas-conocidos-y-soluciones)
15. [Cuellos de Botella](#15-cuellos-de-botella)
16. [Checklist para Producción Real](#16-checklist-para-producción-real)

---

## 1. Arquitectura General del Sistema

La aplicación está dividida en tres capas principales: el cliente (Flutter), el servidor (Supabase) y los servicios externos (Stripe, FCM).

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          USUARIOS FINALES                                │
│                                                                          │
│   Navegador Web          App Android           App iOS (futuro)          │
│   (cualquier PC/cel)     (GOGOFood.apk)        (requiere Mac + $99/año)  │
└──────────┬───────────────────────┬────────────────────────┬─────────────┘
           │                       │                        │
           └───────────────────────▼────────────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │      FLUTTER (Dart 3.11.5)   │
                    │                              │
                    │  • go_router (navegación)    │
                    │  • provider (estado carrito) │
                    │  • flutter_stripe (pagos)    │
                    │  • geolocator (GPS)          │
                    │  • flutter_map (mapas web)   │
                    │  • google_maps (mapas móvil) │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │         SUPABASE CLOUD        │
                    │                               │
                    │  • PostgreSQL (base de datos) │
                    │  • Auth (login y roles)       │
                    │  • Storage (fotos)            │
                    │  • Realtime (websockets)      │
                    │  • Edge Functions (servidor)  │
                    └──────────────┬────────────────┘
                                   │
           ┌───────────────────────┼──────────────────────┐
           │                       │                       │
  ┌────────▼────────┐   ┌──────────▼──────────┐  ┌───────▼──────────┐
  │     STRIPE      │   │  Firebase FCM        │  │     SENTRY       │
  │  (cobros reales)│   │  (notificaciones     │  │  (errores en     │
  │                 │   │   push — GRATIS)     │  │   producción)    │
  └─────────────────┘   └─────────────────────┘  └──────────────────┘
```

### ¿Cómo se conectan las piezas?

- **Flutter** es la app que el usuario ve y toca. Corre en el navegador (web) o en el teléfono (Android/iOS). Toda la interfaz gráfica está aquí.
- **Supabase** es el servidor. Guarda todos los datos (restaurantes, pedidos, usuarios, fotos). Flutter se comunica con Supabase a través del SDK oficial.
- **Stripe** procesa los pagos con tarjeta. Flutter nunca toca dinero directamente — le pide a una Edge Function de Supabase que cree el cobro, y Supabase le habla a Stripe con la clave secreta.
- **FCM (Firebase Cloud Messaging)** envía las notificaciones push al repartidor y al dueño cuando llega un pedido nuevo.

---

## 2. Stack Tecnológico

| Tecnología | Versión | Para qué se usa |
|---|---|---|
| **Flutter** | 3.x (Dart 3.11.5) | Framework principal. Un solo código para web, Android e iOS |
| **Supabase** | Latest | Base de datos PostgreSQL en la nube, autenticación, storage de fotos y comunicación en tiempo real |
| **go_router** | ^14.0.0 | Sistema de navegación entre pantallas con rutas nombradas (`/restaurants`, `/dueno`, `/flota`, etc.) |
| **provider** | ^6.1.2 | Estado global del carrito de compras. Permite que cualquier pantalla vea el carrito sin pasarlo manualmente |
| **flutter_stripe** | Latest | Procesamiento de pagos con tarjeta. Abre el formulario de pago nativo de Stripe |
| **google_maps_flutter** | Latest | Mapa interactivo para que el cliente elija su dirección. **Solo funciona en móvil**, no en web |
| **flutter_map** | ^6.0.0 | Mapas con OpenStreetMap. Funciona en **web y móvil**. Se usa en el panel de flota |
| **latlong2** | ^0.9.0 | Librería de coordenadas geográficas. Necesaria para `flutter_map` |
| **geolocator** | Latest | Accede al GPS del dispositivo para detectar dónde está el usuario o el repartidor |
| **shared_preferences** | Latest | Guarda la sesión del usuario en el disco del teléfono/navegador para que no tenga que volver a entrar |
| **url_launcher** | ^6.3.0 | Abre URLs externas desde la app (ej. abrir Google Maps desde el panel de flota) |
| **Vercel** | Latest | Hosting del build web. CDN global, SSL automático, URL pública |

### ¿Por qué Flutter y no React Native o nativo?

Flutter permite escribir **una sola vez** la lógica de la app y compilarla para web, Android e iOS. Esto reduce el tiempo de desarrollo a la tercera parte. El único inconveniente es que algunos paquetes (como `google_maps_flutter`) no tienen soporte web.

---

## 3. Estructura de Carpetas del Proyecto

```
landing_test/                         ← Raíz del proyecto
│
├── lib/                              ← TODO el código Flutter está aquí
│   │
│   ├── core/
│   │   └── constants.dart            ← Credenciales: URL Supabase, clave Stripe, colores de la app
│   │
│   ├── models/                       ← Estructuras de datos (lo que vive en la BD)
│   │   ├── restaurant.dart           ← Modelo de restaurante (nombre, imagen, dirección, dueño)
│   │   ├── category.dart             ← Categoría de productos (ej. "Tacos", "Bebidas")
│   │   ├── product.dart              ← Producto con precio, imágenes, disponibilidad y promos
│   │   ├── cart_item.dart            ← Ítem del carrito: qué producto y cuántos
│   │   └── restaurant_banner.dart    ← Banner promocional dinámico (imagen + descuento)
│   │
│   ├── providers/                    ← Estado global que cualquier pantalla puede escuchar
│   │   ├── cart_provider.dart        ← Carrito de compras (agregar, quitar, limpiar)
│   │   ├── app_data_provider.dart    ← Likes de restaurantes en tiempo real
│   │   └── theme_provider.dart       ← Modo oscuro / modo claro
│   │
│   ├── services/                     ← Toda la comunicación con Supabase y servicios externos
│   │   ├── supabase_service.dart     ← CRUD completo: restaurantes, productos, pedidos, flota
│   │   ├── auth_service.dart         ← Login, registro, logout por rol, sesión persistente
│   │   ├── notification_service.dart ← Envío y recepción de notificaciones push (FCM)
│   │   ├── location_service.dart     ← GPS y validación de zona de cobertura (30 km de Maravatío)
│   │   ├── geocoding_service.dart    ← Convertir coordenadas GPS a dirección en texto
│   │   ├── fcm_service.dart          ← Envío de notificaciones al repartidor y dueño
│   │   └── order_history_service.dart ← Historial de pedidos guardado localmente
│   │
│   ├── screens/                      ← Cada archivo es una pantalla de la app
│   │   ├── splash_screen.dart            ← Pantalla de carga (logo 1.5 seg) → decide adónde ir según el rol
│   │   ├── login_screen.dart             ← Login de cliente (email + contraseña)
│   │   ├── restaurants_screen.dart       ← Pantalla principal: lista de restaurantes, carrito, búsqueda
│   │   ├── menu_screen.dart              ← Menú expandido de un restaurante específico
│   │   ├── product_detail_screen.dart    ← Detalle de un producto: fotos, descripción, agregar al carrito
│   │   ├── cart_screen.dart              ← Vista del carrito con productos y totales
│   │   ├── checkout_screen.dart          ← Dirección de entrega, método de pago, confirmar pedido
│   │   ├── tracking_screen.dart          ← Rastreo GPS del repartidor en tiempo real
│   │   ├── order_history_screen.dart     ← Historial de pedidos anteriores del cliente
│   │   ├── profile_screen.dart           ← Perfil del cliente: nombre, foto, dirección guardada
│   │   ├── rating_dialog.dart            ← Diálogo para calificar un pedido entregado
│   │   ├── dueno_login_screen.dart       ← Login exclusivo para dueños (tema naranja)
│   │   ├── dueno_screen.dart             ← Panel naranja del dueño: pedidos, productos, banners, config
│   │   ├── repartidor_login_screen.dart  ← Login para repartidores
│   │   ├── repartidor_screen.dart        ← Pantalla del repartidor: pedidos activos + GPS en vivo
│   │   ├── admin_screen.dart             ← Panel oscuro admin: todos los restaurantes, pedidos, usuarios
│   │   ├── flota_login_screen.dart       ← Login exclusivo para jefes de flota (tema oscuro azul)
│   │   ├── flota_screen.dart             ← Panel del jefe de flota: riders, mapa, ganancias del día
│   │   ├── registro_restaurante_screen.dart ← Formulario de alta de nuevo restaurante
│   │   ├── registro_repartidor_screen.dart  ← Formulario de alta de nuevo repartidor
│   │   └── map_picker_screen.dart        ← Selector de dirección con mapa (solo móvil)
│   │
│   ├── router.dart     ← Define TODAS las rutas de la app (qué URL lleva a qué pantalla)
│   ├── main.dart       ← Punto de entrada de la app cliente y web
│   └── main_admin.dart ← Punto de entrada alternativo para la APK del administrador Fercadi
│
├── documentacion/
│   ├── DOCUMENTACION_TECNICA.md
│   ├── DOC_DESPLIEGUE_Y_PAGOS.md
│   ├── DOC_ACTUALIZACIONES_Y_TIENDAS.md
│   └── markdown/
│       └── GOGO_FOOD_DOCUMENTACION_COMPLETA.md   ← Este archivo
│
├── android/           ← Configuración nativa Android
├── ios/               ← Configuración nativa iOS
├── web/               ← Configuración del build web (index.html, iconos, manifest)
├── assets/            ← Imágenes y fuentes locales (logo SVG, etc.)
├── build/             ← Resultado de flutter build (no se sube a git)
├── vercel.json        ← Configuración del servidor web en Vercel
├── pubspec.yaml       ← Lista de dependencias (como package.json en Node.js)
└── build_apks.ps1     ← Script de PowerShell para generar las dos APKs
```

---

## 4. Roles y Flujo de Navegación

La app tiene **5 roles**. Cada rol tiene su propia pantalla de inicio y su propio set de permisos en la base de datos.

### Tabla de roles

| Rol | Valor en BD | URL de login | Pantalla principal | Dispositivo |
|---|---|---|---|---|
| **Cliente** | `cliente` | `/login` | `/restaurants` | Web o móvil |
| **Dueño de restaurante** | `dueno` | `/restaurante` | `/dueno` | Web o móvil |
| **Repartidor** | `repartidor` | `/moto` | `/repartidor` | Solo móvil (en web muestra aviso) |
| **Administrador Fercadi** | `admin` | App GOGOAdmin.apk | `/admin` | App separada |
| **Jefe de flota** | `jefe_flota` | `/flota-login` | `/flota` | Web (panel de control) |

### ¿Cómo decide la app adónde ir al abrir?

El `splash_screen.dart` es el portero. Siempre se muestra primero (con el logo animado). Luego sigue esta lógica:

```
Usuario abre la app (URL raíz "/")
            │
            ▼
     splash_screen.dart
     Espera initialSession de Supabase (~500ms)
            │
            ├── ¿Hay sesión guardada en SharedPreferences?
            │       │
            │       ├── NO ──────────────────────────────► /login
            │       │                                    (pantalla de login cliente)
            │       │
            │       └── SÍ → ¿Cuál es el rol guardado?
            │                │
            │                ├── "/restaurants" ─────────► /restaurants
            │                │                            (lista de restaurantes)
            │                │
            │                ├── "/dueno" ───────────────► Limpia sesión → /login
            │                │   (los dueños tienen su propio login en /restaurante)
            │                │
            │                ├── "/repartidor" ──────────► Limpia sesión → /login
            │                │   (los repartidores tienen su propio login en /moto)
            │                │
            │                └── "/flota" ───────────────► Verifica sesión Supabase
            │                    o "/admin"                 Si es jefe_flota → /flota
            │                                               Si es admin → /admin
            │                                               Si no coincide → /login
            │
     Jefe de flota entra por /flota-login
     (no interfiere con el flujo de arriba)
```

### ¿Dónde se guarda el rol?

El rol vive en **dos lugares**:
1. **Supabase Auth** → `user_metadata.role` del usuario (fuente de verdad)
2. **SharedPreferences** (disco local del dispositivo) → para saber adónde ir sin esperar a Supabase

```dart
// Así se lee el rol desde Supabase
final role = supabaseSession.user.userMetadata?['role'] as String?;
```

---

## 5. Base de Datos — Supabase PostgreSQL

### Diagrama de tablas

```
restaurants ──────────────┬──────────────────────── orders
     │                    │                            │
     │                    │                            │
   categories          product_likes              order_items
     │                                                 │
   products ──────── product_images               products (FK)
     │
restaurant_banners
     │
   products (FK a product_id)

── Sistema de Flota ──
flota_members
  jefe_id ──── (FK a auth.users)
  rider_id ─── (FK a auth.users)

rider_locations
  rider_id ─── (FK a auth.users)
  lat, lng, is_active, last_seen
```

### Descripción detallada de cada tabla

#### `restaurants` — Restaurantes registrados

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | text (PK) | Identificador único del restaurante |
| `name` | text | Nombre del restaurante |
| `description` | text | Descripción del restaurante |
| `address` | text | Dirección en texto libre |
| `image_url` | text | URL de la imagen de portada |
| `owner_id` | uuid | FK al usuario dueño en `auth.users` |
| `is_active` | boolean | Si aparece en la lista de clientes |
| `created_at` | timestamptz | Fecha de registro |

#### `categories` — Categorías de productos

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid (PK) | Identificador único |
| `restaurant_id` | text | FK a `restaurants.id` |
| `name` | text | Nombre de la categoría (ej. "Tacos", "Bebidas") |
| `sort_order` | int | Orden en que aparece en el menú |

#### `products` — Productos del menú

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | text (PK) | Identificador único del producto |
| `category_id` | uuid | FK a `categories.id` |
| `name` | text | Nombre del producto |
| `description` | text | Descripción corta |
| `price` | numeric | Precio en pesos MXN |
| `image_url` | text | URL de la imagen principal |
| `is_available` | boolean | Si se puede pedir actualmente |
| `promo_label` | text | Etiqueta promocional (ej. "2x1", "Nuevo") |

#### `orders` — Pedidos realizados

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid (PK) | Identificador del pedido |
| `restaurant_id` | text | FK a `restaurants.id` |
| `customer_id` | uuid | FK al cliente en `auth.users` |
| `rider_id` | uuid | FK al repartidor asignado |
| `status` | text | Estado: `pending` → `accepted` → `delivering` → `delivered` |
| `total` | numeric | Total en pesos MXN |
| `delivery_fee` | numeric | Cargo por delivery (ganancia del repartidor) |
| `address` | text | Dirección de entrega |
| `payment_method` | text | `cash`, `card` o `oxxo` |
| `created_at` | timestamptz | Fecha y hora del pedido |

#### `flota_members` — Relación jefe de flota ↔ repartidor

| Columna | Tipo | Descripción |
|---|---|---|
| `jefe_id` | uuid | FK al jefe de flota en `auth.users` |
| `rider_id` | uuid | FK al repartidor en `auth.users` |
| `rider_name` | text | Nombre del repartidor (para mostrar rápido) |
| `rider_email` | text | Correo del repartidor |
| `created_at` | timestamptz | Cuando se vincularon |

> **PK compuesta:** `(jefe_id, rider_id)` — un rider solo puede estar vinculado a un jefe a la vez.

#### `rider_locations` — Ubicación GPS en tiempo real de cada repartidor

| Columna | Tipo | Descripción |
|---|---|---|
| `rider_id` | uuid (PK) | FK al repartidor en `auth.users` |
| `lat` | double precision | Latitud GPS |
| `lng` | double precision | Longitud GPS |
| `is_active` | boolean | Si la app está abierta y transmitiendo |
| `last_seen` | timestamptz | Última vez que se actualizó la ubicación |

> **Online/Offline:** Si `last_seen` tiene menos de 5 minutos de antigüedad, el rider se considera "En línea".

### Seguridad — Row Level Security (RLS)

Todas las tablas tienen RLS activado. Cada operación se valida con el rol del usuario autenticado:

```sql
-- Así se obtiene el rol en las políticas de RLS
auth.jwt() -> 'user_metadata' ->> 'role'
```

| Rol | Qué puede hacer |
|---|---|
| **cliente** | Leer restaurantes, productos y categorías. Crear pedidos propios. Leer sus propios pedidos |
| **dueno** | CRUD completo en sus propios restaurantes (validado por `owner_id = auth.uid()`), productos y banners |
| **repartidor** | Leer pedidos asignados a él. Actualizar estado de pedido. Escribir en `rider_locations` |
| **jefe_flota** | Leer `flota_members` donde es el jefe. Leer `rider_locations` de sus riders. Leer pedidos de sus riders |
| **admin** | Acceso completo a todas las tablas sin restricciones |

---

## 6. Flujo Completo de un Pedido

Este es el ciclo de vida de un pedido desde que el cliente lo hace hasta que llega a su puerta:

```
PASO 1 — Cliente navega
  Cliente abre la app → ve lista de restaurantes → entra a uno → ve el menú
  Agrega productos al carrito (CartProvider en memoria)

PASO 2 — Checkout
  Cliente va al carrito → confirma productos → introduce dirección de entrega
  Elige método de pago: Efectivo / Tarjeta / OXXO

PASO 3 — Pago (si es con tarjeta)
  App llama a Edge Function "create-payment-intent" en Supabase
  → Edge Function llama a Stripe con la clave secreta
  → Stripe devuelve clientSecret
  → App abre PaymentSheet de Stripe
  → Cliente ingresa sus datos de tarjeta
  → Stripe verifica con el banco
  → Banco aprueba → pago confirmado

PASO 4 — Creación del pedido
  App crea registro en tabla `orders` con status = "pending"
  FCM envía notificación push al dueño del restaurante

PASO 5 — Dueño acepta
  Dueño ve el pedido en su panel naranja (/dueno)
  Toca "Aceptar pedido"
  → status = "accepted"
  FCM notifica al repartidor disponible

PASO 6 — Repartidor recoge
  Repartidor ve el pedido en su pantalla (/repartidor)
  Toca "Ir a recoger"
  → status = "delivering"
  App del repartidor comienza a transmitir GPS cada 10 segundos
  → Escribe en tabla `rider_locations` continuamente

PASO 7 — Cliente rastrea
  Cliente puede ver en /tracking la posición del repartidor en tiempo real
  El mapa se actualiza automáticamente al detectar cambios en la BD

PASO 8 — Entrega
  Repartidor entrega el pedido → toca "Entregado"
  → status = "delivered"
  App deja de transmitir GPS
  Cliente recibe opción de calificar el pedido (rating_dialog.dart)
```

---

## 7. Sistema de Panel de Flota

El panel de flota es un **mini-admin para empresarios** que tienen repartidores propios (ej. alguien con 5 motos y 5 repartidores trabajando para él). Les permite ver qué está haciendo cada uno de sus riders en tiempo real.

### Quién ve qué

| Rol | Qué ve |
|---|---|
| **jefe_flota** | Solo sus riders: ubicación en mapa, pedido activo, ganancias del día, estado online/offline |
| **rider_flota** | Sus pedidos normalmente (igual que cualquier repartidor) — NO ve sus propias ganancias |
| **admin Fercadi** | Todos los riders de todas las flotas |

### Cómo funciona técnicamente

#### Transmisión de ubicación del repartidor

El `repartidor_screen.dart` llama a `SupabaseService.broadcastRiderPresence()` **cada vez que el GPS actualiza**, sin importar si tiene un pedido activo o no:

```dart
// En repartidor_screen.dart — dentro del listener del GPS
_gpsSub = Geolocator.getPositionStream(...).listen((pos) {
  setState(() => _myPos = pos);
  // Siempre transmite presencia al jefe de flota
  SupabaseService.broadcastRiderPresence(pos.latitude, pos.longitude);
  // Solo transmite tracking cuando tiene pedido activo
  if (_activeOrder != null) {
    SupabaseService.broadcastLocation(pos.latitude, pos.longitude);
  }
});
```

#### Panel del jefe (flota_screen.dart)

El panel hace polling a Supabase **cada 10 segundos** para actualizar:
- Lista de riders vinculados (`flota_members`)
- Ubicaciones GPS (`rider_locations`)
- Pedidos del día de cada rider (`orders` filtrado por fecha y rider_id)
- Pedido activo de cada rider (`orders` con status `delivering`)

```dart
// Polling automático
_pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadAll());
```

#### Mapa embebido con OpenStreetMap

Cada card de rider tiene un mapa de OpenStreetMap (funciona en web, sin costo):

- Si el rider **no tiene ubicación**: muestra área gris con "Sin ubicación aún"
- Si el rider **tiene ubicación**: muestra mapa con marcador de moto azul
- Botón **"Abrir en Google Maps"**: abre las coordenadas en Google Maps en nueva pestaña

### Rutas del panel de flota

| URL | Pantalla |
|---|---|
| `/flota-login` | Login del jefe de flota (tema oscuro azul) |
| `/flota` | Panel de control del jefe de flota |

### Colores del panel de flota

```dart
_bg      = Color(0xFF0F1117)  // Fondo oscuro casi negro
_surface = Color(0xFF1A1D27)  // Superficie de secciones
_card    = Color(0xFF22263A)  // Cards de riders
_accent  = Color(0xFF4F8EF7)  // Azul para acentos, botones, marcador del mapa
```

### SQL para crear las tablas de flota

```sql
-- Tabla de miembros de flota
CREATE TABLE flota_members (
  jefe_id    uuid,
  rider_id   uuid,
  rider_name  text,
  rider_email text,
  created_at  timestamptz DEFAULT now(),
  PRIMARY KEY (jefe_id, rider_id)
);

-- Tabla de ubicaciones en tiempo real
CREATE TABLE rider_locations (
  rider_id   uuid PRIMARY KEY,
  lat        double precision,
  lng        double precision,
  is_active  boolean DEFAULT false,
  last_seen  timestamptz DEFAULT now()
);

-- RLS: jefe solo ve sus riders
CREATE POLICY "jefe_lee_sus_riders" ON flota_members
  FOR SELECT USING (
    auth.uid() = jefe_id OR
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- RLS: rider actualiza su propia ubicación
CREATE POLICY "rider_actualiza_ubicacion" ON rider_locations
  FOR ALL USING (auth.uid() = rider_id);

-- RLS: jefe lee ubicaciones de sus riders
CREATE POLICY "jefe_lee_ubicaciones" ON rider_locations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM flota_members
      WHERE jefe_id = auth.uid() AND rider_id = rider_locations.rider_id
    ) OR (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );
```

### Cómo agregar un nuevo jefe de flota

```sql
-- 1. En Supabase → Authentication → Users → Add user
--    (o con SQL)
-- 2. Asignarle el rol jefe_flota
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"role": "jefe_flota"}'::jsonb
WHERE email = 'correo_del_jefe@ejemplo.com';

-- 3. Vincular riders al jefe
INSERT INTO flota_members (jefe_id, rider_id, rider_name, rider_email)
VALUES ('uuid-del-jefe', 'uuid-del-rider', 'Nombre del Rider', 'rider@correo.com');
```

---

## 8. Despliegue Web en Vercel

### ¿Qué es Vercel?

Vercel es el servicio que aloja la versión web de la app. Cuando alguien entra a `web-iota-brown-32.vercel.app`, Vercel le sirve los archivos de Flutter compilados a JavaScript.

### URL de producción

```
https://web-iota-brown-32.vercel.app
```

### Proceso completo de deploy

```powershell
# Paso 1 — Compilar Flutter a JavaScript
flutter build web --release --pwa-strategy=none
# Tiempo: ~60 segundos
# Resultado: carpeta build/web/ con todos los archivos

# Paso 2 — Copiar la configuración de rutas de Vercel
# (Sin este paso, Vercel no sabe redirigir /flota, /dueno, etc. a index.html)
Copy-Item vercel.json build/web/vercel.json -Force

# Paso 3 — Subir a producción
cd build/web
npx vercel --prod --archive=tgz
# Tiempo: ~20 segundos
# El flag --archive=tgz comprime todo antes de subir (más rápido)
```

### ¿Qué hace el vercel.json?

```json
{
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }],
  "headers": [
    {
      "source": "/(flutter_service_worker.js|flutter_bootstrap.js)",
      "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
    }
  ]
}
```

- **`rewrites`**: Hace que `/flota`, `/dueno`, `/admin`, etc. todos carguen `index.html`. Flutter maneja la navegación internamente con go_router.
- **`headers`**: Le dice al navegador que no cachee los archivos del Service Worker, para que siempre cargue la versión más nueva.

### Cuándo hacer deploy

Hacer deploy cada vez que se modifique algo en:

- `lib/screens/` — cambios de pantallas o diseño
- `lib/services/` — cambios de lógica de negocio
- `lib/router.dart` — cambios de rutas
- `vercel.json` — cambios de configuración del servidor

**No** es necesario hacer deploy cuando:
- Se cambian datos en Supabase (restaurantes, productos, precios) — la app los lee en tiempo real
- Se cambian variables de entorno en Supabase Edge Functions

### Rollback (volver a una versión anterior)

Si algo sale mal después de un deploy:

1. Ir a [vercel.com](https://vercel.com) → tu proyecto → **Deployments**
2. Encontrar el deploy anterior que funcionaba
3. Clic en **"Promote to Production"**
4. En 30 segundos la versión anterior está activa de nuevo

---

## 9. Despliegue Android — APKs

La app tiene **dos APKs independientes**:

| Archivo | Para quién | Entry point |
|---|---|---|
| `GOGOFood.apk` | Clientes y repartidores | `lib/main.dart` |
| `GOGOAdmin.apk` | Administrador Fercadi | `lib/main_admin.dart` |

### Generar ambas APKs

```powershell
.\build_apks.ps1
# Genera:
#   build\GOGOFood.apk    (~35 MB)
#   build\GOGOAdmin.apk   (~35 MB)
```

### Instalar en teléfonos (sideload)

1. Transferir el `.apk` al teléfono (WhatsApp, Google Drive, cable USB)
2. Abrir el archivo en el teléfono
3. Si Android bloquea la instalación: **Configuración → Seguridad → Permitir fuentes desconocidas**

### Bundle IDs

| App | Bundle ID |
|---|---|
| GOGOFood (cliente) | `com.fercadi.app` |
| GOGOAdmin | `com.fercadi.admin` |

> El Bundle ID es el identificador único de la app en Google Play y App Store. Cambiar el Bundle ID crea una app completamente nueva en las tiendas.

---

## 10. Sistema de Pagos con Stripe

### Los 3 métodos de pago

#### 10.1 Efectivo — El más simple

```
Cliente elige "Efectivo" → Se crea el pedido → Repartidor cobra en mano
```

No hay integración técnica. El riesgo es que no hay verificación digital del pago.

#### 10.2 Tarjeta — Stripe

```
Cliente elige "Tarjeta"
    │
    ▼
checkout_screen.dart llama a _payWithStripe()
    │
    ▼
Supabase Edge Function "create-payment-intent"
    ├── Recibe: monto en centavos (MXN), moneda "mxn"
    ├── Llama a Stripe API con la clave secreta (sk_...)
    └── Devuelve: clientSecret (token de un solo uso)
    │
    ▼
App recibe el clientSecret
    │
    ▼
flutter_stripe abre el PaymentSheet (pantalla nativa de pago de Stripe)
    ├── Cliente ingresa: número de tarjeta, fecha de expiración, CVV
    ├── Stripe valida en tiempo real (Luhn, BIN lookup)
    └── Stripe envía al banco del cliente para autorización
    │
    ▼
Banco aprueba → Stripe confirma el pago → PaymentSheet cierra con éxito
    │
    ▼
App crea el pedido en Supabase con status = "pending"
```

**Archivos involucrados:**

| Archivo | Qué hace |
|---|---|
| `lib/screens/checkout_screen.dart` | Interfaz de checkout, llama a Stripe |
| `lib/core/constants.dart` | Guarda la clave pública de Stripe (`pk_test_...`) |
| Supabase Edge Function `create-payment-intent` | Crea el cobro en Stripe (clave secreta) |

**Las claves de Stripe:**

| Clave | Prefijo | Dónde va | Para qué |
|---|---|---|---|
| Publishable key | `pk_test_...` / `pk_live_...` | `constants.dart` en el código | Inicializa el SDK en el cliente |
| Secret key | `sk_test_...` / `sk_live_...` | Variable de entorno en Supabase Edge Function | Crea cobros reales. **NUNCA en el código del cliente** |

> ⚠️ Actualmente está en modo **prueba** (`pk_test_` / `sk_test_`). Las tarjetas de prueba de Stripe no cobran dinero real. Para producción, cambiar a `pk_live_` / `sk_live_`.

#### 10.3 OXXO Pay

```
Cliente elige "OXXO" → Stripe genera referencia de pago → Cliente va al OXXO
→ OXXO notifica a Stripe (1-3 días) → Stripe manda webhook → Pedido se marca como pagado
```

> **Estado actual:** La opción existe en la UI pero el webhook de OXXO no está completamente configurado en Supabase.

### Tarjetas de prueba (modo test)

Para probar pagos sin dinero real:

| Tarjeta | CVV | Fecha | Resultado |
|---|---|---|---|
| `4242 4242 4242 4242` | Cualquier 3 dígitos | Cualquier fecha futura | Pago aprobado |
| `4000 0000 0000 0002` | Cualquier | Cualquier | Pago rechazado |
| `4000 0025 0000 3155` | Cualquier | Cualquier | Requiere autenticación 3D Secure |

### Comisiones de Stripe (producción)

| Tipo de tarjeta | Comisión |
|---|---|
| Nacional (México) | **3.6% + $3 MXN** por transacción |
| Internacional | **4.6% + $3 MXN** por transacción |

**Ejemplo:** Pedido de $150 MXN con tarjeta nacional:
```
$150.00 × 3.6% = $5.40
              + $3.00 (fijo)
= $8.40 que se queda Stripe
= $141.60 que recibe Fercadi
```

---

## 11. Actualizaciones y Versiones

### Numeración de versiones

El número de versión está en `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        │ │ │  └── Build number: entero que DEBE incrementar en cada subida a tienda
#        │ │ └────── Patch: correcciones de bugs menores
#        │ └──────── Minor: nueva funcionalidad sin romper compatibilidad
#        └────────── Major: cambio grande o rediseño completo
```

**Ejemplos:**

| Cambio | Antes | Después |
|---|---|---|
| Corrección de imagen rota | `1.0.0+1` | `1.0.1+2` |
| Se agrega pantalla de flota | `1.0.1+2` | `1.1.0+3` |
| Rediseño completo de la app | `1.4.2+10` | `2.0.0+11` |

### ¿Qué pasa con los datos al actualizar?

| Dato | Dónde vive | ¿Se afecta al actualizar la app? |
|---|---|---|
| Pedidos, restaurantes, menús | Supabase (nube) | ❌ Nunca. Están en la nube |
| Fotos de productos | Supabase Storage (nube) | ❌ Nunca |
| Sesión del usuario | SharedPreferences (teléfono) | ❌ El usuario sigue logueado |
| Carrito actual | Memoria RAM de la app | ⚠️ Se pierde si la app se cierra (es normal) |

**La app en el teléfono es solo la pantalla. Todos los datos reales viven en Supabase.**

### Diferencia entre actualizar app y actualizar datos

| Tipo de cambio | Ejemplo | ¿Requiere compilar? | ¿Requiere revisión de tienda? |
|---|---|---|---|
| **Código** | Nueva pantalla, fix de bug, nuevo color | ✅ Sí | ✅ Sí |
| **Datos** | Nuevo restaurante, cambio de precio, nueva foto | ❌ No | ❌ No |
| **Menú** | Agregar producto, quitar categoría | ❌ No (el dueño lo hace solo) | ❌ No |
| **Configuración BD** | Nueva tabla, nuevo índice | ❌ No (se hace en Supabase) | ❌ No |

---

## 12. Publicación en Tiendas

### 12.1 Google Play Store

#### Primera vez (configuración única)

1. **Crear cuenta de desarrollador:** [play.google.com/console](https://play.google.com/console) — **$25 USD pago único**

2. **Crear el keystore** (firma digital — se hace UNA SOLA VEZ, GUARDAR SIEMPRE):
   ```powershell
   keytool -genkey -v -keystore gogofood.keystore -alias gogofood -keyalg RSA -keysize 2048 -validity 10000
   ```
   > ⚠️ Si se pierde el keystore, **nunca más** se puede actualizar la app en Play Store. Guardar en Drive, USB y correo.

3. **Primera publicación:**
   - Crear la app en Play Console
   - Llenar la ficha: nombre, descripción, capturas de pantalla
   - Agregar política de privacidad (obligatoria)
   - Subir el APK o AAB firmado
   - Esperar revisión de Google: 1-7 días hábiles

#### Para cada actualización

```powershell
# 1. Incrementar versión en pubspec.yaml
# version: 1.0.0+1  →  version: 1.0.1+2

# 2. Generar APK firmada
.\build_apks.ps1

# 3. En play.google.com/console:
# → Tu app → Producción → Crear nueva versión → Subir APK → Publicar
```

#### Tiempos de revisión Google

| Etapa | Tiempo |
|---|---|
| Compilar APK | 2-5 minutos |
| Subir a Play Console | 2-5 minutos |
| Revisión de Google | 1-3 días (puede ser más la primera vez) |
| Disponible para usuarios | Inmediato después de aprobación |

### 12.2 Apple App Store (futuro)

> **Requisito:** Una computadora Mac con Xcode. No se puede compilar para iOS desde Windows.

#### Costo
- **$99 USD/año** — Cuenta Apple Developer (se renueva cada año)

#### Pasos (cuando se implemente)

1. Crear cuenta en [developer.apple.com](https://developer.apple.com)
2. Registrar Bundle ID: `com.fercadi.gogofood`
3. Crear certificados de distribución en el portal de Apple Developer
4. Compilar en Mac: `flutter build ipa --release`
5. Subir con Xcode o Transporter a App Store Connect
6. Esperar revisión: 1-7 días (Apple es más estricta que Google)

---

## 13. Costos de Cada Servicio

### Resumen de costos actuales vs producción

| Servicio | En desarrollo (ahora) | Al lanzar | Costo mensual |
|---|---|---|---|
| **Stripe** | Gratis (modo prueba) | Activo automáticamente | 3.6% + $3 MXN por transacción con tarjeta |
| **Supabase** | Gratis | Pagar Pro desde día 1 | **$25 USD/mes** (~$500 MXN) |
| **Vercel** | Gratis | Gratis (puede quedarse así) | $0 (o $20 USD si se quiere dominio propio) |
| **Google Maps** | Gratis | Gratis (< 28,500 cargas/mes) | $0 |
| **Google Play** | N/A | **$25 USD pago único** | $0 |
| **Apple Store** | N/A | **$99 USD/año** (si se hace iOS) | $8.25 USD/mes |
| **FCM (notificaciones)** | Gratis | Gratis | $0 siempre |
| **Sentry (errores)** | No activo | Gratis es suficiente al inicio | $0 (o $26 USD/mes si se necesita más) |

### Costo mínimo para lanzar

```
Sin iOS:   $50 USD = $25 Supabase Pro primer mes + $25 Google Play
Con iOS:  $149 USD = $50 anterior + $99 Apple Developer
```

### Costo mensual fijo después de lanzar

```
Mínimo: $25 USD/mes (Supabase Pro)
Normal: $25-45 USD/mes (Supabase + Vercel si se quiere dominio)
```

### Detalle de Supabase — ¿Por qué pagar el Pro?

El plan gratuito tiene un problema crítico: **la base de datos se "duerme" después de 7 días sin actividad**. Cuando alguien intenta pedir comida, la primera petición tarda 30 segundos en despertar la BD. Eso es inaceptable para una app de delivery.

| Plan | Costo | BD duerme | Storage | Edge Functions |
|---|---|---|---|---|
| Free (actual) | $0 | ✅ Sí (7 días inactivo) | 5 GB | 50,000/mes |
| **Pro (recomendado)** | **$25 USD/mes** | ❌ No | 100 GB | 2,000,000/mes |

---

## 14. Problemas Conocidos y Soluciones

### P1 — CORS en imágenes desde la web
**Síntoma:** Las imágenes de productos aparecen como ícono roto en el navegador Chrome/Edge.  
**Causa:** Unsplash hace un redirect HTTP al cargar imágenes sin los parámetros correctos. El navegador bloquea estos redirects por política de seguridad cross-origin.  
**Solución implementada:** Todas las URLs de Unsplash pasan por `_repairUrl()` en `supabase_service.dart` que les agrega `?w=400&h=300&fit=crop&q=80` antes de usarlas.

---

### P2 — Google Maps no funciona en web
**Síntoma:** `MapPickerScreen` muestra pantalla en blanco o crash en el navegador.  
**Causa:** El paquete `google_maps_flutter` no tiene soporte para Flutter Web oficial.  
**Solución implementada:** El selector de mapa (`MapPickerScreen`) se desactiva con `kIsWeb`. En web, se muestra un campo de texto libre para la dirección.  
**Afecta:** Solo la selección de dirección al registrar restaurante y al hacer checkout. El panel de flota usa `flutter_map` (OpenStreetMap) que sí funciona en web.

---

### P3 — Notificaciones push no llegan en web
**Síntoma:** El dueño o repartidor no recibe notificaciones en el navegador cuando llega un pedido.  
**Causa:** `flutter_local_notifications` no tiene soporte web. FCM en web requiere configuración adicional de Service Worker.  
**Estado:** Las notificaciones **solo funcionan en Android**. Para web se necesitaría implementar Web Push con Service Worker.

---

### P4 — Sesión expirada silenciosa
**Síntoma:** El usuario ve pantalla en blanco o error 401 después de mucho tiempo inactivo.  
**Causa:** El token JWT de Supabase expira (por defecto cada hora).  
**Solución implementada:** Supabase auto-refresh está activo. Si el refresh falla, `splash_screen.dart` detecta la sesión inválida y redirige al login correspondiente.

---

### P5 — Panel de dueño no muestra sus productos
**Síntoma:** El dueño entra a su panel pero ve la lista de productos vacía o recibe error.  
**Causa:** El `owner_id` del restaurante en la tabla `restaurants` no coincide con el `auth.uid()` del usuario autenticado. RLS rechaza la operación silenciosamente.  
**Diagnóstico:** Supabase → Table Editor → `restaurants` → verificar que `owner_id` = UUID del dueño.

---

### P6 — GPS fuera de zona de servicio
**Síntoma:** La app muestra "Fuera de zona de servicio" aunque el usuario esté en Maravatío.  
**Causa:** El radio de cobertura configurado es de 30 km desde las coordenadas `19.8969° N, 100.4447° W`. Si el GPS del dispositivo tiene poca precisión, puede reportar una ubicación incorrecta.  
**Solución para desarrollo:** Activar `useMock = true` en `supabase_service.dart` — en modo mock el GPS siempre simula estar dentro del radio.

---

### P7 — El repartidor ve "usa la app móvil" en web
**Síntoma:** El repartidor intenta entrar a su panel desde el navegador y ve un mensaje diciendo que use la app.  
**Causa:** Diseño intencional. El panel del repartidor necesita GPS activo y mapas en tiempo real, características que funcionan mejor en la app nativa.  
**Estado:** El panel web del repartidor es deliberadamente limitado. Solo los paneles de cliente, dueño, admin y flota son completamente funcionales en web.

---

### P8 — Sesiones del panel de flota interfieren con la app cliente
**Síntoma:** El jefe de flota entra a su panel y la app cliente (para pedir comida) lo manda al panel de flota.  
**Causa:** La sesión de Supabase es compartida en el mismo navegador.  
**Solución implementada:** El panel de flota usa sesión independiente — no escribe en SharedPreferences. El splash screen de la app cliente no verifica la sesión de Supabase para el rol jefe_flota.  
**Solución práctica:** El jefe de flota debe usar el panel desde `web-iota-brown-32.vercel.app/flota-login`. Si quiere pedir comida como cliente, debe usar otro navegador o modo incógnito.

---

## 15. Cuellos de Botella

Los cuellos de botella son puntos de la app donde el rendimiento puede ser lento o donde el sistema puede saturarse.

### B1 — Carga inicial del menú de un restaurante ⚠️ CRÍTICO

**Dónde:** `restaurants_screen.dart` → `_loadMenu(restaurantId)`  
**Qué pasa:** Al abrir un restaurante se hacen 3 peticiones en paralelo:
- Traer todas las categorías del restaurante
- Traer todos los productos de cada categoría (una query por categoría)
- Traer los banners promocionales

Con un restaurante de 8 categorías y 60 productos en conexión 4G lenta, esto puede tardar **3-5 segundos**.  

**Impacto:** Alto — el usuario ve un spinner largo y puede pensar que la app está rota.  
**Mejora posible:** Cargar solo la primera categoría al abrir, y cargar las demás conforme el usuario hace scroll.

---

### B2 — Polling cada 10 segundos en el panel de flota

**Dónde:** `flota_screen.dart` → `_loadAll()` con `Timer.periodic`  
**Qué pasa:** El panel del jefe hace 3-5 peticiones a Supabase cada 10 segundos (riders, ubicaciones, pedidos del día, pedido activo de cada rider).  
**Impacto:** Medio — con 10 riders y polling cada 10 segundos, son ~6 peticiones/minuto/jefe. Con muchos jefes, esto escala.  
**Mejora posible:** Usar Supabase Realtime (WebSockets) para recibir actualizaciones solo cuando cambia algo, en vez de preguntar constantemente.

---

### B3 — Carga de imágenes de productos

**Dónde:** `restaurants_screen.dart` → tiles de productos  
**Qué pasa:** Cada tile de producto carga una imagen desde CDN externo (Unsplash o Pexels). Con 30 productos visibles, son 30 peticiones de imagen simultáneas al abrir el menú.  
**Impacto:** Medio — consumo de datos elevado en la primera visita. Las imágenes no se cachean entre sesiones.  
**Mejora posible:** Implementar `cached_network_image` para guardar las imágenes localmente y no volver a descargarlas.

---

### B4 — Panel admin carga hasta 200 pedidos

**Dónde:** `admin_screen.dart` → `_loadOrders()`  
**Qué pasa:** Al abrir el panel admin, se traen los últimos 200 pedidos del día actual en una sola query.  
**Impacto:** Bajo por ahora — puede volverse lento con muchos restaurantes activos.  
**Mejora posible:** Paginación server-side o filtrar por restaurante desde el principio.

---

### B5 — Cold start de Edge Functions de Supabase

**Dónde:** `checkout_screen.dart` → llamada a Edge Function `create-payment-intent`  
**Qué pasa:** Las Edge Functions de Supabase tienen un "cold start" de 1-3 segundos si no han sido invocadas recientemente. El usuario toca "Pagar" y no pasa nada por 2-3 segundos.  
**Impacto:** Alto — genera ansiedad en el momento más crítico del flujo (el pago).  
**Mejora posible:** Hacer una llamada "calentadora" a la Edge Function unos segundos antes de que el usuario llegue al botón de pago.

---

### B6 — Build web tarda ~60 segundos

**Dónde:** Proceso de compilación en PowerShell  
**Qué pasa:** `flutter build web` compila todo desde cero cada vez. No hay caché entre compilaciones.  
**Impacto:** Un hotfix urgente tarda 2-3 minutos en llegar a producción.  
**Mejora posible:** Usar GitHub Actions para automatizar el build en servidores más rápidos (con caché de paquetes).

---

## 16. Checklist para Producción Real

Antes de abrir la app al público en Maravatío, verificar todo lo siguiente:

### Pagos y dinero
- [ ] Cambiar `pk_test_...` → `pk_live_...` en `lib/core/constants.dart`
- [ ] Cambiar `sk_test_...` → `sk_live_...` en Supabase → Edge Functions → Secrets
- [ ] Verificar cuenta bancaria registrada en Stripe Dashboard (CLABE 18 dígitos)
- [ ] Configurar webhook de Stripe apuntando a una Edge Function de Supabase
- [ ] Hacer prueba de pago completa con tarjeta real (pedido de $1 MXN)

### Infraestructura
- [ ] Cambiar plan de Supabase a **Pro** ($25 USD/mes)
- [ ] Configurar dominio propio en Vercel (ej. `gogofood.mx` o `pedidosfercadi.mx`)
- [ ] Verificar que el SSL del dominio está activo (Vercel lo hace automáticamente)
- [ ] Activar monitoreo de errores en Sentry (obtener DSN real y ponerlo en `constants.dart`)

### Android
- [ ] Cambiar Bundle ID de `com.example.landing_test` a `com.fercadi.gogofood`
- [ ] Crear keystore de firma: `keytool -genkey -v -keystore gogofood.keystore ...`
- [ ] Guardar el keystore en al menos 3 lugares seguros (Drive, USB, correo)
- [ ] Crear cuenta Google Play ($25 USD pago único)
- [ ] Subir app a prueba interna primero, probar, luego publicar en producción
- [ ] Agregar política de privacidad (requerida por Google Play)

### Contenido
- [ ] Icono de la app 1024×1024 píxeles sin transparencia
- [ ] Screenshots para Play Store (mínimo 2, máximo 8 por tipo de dispositivo)
- [ ] Descripción de la app en español para la tienda
- [ ] Verificar que todos los restaurantes tienen fotos y menú completo

### Seguridad
- [ ] Revisar que las claves de Supabase en `constants.dart` son las de producción
- [ ] Verificar que el `anonKey` de Supabase tiene los permisos correctos en RLS
- [ ] Confirmar que el `useMock = false` en `supabase_service.dart`

### Prueba final antes de lanzar
- [ ] Crear pedido completo como cliente (desde seleccionar restaurante hasta entregado)
- [ ] Probar login de dueño, aceptar pedido desde panel naranja
- [ ] Probar que el repartidor recibe el pedido en la app Android
- [ ] Probar que el GPS del repartidor aparece en el tracking del cliente
- [ ] Probar que el jefe de flota ve al repartidor en su panel
- [ ] Probar que una tarjeta de prueba de Stripe funciona correctamente

---

## Geolocalización

- **Centro de Maravatío:** `19.8969° N, 100.4447° W`
- **Radio de cobertura:** 30 km
- **En modo mock (`useMock = true`):** El GPS siempre simula estar dentro del radio
- **En producción:** Si el usuario está a más de 30 km del centro, la app muestra "Fuera de zona de servicio"

---

## Contacto y Repositorio

- **Repositorio:** GitHub (privado) — Grupo Fercadi
- **URL web:** `https://web-iota-brown-32.vercel.app`
- **BD:** Supabase proyecto Fercadi
- **Pagos:** Stripe Dashboard (pendiente conectar a cuenta bancaria real)

---

*Documentación completa GOGO Food — Grupo Fercadi*  
*Maravatío, Michoacán, México*  
*Versión: Junio 2026*
