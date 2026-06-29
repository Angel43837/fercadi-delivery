# Manual de Frontend — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿Qué es el "frontend" de GOGO Food?

El frontend es todo lo que el usuario ve y toca — las pantallas, los botones, el carrito, los menús. En GOGO Food el frontend está hecho con **Flutter**, un framework que permite escribir el código una sola vez y correr en Android, iOS y navegador web.

---

## 1. Estructura de Carpetas del Frontend

```
lib/
├── core/
│   └── constants.dart          ← Colores, URLs, claves API
├── models/                     ← Estructuras de datos
│   ├── product.dart
│   ├── restaurant.dart
│   ├── cart_item.dart
│   ├── restaurant_banner.dart
│   └── ...
├── providers/                  ← Estado global
│   ├── cart_provider.dart      ← Carrito de compras
│   └── app_data_provider.dart  ← Likes de restaurantes
├── screens/                    ← Una pantalla = un archivo
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── restaurants_screen.dart
│   ├── checkout_screen.dart
│   ├── dueno_screen.dart
│   ├── admin_screen.dart
│   ├── repartidor_screen.dart
│   ├── flota_screen.dart
│   ├── flota_login_screen.dart
│   └── tracking_screen.dart
├── services/
│   ├── supabase_service.dart   ← Toda comunicación con Supabase
│   ├── auth_service.dart       ← Sesión y SharedPreferences
│   └── notification_service.dart
├── router.dart                 ← Todas las rutas de navegación
├── main.dart                   ← Punto de entrada cliente/web
└── main_admin.dart             ← Punto de entrada admin
```

---

## 2. Sistema de Colores y Temas

Cada panel tiene su propio esquema de colores. Están definidos en `lib/core/constants.dart`:

### App del Cliente y Admin

```dart
static const Color bgColor      = Color(0xFF121212);   // Fondo negro
static const Color surfaceColor = Color(0xFF1E1E1E);   // Superficie oscura
static const Color primaryColor = Color(0xFFE91E8C);   // Rosa magenta — botones principales
static const Color textColor    = Color(0xFFFFFFFF);   // Texto blanco
static const Color textSecondary= Color(0xFF9E9E9E);   // Texto secundario gris
```

### Panel del Dueño (tema naranja)

```dart
static const Color duenoBg      = Color(0xFFFFF3E0);   // Fondo cálido crema
static const Color duenoPrimary = Color(0xFFFF5722);   // Naranja — NO cambiar
static const Color duenoSurface = Color(0xFFFFFFFF);   // Tarjetas blancas
```

### Panel de Flota (tema azul oscuro)

```dart
static const Color flotaBg      = Color(0xFF0F1117);   // Casi negro
static const Color flotaSurface = Color(0xFF1A1D27);
static const Color flotaCard    = Color(0xFF22263A);
static const Color flotaAccent  = Color(0xFF4F8EF7);   // Azul eléctrico
```

---

## 3. Pantallas y lo que hacen

### `splash_screen.dart` — Pantalla de carga

- Muestra el logo de GOGO Food por 1.5 segundos
- Lee la sesión de SharedPreferences
- Redirige a la pantalla correcta según el rol

### `login_screen.dart` — Login del cliente

- Email + contraseña con Supabase Auth
- Botón de registro → `registro_screen.dart`
- Tema oscuro con rosa magenta

### `restaurants_screen.dart` — App del cliente

La pantalla principal del cliente. Contiene:
- Barra superior con búsqueda y carrito
- Filtros de categorías (carrusel horizontal)
- Lista de restaurantes (cards con foto, nombre, likes)
- Botón de carrito flotante con contador
- Swipe para dar like al restaurante

Al tocar un restaurante → `restaurant_detail_screen.dart` con el menú.

### `checkout_screen.dart` — Pago

- Dirección de entrega
- Método de pago: Efectivo / Tarjeta
- Resumen del pedido
- Si elige tarjeta → abre Stripe PaymentSheet
- Al confirmar → crea el pedido en Supabase

### `tracking_screen.dart` — Rastreo del pedido

- Mapa con la posición del repartidor en tiempo real
- Se actualiza automáticamente vía Supabase Realtime
- Solo funciona en móvil (google_maps_flutter no soporta web)

### `dueno_screen.dart` — Panel del dueño

Panel naranja para gestionar el restaurante propio:
- Lista de pedidos del día con estado
- CRUD de productos (agregar, editar precio, disponibilidad)
- CRUD de categorías
- Gestión de banners promocionales
- Configuración del restaurante (nombre, foto, dirección)
- Subida de imágenes a Supabase Storage

### `admin_screen.dart` — Panel del administrador Fercadi

Panel oscuro para el administrador:
- Lista de todos los restaurantes
- Pedidos totales del día
- Usuarios registrados
- Botón de eliminar restaurante (con cascada)

### `repartidor_screen.dart` — Panel del repartidor

