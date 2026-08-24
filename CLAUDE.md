# GOGO Food — Grupo Fercadi

App de delivery para Maravatío, Michoacán. Flutter + Supabase + Stripe.

---

## Stack

| Tecnología | Uso |
|---|---|
| Flutter (Dart 3.11.5) | Framework principal |
| Supabase | BD, Auth, Storage, Edge Functions |
| go_router ^14.0.0 | Navegación |
| provider ^6.1.2 | Estado global (carrito) |
| google_maps_flutter | Mapa para selección de dirección (móvil) |
| flutter_stripe | Pagos con tarjeta |
| geolocator | GPS |
| shared_preferences | Sesión persistente local |

---

## Correr la app

```powershell
flutter pub get
flutter run -d emulator-5554   # Android
flutter run -d chrome          # Web
```

Mock data: `lib/services/supabase_service.dart` → `static const bool useMock = true`
Supabase real: `false` + credenciales en `lib/core/constants.dart`

---

## Roles y pantallas

| Rol | Ruta | Pantalla |
|---|---|---|
| Cliente | `/restaurants` | Lista de restaurantes, carrito, checkout |
| Dueño | `/dueno` | Panel naranja — pedidos, productos, config restaurante |
| Repartidor | `/repartidor` | Pedidos activos (solo app móvil, web muestra aviso) |
| Admin | `/admin` | Panel oscuro — todos los restaurantes, pedidos, usuarios |
| Jefe de flota | `/flota` | Panel de riders a su cargo (mapa, entregas, ganancias) |

**Admin y Jefe de flota son apps/sitios separados**, no viven dentro de GOGO Food: `lib/main_admin.dart` / `lib/main_flota.dart`, cada uno con su propio router (`_adminRouter` / `_flotaRouter`), bundle id (`com.fercadi.admin` / `com.fercadi.flota`) y build (Android APK propio, flavor de iOS propio, sitio web propio). Ver `documentos/Documentaciones/manual_ios.md`.

El rol se guarda en `user_metadata.role` en Supabase Auth y en SharedPreferences.
La sesión persiste: el splash espera el evento `initialSession` de Supabase antes de rutear.

El restaurante de una cuenta dueño se guarda en `user_metadata.restaurant_id` (`AuthService.getRestaurantId()`), **no** en `restaurants.owner_id` — esa columna solo se escribe al auto-registrarse y no se lee para enrutar el panel.

---

## Temas

```dart
// App cliente / admin
bgColor      = 0xFF121212   // negro
surfaceColor = 0xFF1E1E1E
primaryColor = 0xFFE91E8C   // rosa/magenta

// Dueño y registro de restaurante
primaryColor = 0xFFFF5722   // naranja — NO cambiar
```

---

## Deploy

**Web** (Vercel — `web-iota-brown-32.vercel.app`):
```powershell
flutter build web --release
Copy-Item vercel.json build/web/vercel.json -Force
cd build/web
npx vercel --prod --archive=tgz
```

**Android APKs** (dos apps: cliente y admin):
```powershell
.\build_apks.ps1
# Genera: build\GOGOFood.apk y build\GOGOAdmin.apk
```

Bundle ID: `com.fercadi.app` (admin: `com.fercadi.admin`)

---

## Supabase — Tablas principales

`restaurants`, `categories`, `products`, `product_images`, `orders`, `order_items`, `product_likes`

RLS activa. Roles via `auth.jwt() -> 'user_metadata' ->> 'role'`.

Para eliminar restaurante desde admin: `SupabaseService.deleteRestaurant(id)` — borra en cascada.

---

## Comportamientos web vs móvil

- **Repartidor en web**: muestra pantalla "usa la app móvil", sin panel
- **Dirección en registro**: sin botón GPS (solo texto libre)
- **Dirección en panel dueño**: campo editable directo, sin mapa
- **Mapa (MapPickerScreen)**: solo funciona en móvil (google_maps_flutter no soporta web)

---

## Pendiente para tiendas

- [ ] Cambiar bundle ID de `com.example.landing_test` a `com.fercadi.gogofood`
- [ ] Crear keystore para firmar Android (Play Store)
- [ ] Cuenta Google Play ($25 USD una vez) → play.google.com/console
- [ ] Cuenta Apple Developer ($99 USD/año) → developer.apple.com
- [x] Icono 1024×1024 sin transparencia (diseño GOGO naranja, julio 2026 — `assets/images/app_icon.png`)
- [ ] Screenshots para ambas tiendas

---

## Geolocalización

- Centro Maravatío: `19.8969° N, 100.4447° W`, radio 50 km (cubre también Acámbaro)
- Mock siempre simula estar dentro del radio

---

## Zonas (Maravatío / Acámbaro)

