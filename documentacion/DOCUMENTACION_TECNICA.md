# Documentación Técnica — GOGO Food (Grupo Fercadi)

> App de delivery de comida para Maravatío, Michoacán.  
> Desarrollada con Flutter + Supabase + Stripe.

---

## 1. Arquitectura General del Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENTES                                │
│   Navegador Web (Vercel)  │  App Android  │  App iOS (futuro)  │
└──────────────┬────────────┴───────┬────────┴────────────────────┘
               │                   │
               ▼                   ▼
        ┌─────────────────────────────┐
        │      Flutter (Dart 3)       │
        │  go_router  │  provider     │
        │  flutter_stripe │ geolocator│
        └──────────────┬──────────────┘
                       │
                       ▼
        ┌─────────────────────────────┐
        │          Supabase           │
        │  PostgreSQL  │  Auth        │
        │  Storage     │  Realtime    │
        │  Edge Functions             │
        └──────────────┬──────────────┘
                       │
                       ▼
        ┌─────────────────────────────┐
        │      Servicios externos     │
        │  Stripe (pagos)             │
        │  FCM (notificaciones push)  │
        │  Sentry (monitoreo errores) │
        └─────────────────────────────┘
```

---

## 2. Stack Tecnológico

| Tecnología | Versión | Uso |
|---|---|---|
| Flutter | 3.x (Dart 3.11.5) | Framework principal — una sola base de código para web, Android e iOS |
| Supabase | Latest | Base de datos PostgreSQL en la nube, autenticación, storage de imágenes y comunicación en tiempo real |
| go_router | ^14.0.0 | Navegación declarativa con rutas nombradas y protección de acceso por rol |
| provider | ^6.1.2 | Estado global del carrito de compras y datos de la app |
| flutter_stripe | Latest | Procesamiento de pagos con tarjeta de crédito/débito |
| google_maps_flutter | Latest | Mapa interactivo para selección de dirección (solo móvil) |
| geolocator | Latest | Acceso al GPS del dispositivo para detectar ubicación del usuario |
| shared_preferences | Latest | Persistencia de sesión en disco local (rol y usuario actual) |
| Sentry | Latest | Monitoreo de errores en producción con capturas de pantalla |
| Vercel | Latest | Hosting del build web con CDN global y SSL automático |

---

## 3. Estructura de Carpetas

```
lib/
├── core/
│   └── constants.dart          # URLs de Supabase, Stripe, colores de la app
│
├── models/
│   ├── restaurant.dart         # Modelo de restaurante
│   ├── category.dart           # Categoría de productos
│   ├── product.dart            # Producto con precio, imágenes y promos
│   ├── cart_item.dart          # Ítem del carrito con cantidad
│   └── restaurant_banner.dart  # Banner promocional dinámico
│
├── providers/
│   ├── cart_provider.dart      # Estado global del carrito (Provider)
│   ├── app_data_provider.dart  # Likes de restaurantes en tiempo real
│   └── theme_provider.dart     # Modo oscuro/claro
│
├── services/
│   ├── supabase_service.dart   # Toda la lógica de acceso a datos (CRUD)
│   ├── auth_service.dart       # Login, registro, logout por rol
│   ├── notification_service.dart # Notificaciones push (FCM)
│   ├── location_service.dart   # GPS y validación de zona de cobertura
│   ├── geocoding_service.dart  # Convertir coordenadas a dirección texto
│   ├── fcm_service.dart        # Envío de notificaciones al repartidor/dueño
│   └── order_history_service.dart # Historial de pedidos local
│
├── screens/
│   ├── splash_screen.dart          # Pantalla de carga — decide ruta inicial por rol
│   ├── login_screen.dart           # Login de cliente (email/contraseña o social)
│   ├── restaurants_screen.dart     # Pantalla principal cliente — lista restaurantes + carrito
│   ├── cart_screen.dart            # Vista del carrito con resumen de pedido
│   ├── checkout_screen.dart        # Formulario de pago con Stripe
│   ├── tracking_screen.dart        # Rastreo en tiempo real del repartidor
│   ├── dueno_login_screen.dart     # Login exclusivo para dueños de restaurante
│   ├── dueno_screen.dart           # Panel naranja del dueño — pedidos, productos, banners
│   ├── repartidor_login_screen.dart# Login para repartidores
│   ├── repartidor_screen.dart      # Pantalla del repartidor con pedidos activos
│   ├── admin_login_screen.dart     # Login del administrador Fercadi
│   ├── admin_screen.dart           # Panel oscuro admin — todos los datos del sistema
│   ├── registro_restaurante_screen.dart # Formulario de alta de restaurante
│   ├── registro_repartidor_screen.dart  # Formulario de alta de repartidor
│   ├── map_picker_screen.dart      # Selector de dirección con mapa (solo móvil)
│   ├── menu_screen.dart            # Menú expandido de un restaurante
│   ├── product_detail_screen.dart  # Detalle de producto individual
│   ├── profile_screen.dart         # Perfil del usuario cliente
│   ├── order_history_screen.dart   # Historial de pedidos del cliente
│   └── rating_dialog.dart          # Diálogo para calificar un pedido
│
├── router.dart   # Rutas nombradas y guardias de autenticación por rol
├── main.dart     # Punto de entrada — inicializa Supabase, Stripe, Sentry
└── main_admin.dart # Punto de entrada alternativo para la APK de administrador
```

---

## 4. Roles y Flujo de Navegación

La app tiene 4 roles. El rol se guarda en `user_metadata.role` de Supabase Auth y también en SharedPreferences para persistencia offline.

```
Usuario abre la app
        │
        ▼
  splash_screen.dart
  (espera initialSession de Supabase)
        │
        ├── Sin sesión ──────────────────► login_screen.dart
        │
        ├── rol = "cliente" ─────────────► /restaurants
        │                                  Lista restaurantes, carrito, checkout
        │
        ├── rol = "dueno" ───────────────► /dueno
        │                                  Panel naranja: pedidos, productos, banners
        │
        ├── rol = "repartidor" ──────────► /repartidor
        │                                  Pedidos activos (solo móvil)
        │                                  En web: pantalla "usa la app móvil"
        │
        └── rol = "admin" ───────────────► /admin
                                           Panel oscuro: todo el sistema
