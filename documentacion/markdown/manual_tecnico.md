# Manual Técnico — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿A quién va dirigido este manual?

A los desarrolladores que trabajan en el proyecto. Explica cómo funciona el código por dentro: cómo se comunican las capas, cómo fluyen los datos, cómo funciona la autenticación y los patrones de diseño usados.

---

## 1. Punto de Entrada de la App

### `lib/main.dart` — App cliente y web

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await Stripe.instance.applySettings(publishableKey: stripePublishableKey);
  runApp(
    MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => CartProvider()),
      ChangeNotifierProvider(create: (_) => AppDataProvider()),
    ], child: const MyApp()),
  );
}
```

- Supabase se inicializa antes de que arranque la UI
- Stripe se configura con la clave pública
- Se montan dos Providers globales: carrito y datos de la app

### `lib/main_admin.dart` — App administrador

Punto de entrada alternativo que solo monta la ruta `/admin`. Se usa para compilar la APK exclusiva del administrador Fercadi.

---

## 2. Sistema de Navegación (go_router)

Toda la navegación está en `lib/router.dart`. Se usa `GoRouter` con rutas estáticas:

```dart
final appRouter = GoRouter(
  initialLocation: '/',   // Siempre arranca en el splash
  routes: [
    GoRoute(path: '/',              builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/login',         builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/restaurants',   builder: (_, _) => const RestaurantsScreen()),
    GoRoute(path: '/flota-login',   builder: (_, _) => const FlotaLoginScreen()),
    GoRoute(path: '/flota',         builder: (_, _) => const FlotaScreen()),
    // ... más rutas
  ],
);
```

### Cómo navegar entre pantallas

```dart
// Reemplazar la pantalla actual (sin volver atrás)
context.go('/restaurants');

// Agregar pantalla al stack (puede volver atrás)
context.push('/product-detail', extra: {'product': p, 'restaurantId': id});

// Leer parámetros pasados por extra
final extra = state.extra as Map<String, dynamic>;
final product = extra['product'] as Product;
```

### Rutas con parámetros

```dart
GoRoute(
  path: '/product-detail',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>;
    return ProductDetailScreen(
      product: extra['product'] as Product,
      restaurantId: extra['restaurantId'] as String,
    );
  },
),
```

---

## 3. Sistema de Autenticación

### `lib/services/auth_service.dart`

Maneja la sesión del usuario usando **dos capas**:

1. **Supabase Auth** — fuente de verdad (tokens JWT)
2. **SharedPreferences** — caché local para acceso rápido sin esperar a Supabase

#### Guardar sesión (después de login exitoso)

```dart
static Future<void> saveSession(String email, String role) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('user_email', email);
  await prefs.setString('session_role', role);
  await prefs.setBool('is_logged_in', true);
}
```

#### Leer sesión (en el splash screen)

```dart
static Future<UserSession?> getSession() async {
  final prefs = await SharedPreferences.getInstance();
  final isLogged = prefs.getBool('is_logged_in') ?? false;
  if (!isLogged) return null;
  return UserSession(
    email: prefs.getString('user_email') ?? '',
    role: prefs.getString('session_role') ?? '/login',
  );
}
```

#### Cerrar sesión

```dart
static Future<void> clearSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
}
```

### Flujo del Splash Screen

El `splash_screen.dart` decide adónde ir al abrir la app:

```dart
Future<void> _navigate() async {
  // Espera 1.5 seg (animación del logo) y lee la sesión en paralelo
  final results = await Future.wait([
    Future.delayed(Duration(milliseconds: 1500)),
    AuthService.getSession(),
  ]);

  final session = results[1];

  // Sin sesión → login de cliente
  if (session == null) { context.go('/login'); return; }

  final route = session.role;

  // Dueño y repartidor tienen su propio login independiente
  if (route == '/dueno' || route == '/repartidor') {
    await AuthService.clearSession();
    context.go('/login');
    return;
  }

  // Admin y flota requieren verificar la sesión viva de Supabase
  if (!useMock && (route == '/admin' || route == '/flota')) {
    final supabaseSession = await _waitForSupabaseSession();
    if (supabaseSession == null) {
      await AuthService.clearSession();
      context.go('/login');
      return;
    }
    final liveRole = supabaseSession.user.userMetadata?['role'];
    if (liveRole == 'admin') { context.go('/admin'); return; }
    if (liveRole == 'jefe_flota') { context.go('/flota'); return; }
    context.go('/login');
    return;
  }

  context.go(route);
}
```

### Esperar la sesión inicial de Supabase (Web)

En Flutter Web, la sesión de Supabase se restaura de `localStorage` de forma asíncrona. Hay que esperar al evento `initialSession`:

```dart
Future<Session?> _waitForSupabaseSession() async {
  final current = Supabase.instance.client.auth.currentSession;
  if (current != null) return current;
  try {
    final state = await Supabase.instance.client.auth.onAuthStateChange
        .firstWhere((s) =>
            s.event == AuthChangeEvent.initialSession ||
            s.event == AuthChangeEvent.signedIn)
        .timeout(Duration(seconds: 6));
    return state.session;
  } catch (_) { return null; }
}
```

---

## 4. Estado Global (Provider)

### `CartProvider` — Carrito de compras

```dart
class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // Agregar producto al carrito
  void addItem(Product product, String restaurantId) {
    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity++;
    } else {
      _items[product.id] = CartItem(product: product, restaurantId: restaurantId);
    }
    notifyListeners(); // Notifica a todas las pantallas que escuchan
  }

  // Total del carrito
  double get totalAmount =>
      _items.values.fold(0, (sum, item) => sum + item.product.price * item.quantity);
}
```

**Cómo usar el carrito en cualquier pantalla:**

```dart
// Leer sin reconstruir
final cart = context.read<CartProvider>();
cart.addItem(product, restaurantId);