- Muestra el pedido activo asignado al repartidor
- Botón GPS para iniciar el rastreo
- Transmite ubicación GPS a Supabase cada vez que se mueve +5 metros
- También transmite a `rider_locations` para el panel de flota
- En web: muestra mensaje "Usa la app móvil"

### `flota_login_screen.dart` — Login del jefe de flota

- Pantalla oscura con acento azul
- Solo acepta cuentas con rol `jefe_flota`
- NO guarda en SharedPreferences para no interferir con el cliente
- Si ya hay sesión activa → redirige automáticamente al panel

### `flota_screen.dart` — Panel del jefe de flota

- Lista de los repartidores bajo su cargo
- Mapa OpenStreetMap embebido por repartidor (sin costo, funciona en web)
- Ícono de moto en el mapa en la posición GPS actual
- Indicador online/offline (verde/rojo) — online = activo en los últimos 5 min
- Entregas del día y ganancias por repartidor
- Si el repartidor tiene pedido activo → muestra el pedido
- Botón "Abrir en Google Maps" para ver en el mapa externo
- Actualización automática cada 10 segundos

### Pantallas de registro

| Archivo | Para quién |
|---|---|
| `registro_restaurante_screen.dart` | Nuevo dueño registra su restaurante |
| `registro_repartidor_screen.dart` | Nuevo repartidor se registra |
| `dueno_login_screen.dart` | Login exclusivo del dueño (tema naranja) |
| `repartidor_login_screen.dart` | Login exclusivo del repartidor |

---

## 4. Cómo Funciona la Navegación

Se usa `go_router` — todas las rutas están en `lib/router.dart`.

### Rutas definidas

```dart
GoRoute(path: '/',              → SplashScreen)
GoRoute(path: '/login',         → LoginScreen)
GoRoute(path: '/restaurants',   → RestaurantsScreen)
GoRoute(path: '/restaurante',   → DuenoLoginScreen)
GoRoute(path: '/dueno',         → DuenoScreen)
GoRoute(path: '/moto',          → RepartidorLoginScreen)
GoRoute(path: '/repartidor',    → RepartidorScreen)
GoRoute(path: '/flota-login',   → FlotaLoginScreen)
GoRoute(path: '/flota',         → FlotaScreen)
GoRoute(path: '/admin',         → AdminScreen)
GoRoute(path: '/checkout',      → CheckoutScreen)
GoRoute(path: '/tracking',      → TrackingScreen)
```

### Cómo navegar desde el código

```dart
// Ir a una pantalla (reemplaza la actual)
context.go('/restaurants');

// Ir a una pantalla pasando datos
context.push('/tracking', extra: {'orderId': order.id});

// Volver a la pantalla anterior
context.pop();
```

---

## 5. El Carrito de Compras (CartProvider)

El carrito vive en memoria mientras la app está abierta. Se implementa con `provider` en `lib/providers/cart_provider.dart`.

### Cómo se agrega un producto al carrito

```dart
// En cualquier pantalla, sin necesidad de pasar callbacks
context.read<CartProvider>().addItem(product, restaurantId);
```

### Cómo se muestra el contador en el ícono del carrito

```dart
// Se reconstruye automáticamente cuando el carrito cambia
final itemCount = context.watch<CartProvider>().itemCount;
```

### Estructura de un ítem del carrito

```dart
class CartItem {
  final Product product;
  final String restaurantId;
  int quantity;

  double get subtotal => product.price * quantity;
}
```

### Limpiar el carrito (después de hacer un pedido)

```dart
context.read<CartProvider>().clear();
```

---

## 6. Subir Imágenes desde el Panel del Dueño

El dueño puede subir fotos de sus productos directamente desde el panel.

### Flujo

```dart
// 1. El usuario elige una foto de su galería
final picker = ImagePicker();
final image = await picker.pickImage(source: ImageSource.gallery);

// 2. Se sube a Supabase Storage
final bytes = await image.readAsBytes();
final path = 'products/$productId/${DateTime.now().millisecondsSinceEpoch}.jpg';
await Supabase.instance.client.storage
    .from('product-images')
    .uploadBinary(path, bytes);

// 3. Se obtiene la URL pública
final url = Supabase.instance.client.storage
    .from('product-images').getPublicUrl(path);

// 4. Se guarda la URL en la tabla products
await Supabase.instance.client.from('products')
    .update({'image_url': url}).eq('id', productId);
```

---

## 7. Notificaciones Push (Solo Android)

Las notificaciones se mandan cuando:

- El cliente hace un pedido → notifica al dueño
- El dueño acepta el pedido → notifica al repartidor disponible

### Cómo se pide el token FCM

```dart
// En el main.dart al iniciar la app
final token = await FirebaseMessaging.instance.getToken();
// Se guarda en Supabase en la tabla users_fcm_tokens
```

### Cómo se procesa una notificación recibida