```

---

## 5. Base de Datos (Supabase PostgreSQL)

### Tablas principales

| Tabla | Descripción | Campos clave |
|---|---|---|
| `restaurants` | Restaurantes registrados | `id (text)`, `name`, `address`, `image_url`, `owner_id` |
| `categories` | Categorías de productos por restaurante | `id`, `restaurant_id`, `name`, `sort_order` |
| `products` | Productos del menú | `id (text)`, `category_id`, `name`, `description`, `price`, `image_url`, `is_available` |
| `product_images` | Imágenes adicionales de un producto | `product_id`, `image_url`, `sort_order` |
| `orders` | Pedidos realizados | `id`, `restaurant_id`, `customer_id`, `status`, `total`, `created_at` |
| `order_items` | Ítems dentro de un pedido | `order_id`, `product_id`, `quantity`, `price` |
| `product_likes` | Likes de usuarios a restaurantes | `user_id`, `restaurant_id` |
| `restaurant_banners` | Banners promocionales del dueño | `id`, `restaurant_id`, `image_url`, `title`, `discount_percent`, `product_id` |

### Seguridad (Row Level Security)

Todas las tablas tienen RLS activo. Los permisos se evalúan con:

```sql
auth.jwt() -> 'user_metadata' ->> 'role'
```

- **Cliente**: solo puede leer restaurantes/productos, crear pedidos propios
- **Dueño**: CRUD solo en restaurantes que le pertenecen (por `owner_id`)
- **Repartidor**: solo puede leer y actualizar pedidos asignados a él
- **Admin**: acceso completo a todas las tablas

---

## 6. Flujo Completo de un Pedido

```
1. Cliente ve restaurantes (/restaurants)
        │
2. Agrega productos al carrito (CartProvider)
        │
3. Va a checkout — introduce dirección
        │
4. Paga con Stripe (flutter_stripe)
   → Supabase Edge Function crea el PaymentIntent
        │
