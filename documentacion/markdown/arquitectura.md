# Arquitectura del Sistema — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿Qué es GOGO Food?

App de delivery de comida para Maravatío, Michoacán. Permite a los clientes pedir comida desde su teléfono o navegador, a los dueños gestionar su menú y pedidos, y a los repartidores entregar con rastreo GPS en tiempo real.

---

## Stack Tecnológico

| Tecnología | Versión | Para qué |
|---|---|---|
| **Flutter** | Dart 3.11.5 | Framework principal — un solo código para web, Android e iOS |
| **Supabase** | Latest | Base de datos, autenticación, storage de fotos, tiempo real |
| **go_router** | ^14.0.0 | Navegación entre pantallas con rutas nombradas |
| **provider** | ^6.1.2 | Estado global del carrito de compras |
| **flutter_stripe** | Latest | Pagos con tarjeta de crédito/débito |
| **google_maps_flutter** | Latest | Mapa interactivo para dirección (solo móvil) |
| **flutter_map** | ^6.0.0 | Mapas OpenStreetMap para web (panel de flota) |
| **geolocator** | Latest | GPS del dispositivo |
| **shared_preferences** | Latest | Sesión persistente en disco local |
| **url_launcher** | ^6.3.0 | Abrir URLs externas desde la app |

---

## Diagrama General

```
┌─────────────────────────────────────────────────────────┐
│                    USUARIOS FINALES                      │
│   Navegador Web    │  App Android   │  App iOS (futuro) │
└──────────┬─────────┴───────┬────────┴───────────────────┘
           └─────────────────┘
                    │
       ┌────────────▼────────────┐
       │     FLUTTER (Dart 3)    │
       │  go_router │ provider   │
       │  stripe    │ geolocator │
       └────────────┬────────────┘
                    │
       ┌────────────▼────────────┐
       │       SUPABASE          │
       │  PostgreSQL │ Auth      │
       │  Storage    │ Realtime  │
       │  Edge Functions         │
       └────┬──────────┬─────────┘
            │          │
     ┌──────▼──┐  ┌────▼───────┐
     │ STRIPE  │  │  FCM/Sentry│
     │ (pagos) │  │ (notif/err)│
     └─────────┘  └────────────┘
```

---

## Roles y Pantallas

| Rol | URL de login | Pantalla principal | Dispositivo |
|---|---|---|---|
| **Cliente** | `/login` | `/restaurants` | Web o móvil |
| **Dueño** | `/restaurante` | `/dueno` | Web o móvil |
| **Repartidor** | `/moto` | `/repartidor` | Solo móvil |
| **Jefe de flota** | `/flota-login` | `/flota` | Web |
| **Admin Fercadi** | App GOGOAdmin.apk | `/admin` | App separada |

El rol se guarda en `user_metadata.role` en Supabase Auth y en SharedPreferences para persistencia offline.

---

## Flujo de Navegación (Splash Screen)

```
Usuario abre la app
        │
  splash_screen.dart
        │
        ├── Sin sesión ─────────────► /login
        ├── rol cliente ────────────► /restaurants
        ├── rol jefe_flota ─────────► /flota  (verifica Supabase)
        └── dueno/repartidor ───────► Su propio login separado
```

---

## Base de Datos — Tablas Principales

| Tabla | Para qué |
|---|---|
| `restaurants` | Restaurantes registrados con nombre, foto, dirección y dueño |
| `categories` | Categorías del menú por restaurante (ej. "Tacos", "Bebidas") |
| `products` | Productos con precio, imagen, descripción y disponibilidad |
| `product_images` | Imágenes adicionales por producto |
| `orders` | Pedidos con estado, total, cliente, repartidor y dirección |
| `order_items` | Productos dentro de cada pedido |
| `product_likes` | Likes de usuarios a restaurantes |
| `restaurant_banners` | Banners promocionales del panel del dueño |
| `flota_members` | Relación jefe de flota ↔ sus repartidores |
| `rider_locations` | Ubicación GPS en tiempo real de cada repartidor |

### Seguridad (Row Level Security)

Todas las tablas tienen RLS activo. Los permisos se validan con:

```sql
auth.jwt() -> 'user_metadata' ->> 'role'
```

| Rol | Permisos |
|---|---|
| `cliente` | Leer restaurantes/productos, crear y leer sus propios pedidos |
| `dueno` | CRUD en sus propios restaurantes (validado por `owner_id`) |
| `repartidor` | Leer y actualizar pedidos asignados a él, escribir su ubicación |
| `jefe_flota` | Leer sus riders en `flota_members` y sus ubicaciones |
| `admin` | Acceso completo sin restricciones |

---

## Flujo Completo de un Pedido

```
1. Cliente agrega productos al carrito (CartProvider en memoria)
2. Checkout: introduce dirección y método de pago
3. Si paga con tarjeta → Stripe procesa el cobro
4. Se crea el pedido en `orders` con status = "pending"
5. Dueño recibe notificación push (FCM) → acepta → status = "accepted"
6. Repartidor recibe → status = "delivering" → transmite GPS cada 10 seg
7. Cliente ve el repartidor en el mapa (/tracking) en tiempo real
8. Entrega → status = "delivered" → cliente califica el pedido
```

---

## Panel de Flota (Sistema para Empresarios con Repartidores)

Para empresarios que tienen motos propias y repartidores a su cargo.

- **Jefe de flota** entra por `/flota-login` y ve su panel
- Ve: ubicación en mapa de cada rider, pedido activo, entregas del día, ganancias
- Los repartidores transmiten GPS continuamente mientras tienen la app abierta
- El panel actualiza cada 10 segundos automáticamente
- Mapa embebido con OpenStreetMap (funciona en web, sin costo)

---

## Estructura de Carpetas

```
lib/
├── core/constants.dart          ← Credenciales (Supabase, Stripe, colores)
├── models/                      ← Estructuras de datos
├── providers/                   ← Estado global (carrito, likes, tema)
├── services/                    ← Comunicación con Supabase y APIs externas
├── screens/                     ← Cada pantalla de la app
├── router.dart                  ← Todas las rutas de navegación
├── main.dart                    ← Punto de entrada de la app
└── main_admin.dart              ← Punto de entrada de la app admin
```

---

## Colores de la App

```dart
// App cliente y admin
bgColor      = Color(0xFF121212)   // Negro
surfaceColor = Color(0xFF1E1E1E)
primaryColor = Color(0xFFE91E8C)   // Rosa/magenta

// Panel dueño y registro de restaurante
primaryColor = Color(0xFFFF5722)   // Naranja — NO cambiar

// Panel de flota
bgColor      = Color(0xFF0F1117)   // Oscuro casi negro
accentColor  = Color(0xFF4F8EF7)   // Azul
```

---

*Grupo Fercadi — GOGO Food | Junio 2026*