// Leer y reconstruir cuando cambie
final totalItems = context.watch<CartProvider>().itemCount;
```

### `AppDataProvider` — Likes de restaurantes

Carga los likes desde Supabase y permite actualizar en tiempo real sin recargar toda la pantalla.

---

## 5. Capa de Datos (SupabaseService)

`lib/services/supabase_service.dart` es el archivo más grande del proyecto. Contiene **todos los métodos de acceso a datos**.

### Modo Mock vs Real

```dart
static const bool useMock = false;
// true  → Devuelve datos hardcodeados (sin internet, para desarrollo)
// false → Lee y escribe en Supabase real
```

Todos los métodos tienen este patrón:

```dart
static Future<List<Restaurant>> getRestaurants() async {
  if (useMock) return _mockRestaurants(); // Datos ficticios
  final data = await _client.from('restaurants').select().eq('is_active', true);
  return data.map((r) => Restaurant.fromJson(r)).toList();
}
```

### Métodos principales

| Método | Qué hace |
|---|---|
| `getRestaurants()` | Lista todos los restaurantes activos |
| `getMenu(restaurantId)` | Trae categorías y productos de un restaurante |
| `createOrder(orderData)` | Crea un nuevo pedido en la BD |
| `getActiveOrders()` | Trae pedidos del día (para el dueño/admin) |
| `updateOrderStatus(id, status)` | Cambia el estado de un pedido |
| `broadcastLocation(lat, lng)` | Actualiza la posición GPS del repartidor en tracking |
| `broadcastRiderPresence(lat, lng)` | Actualiza la posición en `rider_locations` (para flota) |
| `getFlotaRiders(jefeId)` | Trae los riders vinculados a un jefe de flota |
| `getRiderLocations(riderIds)` | Trae la última ubicación GPS de una lista de riders |
| `getRiderOrdersToday(riderId)` | Trae todos los pedidos del día de un rider |
| `deleteRestaurant(id)` | Borra restaurante y todos sus datos en cascada |

### Reparación de URLs de imágenes

```dart
// Unsplash no funciona bien en web sin parámetros específicos
static String _repairUrl(String url) {
  if (url.contains('unsplash.com') && !url.contains('?')) {
    return '$url?w=400&h=300&fit=crop&q=80';
  }
  return url;
}