- `restaurants.zona` (`'maravatio'` | `'acambaro'`) — el cliente solo ve restaurantes de su misma zona en `/restaurants`
- Se detecta **sola**, no hay botón manual: `LocationService.zonaFromCoords(lat, lng)` (Haversine contra los centros de ambas ciudades) o `detectZona(address)` si no hay coordenadas
- El cliente elige su zona desde el picker de dirección en `/profile` (`AuthService.getZona()`/`saveZona()`); el dueño la ve de solo lectura en `/dueno`, calculada desde la dirección del local

---

## GOGO Premium (Dueño)

Plan por restaurante, columna `restaurants.is_premium` (sin UI de cobro todavía — se activa a mano por SQL):

| Función | Gratis | Premium |
|---|---|---|
| Banners promocionales | ❌ Bloqueado (`_buildPremiumLocked`) | ✅ |
| Promo por platillo (descuento/2x1) | ❌ Bloqueado | ✅ |
| Platillos en el menú | Máx. 7 | Máx. 20 |

Todo en `dueno_screen.dart`, gateado con `_isPremium` (leído de `SupabaseService.getRestaurantIsPremium`).

---

## Retiros de repartidores (base, sin Stripe Connect todavía)

Solo `repartidor_plus` independientes (los de flota los paga su jefe de flota fuera de la plataforma). Saldo **siempre calculado en vivo**, nunca guardado: `SUM(delivery_fee)` de pedidos entregados − retiros completados − retiros abiertos (`get_rider_balance()` RPC). El rider solicita con `request_withdrawal(monto)` (mínimo $200, un solo retiro abierto a la vez); Admin transiciona con `admin_transition_withdrawal(...)` desde Más → Retiros.

Tablas: `rider_withdrawals`, `rider_payout_accounts` (CLABE + campos `stripe_*` reservados para el futuro), `withdrawal_status_log`. Capas Dart: `lib/models/rider_withdrawal.dart` → `lib/repositories/rider_withdrawal_repository.dart` → `lib/services/rider_withdrawal_service.dart` → `lib/controllers/rider_withdrawal_controller.dart`.

---

## Categorías de restaurante (filtro del cliente)

`restaurants.categorias` (`TEXT[]`) — lista fija elegida por el dueño al registrarse (`registro_restaurante_screen.dart`) o después desde su panel (`dueno_screen.dart`, sección "Categoría de tu restaurante"). **No** se toma de las categorías del menú de cada restaurante (esas son libres, las inventa cada dueño para organizar sus propios platillos) — son dos cosas distintas a propósito, para que el filtro del cliente sea consistente entre restaurantes.

Lista maestra en `lib/core/restaurant_categories.dart` (`kRestaurantCategories`) — agregar una categoría nueva es una sola línea ahí, sin migración de BD. El filtro en `restaurants_screen.dart` (botón "Categorías" en la lista principal) lee directo de `Restaurant.categorias` de los restaurantes de la zona del cliente.

**Categorías de menú** (tabla `categories`, las pestañas de platillos DENTRO de un restaurante — ej. "Platillos", "Entradas", "Bebidas") son un sistema aparte, sin relación con lo anterior. Hoy se crean solo por SQL directo (no hay UI de creación en la app); no confundir con `restaurants.categorias`. Lista genérica fija en `lib/core/product_categories.dart` (`kProductCategories`: Platillos, Entradas, Ensaladas, Desayunos, Acompañamientos, Postres, Bebidas) — los 15 restaurantes existentes ya se migraron a esta lista (agosto 2026), fusionando donde había nombres muy específicos (ej. "Tacos"+"Carnitas por Kilo"+"Antojitos" → "Platillos" en CarnitasElPuerco; "Cafés"+"Frappes" → "Bebidas" en Starbucks). Usar siempre esta lista para restaurantes nuevos.

---

## Perfil visible entre cliente y repartidor (como Uber)

Una vez que un repartidor acepta un pedido, cliente y repartidor pueden verse el nombre/foto real de perfil el uno al otro (antes de eso, no — ni el pedido tiene todavía repartidor asignado, ni el repartidor debe ver el perfil de un cliente que aún no le corresponde).