5. Se crea el pedido en tabla `orders` con status = "pending"
        │
6. Dueño recibe notificación push (FCM)
   → Acepta pedido → status = "accepted"
        │
7. Se asigna repartidor → status = "delivering"
   → Repartidor transmite GPS cada 5 seg (tabla tracking)
        │
8. Cliente ve tracking en tiempo real (/tracking)
        │
9. Pedido entregado → status = "delivered"
   → Cliente califica el pedido (rating_dialog.dart)
```

---

## 7. Documentación del Despliegue

### 7.1 Web (Vercel)

**Requisitos previos:**
- Node.js instalado (`node -v`)
- Vercel CLI autenticado (`npx vercel login`)
- Flutter en el PATH (`flutter --version`)

**Comandos de despliegue:**

```powershell
# 1. Compilar
flutter build web --release --pwa-strategy=none

# 2. Copiar configuración de Vercel al build
Copy-Item vercel.json build/web/vercel.json -Force

# 3. Hacer deploy
cd build/web
npx vercel --prod --archive=tgz
```

**URL de producción:** `https://web-iota-brown-32.vercel.app`

**El archivo `vercel.json` configura:**
- Que todas las rutas (`/*`) sirvan `index.html` (necesario para go_router en web)
- Headers de cache para assets estáticos

### 7.2 Android APKs

Se generan dos APKs independientes:

```powershell
.\build_apks.ps1
# Genera: build\GOGOFood.apk  → App del cliente
#         build\GOGOAdmin.apk → App del administrador (usa main_admin.dart)
```

| APK | Entry point | Bundle ID |
|---|---|---|
| GOGOFood.apk | `lib/main.dart` | `com.fercadi.app` |
| GOGOAdmin.apk | `lib/main_admin.dart` | `com.fercadi.admin` |

### 7.3 Variables de entorno / Credenciales

Todas las credenciales están en `lib/core/constants.dart`:

| Constante | Dónde obtenerla |
|---|---|
| `supabaseUrl` | Supabase Dashboard → Settings → API |
| `supabaseAnonKey` | Supabase Dashboard → Settings → API |
| `supabaseServiceRoleKey` | Supabase Dashboard → Settings → API (solo para scripts de admin) |
| `stripePublishableKey` | dashboard.stripe.com → Developers → API Keys |
| `sentryDsn` | sentry.io → tu proyecto → Settings → Client Keys |

> ⚠️ La clave secreta de Stripe (`sk_...`) NUNCA va en el código — va como variable de entorno en la Supabase Edge Function.

### 7.4 Modo Mock vs Producción

En `lib/services/supabase_service.dart`:

```dart
static const bool useMock = false;  // true = datos de prueba, false = Supabase real
```

Con `useMock = true` la app funciona sin internet con datos hardcodeados para desarrollo.

---

## 8. Posibles Problemáticas

### P1 — CORS en imágenes (Web)
**Síntoma:** Las imágenes de Unsplash se muestran como ícono roto en el navegador.  
**Causa:** Unsplash hace un redirect HTTP cuando la URL no tiene los parámetros correctos. Flutter Web no puede seguir redirects cross-origin.  
**Solución implementada:** Todas las URLs de Unsplash se procesan en `_repairUrl()` en `supabase_service.dart` para agregar `?w=400&h=300&fit=crop&q=80` antes de usarlas.

### P2 — Google Maps no funciona en Web
**Síntoma:** `MapPickerScreen` crash o pantalla en blanco en navegador.  
**Causa:** `google_maps_flutter` no tiene soporte web oficial.  
**Solución implementada:** El botón de mapa se oculta con `kIsWeb`. En web se usa campo de texto libre para dirección.

### P3 — Notificaciones push no llegan en Web
**Síntoma:** El dueño/repartidor no recibe notificaciones en el navegador.  
**Causa:** `flutter_local_notifications` no soporta web. FCM web requiere configuración adicional de Service Worker.  
**Estado:** Notificaciones solo funcionan en APK Android.