// Mapa de overrides por ID de producto (para corregir fotos específicas)
static const Map<String, String> _productImageFix = {
  'ep1781496944163': 'https://images.pexels.com/photos/1639557/pexels-photo-1639557.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop',
  // más overrides...
};
```

---

## 6. Modelos de Datos

Cada modelo tiene `fromJson()` para deserializar desde Supabase y `toJson()` para serializar:

### Ejemplo: `Restaurant`

```dart
class Restaurant {
  final String id;
  final String name;
  final String? imageUrl;
  final String address;
  final String? ownerId;
  final bool isActive;

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id:       json['id'] as String,
      name:     json['name'] as String,
      imageUrl: json['image_url'] as String?,
      address:  json['address'] as String? ?? '',
      ownerId:  json['owner_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
```

### Ejemplo: `Product`

```dart
class Product {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final String? description;
  final bool isAvailable;
  final String? promoLabel;
  final List<String> additionalImages;
}
```

---

## 7. Sistema GPS y Ubicación

### Validación de zona de cobertura

La app solo funciona dentro de 30 km del centro de Maravatío:

```dart
// lib/services/location_service.dart
static const double _centerLat = 19.8969;
static const double _centerLng = -100.4447;
static const double _maxRadiusKm = 30.0;

static Future<bool> isInCoverageArea() async {
  if (SupabaseService.useMock) return true; // Mock siempre está dentro

  final position = await Geolocator.getCurrentPosition();
  final distance = Geolocator.distanceBetween(
    _centerLat, _centerLng,
    position.latitude, position.longitude,
  ) / 1000; // Convertir metros a km

  return distance <= _maxRadiusKm;
}
```

### Transmisión de GPS del repartidor

El `repartidor_screen.dart` inicia un stream de GPS que corre mientras la app está abierta:

```dart
_gpsSub = Geolocator.getPositionStream(
  locationSettings: LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // Solo actualiza si se movió más de 5 metros
  ),
).listen((pos) {
  setState(() => _myPos = pos);

  // Siempre transmite al panel de flota
  SupabaseService.broadcastRiderPresence(pos.latitude, pos.longitude);

  // Solo transmite al tracking del cliente si tiene pedido activo
  if (_activeOrder != null) {
    SupabaseService.broadcastLocation(pos.latitude, pos.longitude);
  }
});
```

---

## 8. Sistema de Pagos (Stripe)

### Flujo técnico en `checkout_screen.dart`

```dart
Future<void> _payWithStripe() async {
  // 1. Pedir el clientSecret a la Edge Function
  final response = await Supabase.instance.client.functions.invoke(
    'create-payment-intent',
    body: {'amount': (total * 100).toInt(), 'currency': 'mxn'},
  );

  final clientSecret = response.data['clientSecret'] as String;

  // 2. Inicializar el PaymentSheet con el clientSecret
  await Stripe.instance.initPaymentSheet(
    paymentSheetParameters: SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      merchantDisplayName: 'GOGO Food',
    ),
  );

  // 3. Mostrar la pantalla de pago
  await Stripe.instance.presentPaymentSheet();

  // 4. Si llega aquí sin excepción, el pago fue exitoso
  await _createOrder(paymentMethod: 'card');
}
```

### Edge Function en Supabase (TypeScript)

```typescript
// supabase/functions/create-payment-intent/index.ts
import Stripe from 'npm:stripe@14';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!);

Deno.serve(async (req) => {
  const { amount, currency } = await req.json();

  const paymentIntent = await stripe.paymentIntents.create({
    amount,      // En centavos (ej. 15000 = $150.00 MXN)
    currency,    // 'mxn'
    automatic_payment_methods: { enabled: true },
  });

  return Response.json({ clientSecret: paymentIntent.client_secret });
});
```

---

## 9. Notificaciones Push (FCM)

Las notificaciones se envían cuando:
- Llega un pedido nuevo → notifica al dueño del restaurante
- El dueño acepta el pedido → notifica al repartidor disponible

```dart
// lib/services/notification_service.dart
static Future<void> sendOrderNotification({
  required String toToken,    // Token FCM del destinatario
  required String title,
  required String body,
  required Map<String, String> data,
}) async {
  await http.post(
    Uri.parse('https://fcm.googleapis.com/fcm/send'),
    headers: {
      'Authorization': 'key=$fcmServerKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'to': toToken,
      'notification': {'title': title, 'body': body},
      'data': data,
    }),
  );
}
```

> Las notificaciones **solo funcionan en Android**. En web se requiere configuración adicional de Service Worker para Web Push.

---

## 10. Panel de Flota — Implementación Técnica

### Polling automático en `flota_screen.dart`

```dart
@override
void initState() {
  super.initState();
  _jefeId = Supabase.instance.client.auth.currentUser?.id;
  _loadAll();
  // Actualiza cada 10 segundos
  _pollTimer = Timer.periodic(Duration(seconds: 10), (_) => _loadAll());
}