- `orders.customer_id` (`UUID`, nuevo) — se llena solo en `SupabaseService.createOrder` con el `auth.uid()` del cliente que hace el pedido. `orders.repartidor_id` ya existía, se llena al aceptar.
- Edge Function `order-user-lookup` (separada de `admin-user-lookup`, que sigue exclusiva para Admin) — cualquier usuario autenticado puede llamarla, pero **solo para ver a su contraparte en un pedido donde de verdad participa**: verifica contra la tabla `orders` que quien llama sea `customer_id` o `repartidor_id` de ese pedido, y que el perfil pedido sea el del otro lado. Nunca expone la service role key al cliente.
- `SupabaseService.getOrderCounterpartProfile(orderId, targetUserId)` — capa Dart que llama a esa función. Revisa varias keys de `user_metadata` (`avatar_url`/`custom_avatar_url`/`picture`, `name`/`custom_name`/`full_name`) porque repartidor de flota, repartidor plus y cliente guardan su foto/nombre con keys distintas entre sí.
- Cliente: `tracking_screen.dart` muestra una tarjeta propia (foto+nombre) justo arriba del panel del pedido, en cuanto se acepta — tocarla abre el detalle con nivel, entregas y medallas del repartidor.
- Repartidor: `repartidor_screen.dart` (flota) y `entrega_activa_screen.dart` (repartidor plus) muestran la foto/nombre real del cliente en "Datos del cliente", una vez aceptado el pedido.
- Medallas por repartos (🚀🔥⚡🏆👑💎) centralizadas en `lib/core/rider_achievements.dart` (`kRiderAchievements`) — antes vivían duplicadas/privadas dentro de `repartidor_plus_screen.dart`; ahora esa pantalla y el detalle del cliente en `tracking_screen.dart` leen la misma lista.

---

## Notificaciones (estado real, agosto 2026)

**No hay push real (FCM/APNs) en ninguna plataforma** — ni Android ni iOS. `firebase_messaging` no está instalado; `lib/services/fcm_service.dart` es un placeholder deliberadamente comentado, a la espera de un proyecto Firebase real. `SupabaseService.createOrder` recibe `clientFcmToken` pero nunca lo guarda; `orders.client_fcm_token` nunca se llena, así que `_sendFcmForStatus` siempre corta antes de invocar la Edge Function `send-order-notification` (que además usa la API legacy de FCM, descontinuada por Google en junio 2024 — habría que reescribirla con la API v1 igual).

Lo que sí existe: **notificaciones locales** (`lib/services/notification_service.dart`, `flutter_local_notifications`) — la propia app, mientras está abierta o recién en background, detecta cambios de estado por *polling* (`tracking_screen.dart` cada 4s) y dispara el aviso localmente. Esto **no llega con la app cerrada o hace rato en segundo plano** — para eso sí se necesita FCM/APNs real.

Bug corregido: `DarwinInitializationSettings` (iOS) tenía las 3 banderas de permiso en `false` — iOS nunca pedía permiso de notificaciones, así que cualquier notificación local se descartaba en silencio. Android sí las pedía. Ya corregido (las 3 en `true`) — con esto iOS debería mostrar las mismas notificaciones que Android mientras la app esté abierta/reciente.

Para push real con la app cerrada: proyecto Firebase (gratis) + cuenta Apple Developer ($99/año, ya pendiente en este archivo) para la key APNs (.p8) + reescribir la Edge Function con la API v1 + descomentar `fcm_service.dart` + guardar el token en `orders`.

---

## Seguimiento del pedido — ya existía, solo se corrigieron bugs de UI/GPS

`tracking_screen.dart` (cliente) ya es una pantalla completa de seguimiento (stepper de 4 pasos + mapa en vivo) — no había que construir nada nuevo ahí. Correcciones aplicadas:

- El marcador del repartidor en el mapa del cliente ya no se muestra si el pedido está `delivered`/`cancelled` (antes seguía "parado" ahí si se reabría un pedido viejo desde el historial).
- GPS en `entrega_activa_screen.dart`/`repartidor_screen.dart`: antes solo se usaba `getPositionStream()`, que puede tardar mucho en entregar su primer punto en frío — el "arreglo" de abrir Google Maps y volver funcionaba porque eso *despierta* el GPS del sistema, no por nada que hiciera la app. Ahora se pide también un `getCurrentPosition()` puntual al iniciar (mismo efecto, sin salir de la app), y en `entrega_activa_screen.dart` aparece un botón "Reintentar" si sigue sin llegar nada después de 12s.
- Elementos encimados en el paso "En camino" (`entrega_activa_screen.dart`/`repartidor_screen.dart`): el aviso verde "Transmitiendo ubicación en vivo" se dibujaba en la misma franja que la fila de arriba (chip de paso + "Cómo llegar") — se movió más abajo. Los avisos de "Buscando ubicación"/"Dirección no encontrada" (mismo `Positioned`) ahora se apilan en una `Column` en vez de superponerse si ambos aplican a la vez.
- Panel de `entrega_activa_screen.dart` ahora es un `DraggableScrollableSheet` (mismo patrón que el sheet de "Retos" en `repartidor_plus_screen.dart`) — el repartidor puede arrastrarlo para ver más mapa o más info del pedido, con los botones de acción siempre fijos abajo.