```dart
// Se configura en main.dart
FirebaseMessaging.onMessage.listen((message) {
  // App abierta → mostrar banner en la pantalla actual
  showTopBanner(context, message.notification?.body ?? '');
});

FirebaseMessaging.onMessageOpenedApp.listen((message) {
  // Usuario tocó la notificación → navegar a la pantalla correcta
  final route = message.data['route'];
  if (route != null) context.go(route);
});
```

---

## 8. Diferencias Importantes Web vs Móvil

Algunas funciones cambian dependiendo de si el usuario está en el navegador o en el teléfono.

### Detectar si es web

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (kIsWeb) {
  // Código para web
} else {
  // Código para móvil
}
```

### Qué cambia en cada pantalla

**Pantalla del repartidor:**
```dart
// Si está en web → mostrar aviso
if (kIsWeb) {
  return Scaffold(
    body: Center(child: Text('Descarga la app móvil para usar el panel del repartidor'))
  );
}
// Si está en móvil → mostrar el panel completo con GPS
```

**Dirección en el registro:**
```dart
// En móvil → botón GPS para detectar ubicación automáticamente
// En web → solo campo de texto para escribir la dirección
```

**Mapa de rastreo:**
- Móvil: `google_maps_flutter` (mapa interactivo completo)
- Web: no disponible (`google_maps_flutter` no soporta web)
- Panel de flota: `flutter_map` con OpenStreetMap (funciona en ambos)

---

## 9. Cómo Agregar una Nueva Pantalla

Pasos para agregar una pantalla nueva al proyecto:

**1. Crear el archivo en `lib/screens/`:**
```dart
// lib/screens/nueva_pantalla.dart
import 'package:flutter/material.dart';

class NuevaPantalla extends StatefulWidget {
  const NuevaPantalla({super.key});
  @override
  State<NuevaPantalla> createState() => _NuevaPantallaState();
}

class _NuevaPantallaState extends State<NuevaPantalla> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text('Nueva Pantalla')),
      body: const Center(child: Text('Contenido')),
    );
  }
}
```

**2. Agregar la ruta en `lib/router.dart`:**
```dart
import 'screens/nueva_pantalla.dart';

// Dentro del array de routes:
GoRoute(path: '/nueva', builder: (_, _) => const NuevaPantalla()),
```

**3. Navegar a ella desde otra pantalla:**
```dart
context.go('/nueva');
```

---

## 10. Problemas Comunes en el Frontend

### La pantalla muestra datos vacíos

**Causa:** El `SupabaseService` está en modo mock (`useMock = true`) pero el código espera datos reales.
**Solución:** Cambiar `useMock = false` en `supabase_service.dart`.

### El carrito se vacía al navegar

**Causa:** La pantalla está creando un nuevo `CartProvider` en lugar de leer el global.
**Solución:** Usar `context.read<CartProvider>()` — NO `CartProvider()`.

### Las fotos no cargan

**Causa 1:** URL de imagen incorrecta o dominio bloqueado.
**Causa 2:** El bucket de Storage no es público.
**Diagnóstico:** Abrir la URL de la imagen directamente en el navegador.

### El texto del botón se ve cortado

**Causa:** El texto es muy largo para el ancho del botón.
**Solución:** Usar `Text('...', overflow: TextOverflow.ellipsis)` o reducir el texto.

### La app se ve diferente en web y móvil

**Es lo esperado.** Flutter renderiza los widgets de forma ligeramente diferente en web. Para diferencias grandes, verificar si hay código condicional con `kIsWeb` que deba actualizarse.

### Navegación no funciona (GoException)

**Causa:** La ruta a la que se intenta navegar no existe en `router.dart`.
**Solución:** Verificar que el path exista exactamente igual (sin espacios, sin mayúsculas).

---

## 11. Flujo Visual Completo por Rol

### Cliente
```
Abre app → Splash → /login → /restaurants
→ Toca restaurante → menú con categorías
→ Agrega al carrito → /checkout
→ Paga (efectivo o Stripe)
→ Pedido creado → /tracking (rastreo GPS del repartidor)
→ Pedido entregado → pantalla de calificación
```

### Dueño
```
Entra por /restaurante (login naranja)
→ /dueno → panel con pestañas:
    ├── Pedidos del día (con estado)
    ├── Menú (categorías + productos)
    └── Configuración (nombre, foto, dirección)
```

### Repartidor
```
Entra por /moto (login naranja)
→ /repartidor → ve pedidos pendientes de aceptar
→ Acepta un pedido → inicia GPS
→ GPS transmite ubicación cada 5 metros
→ Cliente ve el mapa actualizado en tiempo real
→ Marca como entregado
```

### Jefe de flota
```
Entra por /flota-login (login azul oscuro)
→ /flota → panel con cards por repartidor:
    ├── Mapa OSM con posición actual
    ├── Estado: ONLINE / OFFLINE
    ├── Entregas del día
    ├── Ganancias del día
    └── Botón "Abrir en Google Maps"
```

---

*Grupo Fercadi — GOGO Food | Junio 2026*