Future<void> _loadAll() async {
  final riders = await SupabaseService.getFlotaRiders(_jefeId!);
  final riderIds = riders.map((r) => r['rider_id'] as String).toList();
  final locations = await SupabaseService.getRiderLocations(riderIds);

  // Carga pedidos y pedido activo de cada rider en paralelo
  final ordersAndActivos = await Future.wait(
    riderIds.map((id) => Future.wait([
      SupabaseService.getRiderOrdersToday(id),
      SupabaseService.getRiderActiveOrder(id),
    ]))
  );
  // ...setState con todos los datos
}
```

### Detección de estado online/offline

```dart
bool _isOnline(String riderId) {
  final loc = _locations[riderId];
  if (loc == null) return false;
  final lastSeen = DateTime.tryParse(loc['last_seen'] ?? '');
  if (lastSeen == null) return false;
  // Online = última actualización hace menos de 5 minutos
  return DateTime.now().difference(lastSeen).inMinutes < 5;
}
```

### Mapa con OpenStreetMap en Flutter Web

```dart
FlutterMap(
  options: MapOptions(
    initialCenter: LatLng(lat, lng),
    initialZoom: 15,
    // Deshabilitar interacción (mapa de solo lectura)
    interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
  ),
  children: [
    // Tiles de OpenStreetMap (gratis, sin API key)
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.fercadi.app',
    ),
    // Marcador personalizado con ícono de moto
    MarkerLayer(markers: [
      Marker(
        point: LatLng(lat, lng),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
            child: Icon(Icons.delivery_dining_rounded, color: Colors.white),
          ),
          CustomPaint(painter: _PinTailPainter(_accent)), // Punta del pin
        ]),
      ),
    ]),
  ],
)
```

---

## 11. Diferencias Web vs Móvil

| Funcionalidad | Móvil (Android/iOS) | Web (navegador) |
|---|---|---|
| GPS | ✅ Funciona | ✅ Funciona (requiere permiso) |
| Google Maps | ✅ Funciona | ❌ No soportado |
| flutter_map (OSM) | ✅ Funciona | ✅ Funciona |
| Notificaciones push | ✅ Funciona | ❌ No implementado |
| Stripe PaymentSheet | ✅ Funciona | ⚠️ Soporte limitado |
| Panel repartidor | ✅ Completo | ⚠️ Muestra aviso "usa la app móvil" |
| SharedPreferences | ✅ Disco del teléfono | ✅ localStorage del navegador |

El código detecta si está en web con `kIsWeb`:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (!kIsWeb) {
  // Código solo para móvil (GPS, Google Maps, etc.)
}
```

---

## 12. Constantes y Configuración

`lib/core/constants.dart` — todos los valores configurables en un lugar:

```dart
class AppConstants {
  // Supabase
  static const String supabaseUrl = 'https://xxxx.supabase.co';
  static const String supabaseAnonKey = 'eyJ...';

  // Stripe
  static const String stripePublishableKey = 'pk_test_...';

  // Sentry (monitoreo de errores)
  static const String sentryDsn = ''; // Vacío = Sentry inactivo

  // Colores — App cliente/admin
  static const Color bgColor      = Color(0xFF121212);
  static const Color surfaceColor = Color(0xFF1E1E1E);
  static const Color primaryColor = Color(0xFFE91E8C); // Rosa/magenta

  // Colores — Panel dueño
  static const Color duenoPrimaryColor = Color(0xFFFF5722); // Naranja

  // Geolocalización — Centro de Maravatío
  static const double centerLat   = 19.8969;
  static const double centerLng   = -100.4447;
  static const double radiusKm    = 30.0;
}
```

---

*Grupo Fercadi — GOGO Food | Junio 2026*