### P4 — Sesión expirada silenciosa
**Síntoma:** El usuario ve pantalla en blanco o error 401 después de mucho tiempo inactivo.  
**Causa:** El token JWT de Supabase expira (por defecto a la 1 hora).  
**Solución:** Supabase auto-refresh está activo. Si el refresh falla, `splash_screen.dart` redirige al login.

### P5 — RLS bloquea operaciones del dueño
**Síntoma:** El dueño no puede guardar productos o el menú aparece vacío.  
**Causa:** Si el `owner_id` del restaurante no coincide con el `auth.uid()` del usuario, RLS rechaza la operación.  
**Diagnóstico:** Revisar en Supabase → Table Editor → `restaurants` → columna `owner_id`.

### P6 — GPS fuera de zona
**Síntoma:** La app muestra "Fuera de zona de servicio" aunque el usuario esté en Maravatío.  
**Causa:** El radio de cobertura es de 30 km desde `19.8969° N, 100.4447° W`. Si el GPS del dispositivo tiene mala precisión puede reportar ubicación incorrecta.  
**Solución:** En `useMock = true` el GPS siempre simula estar dentro del radio.

---

## 9. Cuellos de Botella (Bottlenecks)

### B1 — Carga inicial del menú (el más crítico)
**Dónde:** `restaurants_screen.dart` → `_loadMenu()`  
**Problema:** Al abrir un restaurante, se hacen 3 peticiones en paralelo (categorías, productos, banners). Con muchas categorías (10+) y productos (50+), esto puede tardar 2-4 segundos en conexiones lentas.  
**Impacto:** Alta — el usuario ve un spinner largo.  
**Mejora posible:** Paginar productos o cargar solo la primera categoría inicialmente.

### B2 — Tracking del repartidor por polling
**Dónde:** `tracking_screen.dart`  
**Problema:** La pantalla de seguimiento hace polling a Supabase cada 5 segundos para obtener la posición GPS del repartidor. Con muchos pedidos activos simultáneos, esto genera muchas peticiones.  
**Impacto:** Medio — aumenta el uso de la cuota de Supabase.  
**Mejora posible:** Usar Supabase Realtime (WebSockets) en lugar de polling.

### B3 — Carga de imágenes de productos
**Dónde:** `restaurants_screen.dart` → `_productImage()`  
**Problema:** Cada tile de producto carga una imagen desde CDN externo (Unsplash/Pexels). Si el restaurante tiene 30 productos, se hacen 30 peticiones de imagen simultáneas.  
**Impacto:** Medio — consumo de datos alto en primera visita.  
**Mejora posible:** Implementar `cached_network_image` para cachear imágenes localmente entre sesiones.

### B4 — Panel admin carga todos los pedidos
**Dónde:** `admin_screen.dart` → `_loadOrders()`  
**Problema:** El panel admin trae hasta 200 pedidos del día actual en una sola query. Si hay muchos restaurantes activos, este número puede crecer.  
**Impacto:** Bajo por ahora — puede volverse crítico con escala.  
**Mejora posible:** Paginación server-side o filtro por restaurante desde el inicio.

### B5 — `useMock = false` sin credenciales configuradas
**Dónde:** `main.dart`  
**Problema:** Si alguien clona el repositorio y ejecuta con `useMock = false` sin configurar las credenciales reales en `constants.dart`, toda la app falla silenciosamente.  
**Impacto:** Alto en onboarding de nuevos desarrolladores.  
**Mejora posible:** Variables de entorno (`.env`) en lugar de constantes hardcodeadas.

---

## 10. Diagrama de Comunicación entre Capas

```
UI (screens/)
    │  llama métodos de
    ▼
Services (supabase_service.dart, auth_service.dart)
    │  hace peticiones a
    ▼
Supabase Client (SDK)
    │  conecta con
    ▼
Supabase Cloud (PostgreSQL + Auth + Storage + Realtime)
    │  puede disparar
    ▼
Edge Functions (Stripe webhook, notificaciones FCM)
```

Los **Providers** (`CartProvider`, `AppDataProvider`) son independientes — la UI los escucha directamente con `context.watch<>()` sin pasar por el service layer.

---

*Documentación generada para Grupo Fercadi — GOGO Food App*  
*Versión: Junio 2026*
