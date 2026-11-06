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

**RLS lee `app_metadata`, no `user_metadata`** (`is_dueno()`/`is_admin()` en Supabase, vía `auth.jwt() -> 'app_metadata'`) — a propósito: `user_metadata` lo puede editar el propio usuario (`auth.updateUser`), así que si las políticas confiaran en él cualquiera podría auto-otorgarse el rol que quisiera. El trigger `trg_sync_role_to_app_metadata` (`BEFORE INSERT OR UPDATE ON auth.users`) copia `role` y `restaurant_id` de `user_metadata` a `app_metadata` automáticamente en cuanto se crean/actualizan (p. ej. al llamar `AuthService.saveRestaurantId`) — la app y el código Dart siguen leyendo/escribiendo `user_metadata` sin enterarse de este paso intermedio.

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

## Login de Riders y Restaurantes (investigado y corregido, sept 2026)

Riders y Restaurantes no podían iniciar sesión con correo+contraseña aunque
las credenciales fueran correctas. No era un bug de las pantallas de login
(`dueno_login_screen.dart`/`repartidor_login_screen.dart` ya hacían bien el
`signInWithPassword` + chequeo de rol) — eran **cuatro problemas reales**,
todos fuera de esas pantallas:

1. **El registro creaba la cuenta en el proyecto de Supabase equivocado.**
   El registro se había movido a un sitio externo (`gogo-registro.vercel.app`)
   que apunta a `mmjzyqvjdwhzefbaiums.supabase.co` (el proyecto original), pero
   la app instalada (tanto GOGO Food como GOGO Pruebas — ningún build pasa
   `--dart-define`) siempre autentica contra `ymztoayxzewghbethahv.supabase.co`
   ("GOGO-Pruebas", la base que se decidió dejar como definitiva). Cualquier
   cuenta creada en el sitio externo era invisible para la app. **Corrección:**
   se restauró el registro DENTRO de la app —
   `lib/screens/dueno/registro_restaurante_screen.dart` y
   `lib/screens/repartidor_plus/registro_rider_plus_screen.dart` (rutas
   `/registro-restaurante` y `/registro-rider`, enlazadas desde los botones
   "¿Nuevo restaurante?"/"¿Nuevo repartidor?" de los login) — así el registro
   usa siempre el mismo `Supabase.instance.client` que el login.
2. **Confirmación de correo obligatoria sin ningún flujo que la completara.**
   GOGO-Pruebas tiene "Confirm email" activo, pero la app no maneja el enlace
   de confirmación en ningún lado — toda cuenta nueva quedaba con
   `email_confirmed_at = NULL` para siempre, y `signInWithPassword` la
   rechazaba con `email_not_confirmed` (que las pantallas de login mostraban,
   engañosamente, como "Correo o contraseña incorrectos"). **Corrección:**
   `supabase/migrations/20260907170000_auto_confirm_email_signup.sql` —
   trigger `trg_gogo_auto_confirm_email` que confirma el correo solo en el
   instante del registro, más backfill de las cuentas ya atascadas.
3. **Hueco de RLS en `restaurants`:** una política vieja (`write_restaurants`,
   heredada del baseline de agosto) dejaba escribir la tabla a *cualquier*
   usuario autenticado, sin importar su rol — un Rider podía crear/editar
   restaurantes ajenos por API directa. **Corrección:**
   `20260907170500_fix_restaurants_write_policy_hole.sql` — se eliminó esa
   política (las políticas `insert_restaurants`/`update_restaurants`/
   `delete_restaurants`, gateadas por `is_dueno()`/`is_admin()`, ya existían y
   quedan como las únicas). El mismo patrón `write_<tabla> ...
   auth.role()='authenticated'` sigue existiendo, **sin revisar todavía**, en
   `categories`, `flota_members`, `order_items`, `platform_config`,
   `product_likes`, `products`, `restaurant_banners`, `restaurant_likes`.
4. **Un dueño no podía ver el restaurante que acababa de registrar:** Postgres
   exige que la fila insertada también pase la política de SELECT para poder
   hacer `.insert({...}).select()` — y `read_restaurants` solo dejaba ver un
   restaurante propio si `restaurant_id` ya estaba sincronizado en el JWT, cosa
   que solo pasa DESPUÉS de este mismo insert. **Corrección:**
   `20260907171000_fix_restaurants_read_policy_owner_gap.sql` — se agregó
   `owner_id = auth.uid()` a `read_restaurants`.

Las tres migraciones ya están aplicadas a GOGO-Pruebas. Ver
`supabase/migrations/2026090717*.sql` para el detalle completo de cada causa.
Verificado de punta a punta (API + build real en dispositivo): registro →
login → redirección al panel correcto, para Rider y para Dueño, con
contraseña incorrecta siguiendo rechazada y sin tocar cuentas/datos previos.

---

## Aislamiento GOGO Food (producción) vs GOGO Pruebas — auditoría sept 2026

**Hallazgo central: hoy NO existe separación real entre GOGO Food y GOGO
Pruebas.** Los dos "flavors" de iOS (`pruebas` y el default) y los tres APKs
de Android (`build_apks.ps1`) solo difieren en bundle id/nombre/ícono —
ninguno pasa `--dart-define` ni lee `FLUTTER_APP_FLAVOR`, así que
`lib/core/constants.dart` sirve el mismo valor por default sin importar qué
build sea: **`ymztoayxzewghbethahv.supabase.co`** ("GOGO-Pruebas"). El
proyecto original (`mmjzyqvjdwhzefbaiums.supabase.co`, aquí llamado
"producción") no lo usa ningún build actual — pero sigue vivo, con datos
reales (15 restaurantes, esquema más viejo — le falta por ejemplo la columna
`approval_status`) y con el webhook de Stripe real (`stripe-webhook`,
configurado el 29 de julio) apuntando ahí, mientras que ese mismo secreto
(`STRIPE_WEBHOOK_SECRET`) **no** está configurado en el proyecto Pruebas que
la app sí usa — cualquier pago real que pase por la app hoy no puede
confirmarse correctamente por webhook, porque el pedido vive en un proyecto
y el webhook llega a otro.

Otros hallazgos de la misma auditoría:
- Los 15 restaurantes de Pruebas son un **duplicado exacto** de los de
  producción (mismos `id`, ej. Starbucks = `"2"` en ambos) — se sembraron
  juntos al crear Pruebas; no es una fuga accidental de esta sesión, pero
  tampoco son datasets independientes como se asumía.
- El widget nativo (`GOGOTrackingWidget.swift`) tenía hardcodeada la URL de
  producción mientras la app (que llena sus datos vía App Group) usa
  Pruebas — el widget nunca podía autenticar (JWT de un proyecto rechazado
  por el otro). **Corregido**: ahora apunta al mismo proyecto que la app.
- Ambos flavors (Food y Pruebas) comparten el **mismo App Group de iOS**
  (`group.com.fercadi.app`, en `Runner.entitlements` y
  `GOGOTrackingWidget.entitlements`, igual en las 4 configuraciones de
  build) — si algún día sí usan proyectos de Supabase distintos, sus
  sesiones/tokens compartirían el mismo contenedor de `UserDefaults` en el
  mismo teléfono. **No corregido todavía** (requiere separar entitlements +
  editar `project.pbxproj`, y hoy no cambia nada en la práctica porque ambos
  flavors ya comparten el mismo backend) — pendiente si se separan los
  proyectos de verdad.
- Edge Functions: SÍ están desplegadas en ambos proyectos (`create-payment-intent`,
  `stripe-webhook`, `order-user-lookup`, `admin-user-lookup`,
  `send-order-notification` responden en los dos) — leen sus credenciales de
  `Deno.env.get(...)`, nunca hardcodeadas, así que no hay riesgo de mezcla
  ahí en el código — solo falta configurar bien los secretos por proyecto.

**Pendiente de decisión (no es algo que se deba resolver solo):** si
producción de verdad va a ser `mmjzyqvjdwhzefbaiums` (requeriría ponerle al
día el esquema — le faltan migraciones que Pruebas ya tiene) o si se
abandona y Pruebas pasa a ser la única base real de aquí en adelante. Hasta
que se decida, **GOGO Food sigue usando exactamente los mismos datos que
GOGO Pruebas** — cualquier cuenta/pedido/restaurante que se cree en un
"flavor" es visible en el otro porque literalmente es la misma base.

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
- Centro Morelia: `19.7059° N, 101.1949° W` (Catedral), su propio radio de 50 km — está a ~80 km de Maravatío, fuera de su radio, así que se revisa aparte (agregado septiembre 2026, a petición del dueño)
- Mock siempre simula estar dentro del radio
- El geocoding de direcciones (`LocationService.geocodeAddress`) ya no fuerza "Maravatío" en la búsqueda — usa "Michoacán, México" como pista, para que funcione igual de bien en Morelia (antes solo funcionaba bien en Maravatío/Acámbaro)
- **"Detectar mi ubicación" en el registro de restaurante hacía lo contrario de lo que decía** (`registro_restaurante_screen.dart`, corregido oct 2026): ignoraba el texto del campo "Dirección" por completo y sobreescribía con el GPS del dispositivo — si el GPS fallaba (común en pruebas), no pasaba nada sin ningún aviso. Ahora, si ya hay texto escrito, lo geocodifica de verdad con `LocationService.geocodeAddress` y solo cae al GPS si el campo está vacío.

---

## Zonas (Maravatío / Acámbaro / Morelia)

- `restaurants.zona` (`'maravatio'` | `'acambaro'` | `'morelia'`) — el cliente solo ve restaurantes de su misma zona en `/restaurants`
- Se detecta **sola**, no hay botón manual: `LocationService.zonaFromCoords(lat, lng)` (Haversine contra los centros de las tres ciudades) o `detectZona(address)` si no hay coordenadas
- El cliente elige su zona desde el picker de dirección en `/profile` (`AuthService.getZona()`/`saveZona()`); el dueño la ve de solo lectura en `/dueno`, calculada desde la dirección del local
- `LocationService.zonaLabel(zona)` centraliza el nombre para mostrar de cada zona — usarlo en vez de un ternario nuevo cada vez

---

## GOGO Premium (Dueño)

Plan por restaurante, columna `restaurants.is_premium` (sin UI de cobro todavía — se activa a mano por SQL):

| Función | Gratis | Premium |
|---|---|---|
| Banners promocionales | ❌ Bloqueado (`_buildPremiumLocked`) | ✅ |
| Promo por platillo (descuento/2x1) | ❌ Bloqueado | ✅ |
| Platillos en el menú | Máx. 7 | Máx. 20 |

Todo en `dueno_screen.dart`, gateado con `_isPremium` (leído de `SupabaseService.getRestaurantIsPremium`).

**Diálogo "¡ya eres Premium!" disparándose solo (corregido oct 2026):** salía incluso al cerrar sesión y volver a entrar sin que nada hubiera cambiado. Causa: `didChangeAppLifecycleState` dispara `_checkPremiumActivated()` en cuanto la app pasa a `resumed` — algo que ocurre casi de inmediato al abrir/reabrir la pantalla — y eso podía ganarle la carrera a `_initRestaurant()` (que todavía no había puesto `_isPremium` en `true`, seguía en su valor por default `false`). Con el restaurante ya Premium de antes, esa comparación veía `premium=true && !_isPremium(false)` y lo trataba como "recién activado". Corregido con el candado `_premiumChecked` — `_checkPremiumActivated()` no hace nada hasta que `_initRestaurant()` haya completado su primera consulta real.

---

## Envío gratis (promos) dejaba al repartidor sin cobrar ese pedido — corregido oct 2026

Un promo con `applies_to_shipping=true` (incluye el tipo `free_shipping`) descuenta el `delivery_fee` del pedido hasta dejarlo en 0 — correcto para lo que ve el CLIENTE (debe verse "envío gratis"), pero **todo** lo que calcula ganancias de repartidor leía ese mismo `delivery_fee` ya descontado: `get_rider_balance()` (saldo retirable real), y las pantallas `repartidor_screen.dart`, `repartidor_plus_screen.dart`, `flota_screen.dart`/`flota_rider_detail_screen.dart` (gráficas/listas de "cuánto ganó"). Resultado real: un repartidor que entregaba un pedido con envío gratis hacía el mismo recorrido pero cobraba **$0** por esa entrega — el costo de la promo lo terminaba absorbiendo el repartidor, no la plataforma/restaurante (que es quien decide ofrecer la promo).

Corrección: nueva columna `orders.rider_delivery_fee` (migración `20261015000000_rider_delivery_fee.sql`) que guarda el envío **nominal**, calculado ANTES de cualquier descuento de promoción — es el que de verdad se le paga al repartidor. `delivery_fee` se queda igual (lo que se le cobró al cliente, puede ser $0 con envío gratis). `checkout_screen.dart` manda ambos valores a `SupabaseService.createOrder` (`deliveryFee` = post-descuento, `riderDeliveryFee` = `perOrderFee` pre-descuento); `get_rider_balance()` y las 4 pantallas de arriba ahora suman `coalesce(rider_delivery_fee, delivery_fee)` en vez de solo `delivery_fee`.

De paso se encontró que `create-payment-intent` nunca recibe `orderId` desde `checkout_screen.dart` (el único lugar que lo manda es `_payWithStripe`, que no lo incluye en el body) — así que la verificación "monto real contra la BD" de esa Edge Function nunca se activa en la práctica; hoy el único candado real contra manipulación del monto es el de abajo (promoción) y el tope de $50,000. Sin corregir todavía — no es lo que se reportó esta vez, pero es la causa de que el monto de Stripe dependa 100% de lo que calcula el celular.

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

## Flujo de aceptación en 2 pasos (restaurante confirma antes que el repartidor) — sept 2026

Antes, un pedido nuevo (`pending`) era visible y tomable por cualquier
repartidor al instante, sin que el restaurante interviniera — el botón
"Aceptar" del panel del dueño existía en la UI pero no estaba conectado a
nada (`onAccept`/`onCancel` se recibían como parámetros y nunca se usaban en
el `build()` de `_RealOrderCard`).

Ahora el flujo real es: `pending` → **`restaurant_accepted`** (el dueño
confirma) → `accepted` (un repartidor lo toma, se llena `repartidor_id`) →
`delivering` → `delivered`/`cancelled`. Un pedido en `pending` YA NO aparece
en "pedidos disponibles" de ningún repartidor —
`SupabaseService.getOrdersForRepartidor()` solo trae `restaurant_accepted`
(sin repartidor) + los que ya son de ese repartidor. Del lado del cliente,
`restaurant_accepted` se ve igual que `accepted` (mismo paso "Preparando" en
`tracking_screen.dart`), porque desde su perspectiva ambos significan
"todavía se está preparando".

Enforzado del lado servidor con un trigger (no solo RLS, porque ya existían
políticas viejas demasiado permisivas en `orders` que hubieran neutralizado
un candado hecho solo con RLS):
`enforce_restaurant_accepted_before_rider_claim()` (`BEFORE UPDATE ON
orders`) — bloquea con excepción cualquier intento de poner `repartidor_id`
si el pedido no venía ya en `restaurant_accepted`. Migración:
`supabase/migrations/20260928010000_two_step_order_acceptance.sql`.

## Comisión de la plataforma — sept 2026

GOGO se queda con un **10% fijo**, tanto del envío del repartidor como de la
venta del restaurante — guardado en `platform_config`
(`comision_repartidor_pct`, `comision_restaurante_pct`), leído en runtime por
`LocationService.loadTarifas()`.

- **Repartidor**: el 10% se descuenta del `delivery_fee` real dentro de
  `get_rider_balance()` (RPC,
  `supabase/migrations/20260928020000_platform_commission.sql`) — afecta el
  saldo retirable de verdad, no es solo un número cosmético. Además, en
  "Pedidos disponibles" (`repartidor_screen.dart` y
  `repartidor_plus_screen.dart`) ya no se muestra el total del pedido, se
  muestra una ESTIMACIÓN de cuánto va a ganar el repartidor — calculada con
  su posición GPS en vivo → restaurante → cliente
  (`LocationService.estimarGananciaRepartidor`), ya con el 10% restado. Es
  solo una estimación para la lista; el pago real sigue anclado al
  `delivery_fee` fijo del pedido.
- **Restaurante**: el dashboard del dueño (`ventasHoy` en
  `dueno_screen.dart`) aplica el mismo 10% sobre el bruto del día.

### `rider_locations.is_active` — columna muerta, investigado sept 2026

Se sospechó un bug ("el repartidor de flota se queda mostrando como
disponible después de cerrar sesión, porque nada marca `is_active =
false`"), pero al investigar a fondo resultó que **nada en toda la app ni
en las políticas de la base de datos lee esa columna** — ni un solo
`.eq('is_active', ...)` contra `rider_locations` en todo el código. Lo que
de verdad decide si un rider se ve "en línea" para el jefe de flota
(`flota_screen.dart`, `_isOnline()`) es si su `last_seen` tiene menos de 5
minutos — un chequeo que ya funciona bien y se autocorrige solo (no
depende de que alguien cierre sesión, cubre también el caso normal de que
la app se cierre sola o se pierda la señal). Se quitó
`SupabaseService.setRiderInactive()` (la función que escribía en esa
columna muerta) por ya no aportar nada.

## Registro y login por correo (cliente) — corregido sept 2026

`signUp()` con correo+contraseña solo pedía esos dos campos y nunca mandaba
al usuario a poner su nombre — a diferencia del alta por teléfono, que sí
pasa por `complete_profile_screen.dart`. Cuentas creadas por correo se
quedaban con nombre vacío para siempre. Corregido: ahora el alta por correo
también navega a `/complete-profile` (con la bandera
`_emailSignUpInProgress` para que el listener genérico de
`onAuthStateChange` no se adelante y mande al usuario a `/restaurants`
antes de pedirle el nombre — mismo patrón que ya usaba
`_phoneAuthInProgress`).

También se quitó el mensaje "revisa tu correo para confirmar" — ya no
aplica, el correo se auto-confirma solo (trigger
`trg_gogo_auto_confirm_email`, ver más abajo), así que ese aviso era
mentira y confundía.

Se agregó un campo de "Confirmar contraseña" en el formulario de registro —
sin este campo, un typo silencioso al escribir la contraseña dejaba la
cuenta con una contraseña distinta a la que el usuario creía haber puesto,
y luego el login fallaba con "contraseña incorrecta" sin que se notara por
qué.

## Selector de país (login/registro por teléfono) — corregido sept 2026

El paquete `phone_form_field` usa por default un `BottomSheetNavigator` que
NO es modal (`showBottomSheet` normal, sin fondo/foco propios) — el teclado
numérico del campo de teléfono se quedaba abierto detrás del buscador de
país, la búsqueda no recibía lo que se escribía, y no se podía cerrar
tocando afuera (solo se destrababa tocando un número). Corregido con un
`CountrySelectorNavigator` propio (`_GogoCountrySelectorNavigator` en
`phone_number_field.dart`) que abre una hoja modal de verdad
(`showModalBottomSheet`) con fondo blanco sólido explícito y tema claro
forzado — así no hereda el tema oscuro/naranja de la pantalla de atrás ni
se ve transparentado.

## Carrusel de promos (pantalla de restaurantes) — corregido sept 2026

El banner de "Promos" en `restaurants_screen.dart` (`_PromoCarousel`)
avanzaba solo cada 4s con un `Timer.periodic` que no sabía si el usuario
estaba arrastrando el carrusel con el dedo — le competía el swipe manual y
lo hacía regresar de golpe al principio. Corregido con un
`NotificationListener<ScrollNotification>` que distingue un drag real del
usuario (`dragDetails != null`) de nuestro propio `animateToPage`: pausa el
timer al detectar `ScrollStartNotification` con drag real, y lo reinicia
(desde 0s) en `ScrollEndNotification`.

## Banners promocionales — nunca desaparecían del carrusel al vencer — corregido oct 2026

Al agregarle un selector de duración al formulario de banners (ver más
abajo), se encontró un segundo bug relacionado: el % de descuento de un
banner sí dejaba de aplicarse al vencer (`RestaurantBanner.isDiscountActive`,
usado en `_recomputeBannerDiscounts()`), pero el banner en sí (imagen,
título, badge) **nunca se quitaba del carrusel** — `getBanners()` solo
filtraba `is_active = true`, sin checar `expires_at` en ningún lado del
lado de la UI. Se agregó `RestaurantBanner.isExpired` (independiente de si
tiene descuento o no — también aplica a banners informativos sin %) y se
filtra en `_buildPromoBanner()` (`restaurants_screen.dart`) antes de
armar las slides del carrusel.

## Formulario de banners — nunca tuvo forma de ponerles tiempo límite — corregido oct 2026

A diferencia del promo-por-platillo (que sí tiene un selector de
duración desde antes), el formulario para crear banners en
`dueno_screen.dart` nunca pedía una fecha de expiración —
`RestaurantBanner.expiresAt` siempre quedaba `null` (nunca expira). Se
agregó el mismo selector de chips (1h/2h/.../5 días + "No expira") usado
en el promo de platillo, conectado al campo real.

## CLABE del repartidor — se guardaba pero Admin nunca la veía — corregido oct 2026

`repartidor_plus_screen.dart` guarda la CLABE en `rider_payout_accounts`
específicamente para que Admin la vea al procesar un retiro manual
(`RiderWithdrawalRepository.saveClabe`), pero nada la leía de vuelta en
ningún lado — Admin tenía que pedírsela al repartidor por fuera de la
app. Se agregó `RiderWithdrawalRepository.getClabe()` y se muestra
(seleccionable, para copiar fácil) en la tarjeta "Cuenta del repartidor"
de `admin_retiros_screen.dart`. RLS ya permitía que Admin la leyera
(`read_own_payout_account`), no hizo falta ninguna migración.

## "Clientes y repartidores" en Admin — reescrito para usar cuentas reales — oct 2026

Antes esa pantalla armaba sus dos listas escaneando `orders` (clientes
desde `customer_name`/teléfono en texto libre, repartidores contando
`repartidor_id`) — una cuenta sin pedidos **no aparecía en ningún lado**,
y los repartidores salían con su UUID corto en vez de su nombre
(`getRepartidores()` nunca hacía join con el perfil real).

Se extendió la Edge Function `admin-user-lookup` con una acción nueva,
`listByRole` (`{action: 'listByRole', role: string | string[]}`) — usa
`admin.auth.admin.listUsers()` paginado y filtra por
`app_metadata.role`/`user_metadata.role`; un cliente normal no tiene
`role` guardado en absoluto, así que `'cliente'` se usa como valor
especial para "cualquier cuenta sin role". Nuevo wrapper en Dart:
`SupabaseService.listUsersByRole(roles)`.

`_buildUsuarios()` ahora usa esas listas reales como fuente de la lista
(`_clientUsers`/`_repartidorUsers`, cargadas una vez en `_loadUsuarios()`)
y solo usa `orders` para calcular la cifra de "pedidos"/"entregas" por
cuenta (via `customer_id`/`repartidor_id`). Se agregó
`SupabaseService.getOrdersByCustomerId()` (más confiable que el viejo
`getOrdersByPhone`, que dependía de texto libre). `_UserTile` y
`_UserDetailSheet` ahora también muestran la foto real
(`user_metadata.avatar_url`) en vez de solo un ícono genérico.

## Mensajes directos de Admin a un usuario — nuevo, oct 2026

No existía ninguna forma de que Admin le avisara algo puntual a una
cuenta específica (ej. "tu identificación salió borrosa, vuelve a
subirla") — el chat existente es solo por pedido (cliente↔repartidor) y
las alertas son para incidentes internos, ninguno de los dos sirve para
esto.

- Tabla nueva `admin_messages` (`recipient_id`, `sent_by`, `title`, `body`,
  `read_at`) — RLS: solo `is_admin()` puede insertar, cada quien ve solo
  lo suyo (`recipient_id = auth.uid() or is_admin()`), el destinatario
  puede marcar como leído su propia fila.
- Admin: botón "Mandar mensaje" (ícono ✈️) en `_UserDetailSheet`
  (`admin_screen.dart`) — abre un diálogo simple de título+cuerpo.
- Cliente/repartidor: pantalla nueva `avisos_screen.dart` (ruta
  `/avisos`), compartida igual que `/profile` — entrada con contador de
  no leídos agregada en `profile_screen.dart`, justo antes de la sección
  "Sesión".
- Es de una sola vía (Admin → usuario), sin respuesta — si se necesita
  ida y vuelta real después, hay que extenderlo.

## Documentos del registro web de un repartidor, visibles en Admin — nuevo, oct 2026

Los repartidores que se registran desde la página web oficial
(`gogo-web-pruebas`, repo separado `~/Pagina_web_GoGo`) suben foto de
perfil, identificación (frente/reverso) y comprobante de domicilio a una
tabla `drivers` + bucket privado `identificaciones` — pero **nada en
ninguna app los mostraba**, ni siquiera Admin. El bucket es privado a
propósito (son datos sensibles), así que ni Admin puede leerlo directo
desde el cliente — hace falta `service_role` para firmar URLs.

Se agregó la acción `driverDocs` a la Edge Function `admin-user-lookup`
(`{action: 'driverDocs', userId}`) — lee la fila de `drivers` con
service_role y firma URLs temporales (10 min) para los 3 documentos +
regresa la foto de perfil (bucket público, no necesita firma). Wrapper:
`SupabaseService.getDriverDocs(riderId)`. En Admin, botón "Ver
documentos" (ícono 🪪) en la ficha de un repartidor, visible solo para
riders (`_UserDetailSheet(isRider: true)`) — abre `_DriverDocsSheet`, que
muestra vehículo/ciudad/tipo de identificación + las 4 imágenes, con
aviso claro si la cuenta nunca se registró por la web (no tiene fila en
`drivers` — ej. las de flota).

**Pendiente, fuera de alcance de esta sesión:** no hay ninguna forma de
**aprobar/rechazar** a un repartidor desde Admin todavía (solo ver sus
documentos) — el campo `drivers.status` por default queda en `'aprobado'`
automático (ver nota en `~/Pagina_web_GoGo/documentos` del otro repo), sin
que nadie los revise de verdad antes de activarse.

## Correo y teléfono del dueño — dos huecos chicos corregidos — oct 2026

- **Admin nunca mostraba el correo con el que un dueño inicia sesión** (solo nombre/teléfono del dueño) — se conectó `SupabaseService.lookupAuthUser(ownerId)` (ya existía, la usa "Ver documentos" de repartidor) a `_RestaurantDetailSheet`, agregando "Correo de acceso".
- **El teléfono del restaurante se guardaba y leía solo del caché local del celular** (`SharedPreferences`), nunca de Supabase — un comentario viejo en `getRestaurantProfile` decía que la columna no existía todavía, pero sí existe (la usa Admin y el registro web). Para una cuenta registrada desde la web, sin ese caché local en el teléfono del dueño, esto se veía como "el teléfono no se guardó". Corregido: `getRestaurantProfile`/`updateRestaurantProfile` ahora leen/escriben `phone` igual que nombre/descripción/dirección.

## Registro web (restaurantes y repartidores) — bug real que rompía TODO el registro — oct 2026

**Este bug vive en el repo separado `~/Pagina_web_GoGo`** (sitio oficial,
`gogo-web-pruebas.vercel.app`), no en este — se documenta aquí también
porque bloqueaba por completo el alta de restaurantes y repartidores
reales. `src/lib/realSubmission.ts` llamaba a
`supabase.auth.refreshSession()` justo después de `signUp()`, pensando
que el JWT recién emitido no traía todavía el `app_metadata` que escribe
el trigger `sync_role_to_app_metadata` — pero se verificó decodificando
un JWT real de prueba que **sí lo trae desde el primer momento** (el
trigger es `BEFORE INSERT`, corre antes de que GoTrue arme el JWT de
respuesta). Ese `refreshSession()` no tenía nada que corregir, y encima
fallaba con `Auth session missing!`, tronando el registro justo después
de crear la cuenta — antes de subir imágenes o insertar la fila de
restaurante/rider. Se quitó esa llamada de los dos flujos
(`submitRestaurantRegistration`/`submitDriverRegistration`).

De paso se encontró que el registro web y la app de GOGO Food (este
repo) usan columnas de aprobación **completamente distintas y
desconectadas** sobre la misma tabla `restaurants`: el sitio web usa
`status` (enum `restaurant_status` propio), mientras que esta app usa
`approval_status` (la que de verdad controla la RLS de
`read_restaurants` y lo que ve Admin) — aprobar un restaurante desde un
lado no se refleja en el otro. Sin resolver todavía, pendiente de
decisión del negocio sobre cuál columna es la fuente de verdad.

## GOGO Food y GOGO Pruebas — ahora con bases de datos separadas (oct 2026)

Hasta el 7 de octubre de 2026, **todos** los flavors de iOS/Android usaban la misma base (`ymztoayxzewghbethahv`, "GOGO-Pruebas"), sin importar el nombre del build — ver la auditoría de aislamiento más abajo. Eso cambió: el flavor por default (`com.fercadi.app`, "GOGO Food") ahora apunta a su propia base, **`dlukaxbcyetcdbdjjgct`**, compilando con:

```
flutter build ios --release \
  --dart-define=SUPABASE_URL=https://dlukaxbcyetcdbdjjgct.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_MH72EXetLYHXKgklsUJ2Lw_zGLRohVY \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_... \
  --dart-define=APP_GROUP_ID=group.com.fercadi.app
```

**`APP_GROUP_ID` (nov 2026, Bloque 2):** sin este define, GOGO Food usaría por default el App Group de Pruebas (`group.com.fercadi.app.pruebas`) — el widget de seguimiento nunca encontraría los datos reales del pedido (`HomeWidget` lee del grupo equivocado, falla en silencio). El lado nativo (entitlements de `Runner` y de `GOGOTrackingWidgetExtension`) ya usa `group.com.fercadi.app` para este flavor automáticamente vía los xcconfig de Xcode — este `--dart-define` solo es para que el lado Flutter (`HomeWidget.setAppGroupId`) coincida.

**`STRIPE_PUBLISHABLE_KEY` (nov 2026):** antes `lib/core/constants.dart` traía la `pk_test_...` de Stripe escrita fija, así que un build de producción real seguía cobrando (o más bien, intentando cobrar) con la llave de pruebas sin que nadie lo notara — ningún pago real habría funcionado, pero tampoco habría dado ningún error obvio hasta que un cliente de verdad intentara pagar. Ahora sale de `String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', ...)`, con la `pk_test` como default (igual que `SUPABASE_URL`/`SUPABASE_ANON_KEY`) — GOGO Food necesita pasar la `pk_live_...` real de la cuenta de Stripe de producción al compilar, GOGO Pruebas se queda sin tocar nada.

**Admin y Flota necesitan el mismo `--dart-define`** si deben administrar la base real de GOGO Food — de lo contrario siguen apuntando a Pruebas por default (`lib/core/constants.dart`) sin que nadie lo note, y Admin queda ciego a lo que pasa en la app real. GOGO Pruebas se sigue compilando sin ningún `--dart-define` (usa el default de `constants.dart`).

`dlukaxbcyetcdbdjjgct` ya tiene las 15 migraciones de `supabase/migrations/` aplicadas, el trigger de auto-confirmación de correo, `admin@fercadi.com` creado, la Edge Function `admin-user-lookup` desplegada en su versión actual, y las políticas de Storage de los 3 buckets propios de la app puestas a mano por el dashboard (ver nota de `storage_objects_disable_rls` más abajo — no se puede por SQL). También es la base a la que ahora apunta el registro web (`~/Pagina_web_GoGo`, desplegado en `pagina-web-gogo-rho.vercel.app`).

**Un restaurante recién registrado por la web empieza con `is_open = false` a propósito** (`realSubmission.ts`, repo de la web) — para que no le salga vacío (sin platillos) a un cliente. El dueño lo prende él mismo con el switch "Abierto/Cerrado" del header en `dueno_screen.dart`. **Pendiente:** no hay ningún aviso explicándole esto al dueño nuevo — agregar mensaje en la pantalla de éxito de la web y/o cerca del switch en la app.

## Login con Google/Facebook — nombres de flavor invertidos + redirect fijo (corregido oct 2026)

Dos bugs reales en la configuración nativa de iOS, no en Dart, causaban que "Continuar con Google" fallara con "la dirección no es válida" / "no se pudo abrir la aplicación":

1. **`ios/Runner/Info.plist` e `ios/Runner/Info-Pruebas.plist` tenían el `CFBundleDisplayName` invertido** — el flavor por default (`com.fercadi.app`) decía "GOGO Pruebas" y el flavor `pruebas` (`com.fercadi.app.pruebas`) decía "GOGO Food". Ya corregido.
2. **El redirect de OAuth estaba fijo** a `fercadi://login-callback` en `login_screen.dart`, sin importar qué flavor corriera — pero cada flavor ya tenía su propio esquema en su `Info-*.plist` (`fercadi`/`fercadipruebas`/`fercadiadmin`/`fercadiflota`), pensado justo para que no choquen si hay varios instalados en el mismo teléfono. Se agregó `package_info_plus` (dependencia directa) y `_resolveRedirectUrl()` (`login_screen.dart`), que lee el bundle id real en tiempo de ejecución y arma el enlace correcto.

**Cada proyecto de Supabase necesita su propia configuración de Google OAuth** (Authentication → Providers → Google, con el mismo Client ID/Secret de Google Cloud) y su propia lista de **Redirect URLs** con los 4 esquemas — no se comparte entre proyectos aunque sea el mismo Google Cloud OAuth Client. Si se agrega un proyecto nuevo (como pasó con `dlukaxbcyetcdbdjjgct`), hay que repetir ambos pasos ahí, y agregar el nuevo `https://<project-ref>.supabase.co/auth/v1/callback` a "Authorized redirect URIs" en Google Cloud Console (mismo Client ID para todos los proyectos).

## Seguimiento del pedido — ya existía, solo se corrigieron bugs de UI/GPS

`tracking_screen.dart` (cliente) ya es una pantalla completa de seguimiento (stepper de 4 pasos + mapa en vivo) — no había que construir nada nuevo ahí. Correcciones aplicadas:

- El marcador del repartidor en el mapa del cliente ya no se muestra si el pedido está `delivered`/`cancelled` (antes seguía "parado" ahí si se reabría un pedido viejo desde el historial).
- GPS en `entrega_activa_screen.dart`/`repartidor_screen.dart`: antes solo se usaba `getPositionStream()`, que puede tardar mucho en entregar su primer punto en frío — el "arreglo" de abrir Google Maps y volver funcionaba porque eso *despierta* el GPS del sistema, no por nada que hiciera la app. Ahora se pide también un `getCurrentPosition()` puntual al iniciar (mismo efecto, sin salir de la app), y en `entrega_activa_screen.dart` aparece un botón "Reintentar" si sigue sin llegar nada después de 12s.
- Elementos encimados en el paso "En camino" (`entrega_activa_screen.dart`/`repartidor_screen.dart`): el aviso verde "Transmitiendo ubicación en vivo" se dibujaba en la misma franja que la fila de arriba (chip de paso + "Cómo llegar") — se movió más abajo. Los avisos de "Buscando ubicación"/"Dirección no encontrada" (mismo `Positioned`) ahora se apilan en una `Column` en vez de superponerse si ambos aplican a la vez.
- Panel de `entrega_activa_screen.dart` ahora es un `DraggableScrollableSheet` (mismo patrón que el sheet de "Retos" en `repartidor_plus_screen.dart`) — el repartidor puede arrastrarlo para ver más mapa o más info del pedido, con los botones de acción siempre fijos abajo.

## Auditoría de seguridad — nov 2026 (migración `20261102000000_security_hardening.sql`)

**Sin aplicar todavía a ninguna base** — aplicar primero en Pruebas (`ymztoayxzewghbethahv`), probar, y luego en GOGO Food (`dlukaxbcyetcdbdjjgct`).

- `orders`/`order_items`: se borraron las políticas del baseline que daban acceso total a cualquier autenticado (`orders_auth`, `"Cualquiera puede …"`) y lectura a anon. Cada rol ve solo lo suyo; el jefe de flota, los pedidos de sus riders. El trigger `guard_order_changes` congela todo menos `status`/`repartidor_id`/ubicación y valida transiciones por rol (cliente: `pending→cancelled`; dueño: `pending→restaurant_accepted`, cancelar; rider: tomar libre, `accepted→delivering→delivered`, soltar a `restaurant_accepted`). Admin y service_role sin restricción.
- `sync_role_to_app_metadata`: solo copia roles de autoregistro (no `admin`/`jefe_flota`) y `restaurant_id` **solo si `restaurants.owner_id` es ese usuario**. Un registro (web o app) que no llene `owner_id` deja al dueño sin restaurante en el JWT.
- Dueño solo escribe en SU restaurante/productos/categorías/banners (`owns_restaurant()`); jefe de flota solo su flota.
- `rider_stats` se suman en el servidor al pasar a `delivered` (`trg_add_rider_stats_on_delivery`); `increment_rider_stats` quedó solo para admin.
- Índice único: un solo retiro abierto por restaurante. `rider_calls` ya no lee `user_metadata`. `search_path` fijo en todas las SECURITY DEFINER.

### Pedidos y cobro con montos del servidor (migración `20261102010000_server_side_orders.sql`)

Antes el celular calculaba total/envío/descuento/precios, los insertaba directo y le pedía a Stripe cobrar el `amount` que él mandaba; además cobraba ANTES de crear el pedido. Ahora:

1. `checkout_screen.dart` → `SupabaseService.placeOrder` → RPC `place_order()`: precios de `products` (con promo por platillo % / 2x1 vigente — `CartItem.total` usa el mismo cálculo), envío con `platform_config` + coordenadas del restaurante (con 2 restaurantes: mismo `group_id`, máx. 2 piernas, recargo `multi_restaurant_surcharge` en la primera), promoción validada y marcada como usada, todo en una transacción. Insertar directo en `orders`/`order_items` quedó solo para admin.
2. Efectivo: nace `pending`. Tarjeta: nace **`awaiting_payment`** (nadie lo ve todavía).
3. Edge Function `create-payment-intent` (ahora con acciones): `create` cobra la suma de `orders.total`; `confirm` verifica con Stripe y pasa a `paid` + `pending`; `abandon` cancela pedidos y PaymentIntent. Cancelar un pedido ya creado es siempre por `reject-order` (dueño/admin, y ahora también el cliente mientras siga `pending`), que reembolsa; `cancel_my_order(uuid)` se eliminó porque nunca funcionó (los ids de pedido son texto). El webhook hace lo mismo que `confirm` y revisa que `amount_received` cuadre.
4. `send-order-notification` exige sesión y solo acepta `{orderId}` — token y texto los pone el servidor.

**Para desplegar todo esto** (en Pruebas primero): las 2 migraciones + `supabase functions deploy create-payment-intent` (SIN `--no-verify-jwt`) + `stripe-webhook` + `send-order-notification` + `reject-order`, y **publicar el build nuevo de la app al mismo tiempo** — los builds viejos insertan pedidos directo y dejan de poder pedir.

### Retiros sin doble pago (migración `20261102020000_withdrawal_safety.sql`)

- `rider-withdrawal-transfer` / `restaurant-withdrawal-transfer` (misma lógica en los dos): se pueden **reintentar** desde `en_proceso` (botón "Reintentar pago por Stripe" en Admin). El id de la transferencia se guarda en `stripe_payout_id` apenas Stripe la acepta; con eso lleno no se vuelve a transferir y el trigger `trg_block_cancel_after_transfer` impide rechazar/cancelar (antes eso liberaba el saldo para cobrarlo otra vez).
- `stripe_connect_account_id`/`stripe_onboarding_status` de las cuentas de cobro: solo los escribe el servidor (`trg_protect_payout_stripe_fields`).
- `create-premium-checkout`: URLs de regreso fijas, ya no lee `user_metadata`. `admin-user-lookup`: admin = correo `admin@fercadi.com` o `app_metadata.role`, ya no `user_metadata.role` (cualquiera se lo ponía).

Desplegar también: la migración 3 + `rider-withdrawal-transfer`, `restaurant-withdrawal-transfer`, `create-premium-checkout`, `admin-user-lookup`.

Pendiente (no hecho): políticas de Storage abiertas (se ponen a mano en el dashboard); el % de banner se sigue mostrando tachado aunque no se aplica; `main_flota.dart`/`flota_login_screen.dart` aceptan `user_metadata.role` (solo UI — RLS ya lo bloquea).

### Storage, likes, calificaciones y funciones de oct 2026 (migraciones `20261102030000` y `20261102040000`)

Aplicadas y verificadas en Pruebas (`ymztoayxzewghbethahv`) el 2 nov 2026.

- **Storage**: `product-images`, `profile-photos` y `rider-avatars` tenían "acceso total" para `public` (cualquiera, sin sesión, podía borrar o reemplazar cualquier imagen). La lectura sigue pública; escribir/borrar solo el dueño del archivo según su nombre (`storage_can_write()`: `profile_<uid>`, `profile_restaurant_<rid>`, `profile_banner_<rid>_…`, `avatars/<uid>`, `<rid>_…` en product-images; jefe de flota para fotos de sus riders; admin todo). Sí se puede por SQL (rol `postgres`), ya no hace falta el dashboard.
- Likes: se borraron `write_*_likes` (dejaban editar likes ajenos). Calificaciones: solo el cliente o el repartidor del pedido.
- `rider_calls` y `order_refund_requests` ya no aceptan INSERT directo (solo Edge Function / RPC). `legal_acceptances.accepted_at` lo pone el servidor.
- Llaves a `auth.users` sin `ON DELETE` → `SET NULL` (borrar cuenta tronaba). `delete_my_account` bloquea si hay pedidos/entregas/llamadas en curso.
- Edge Functions: `restaurant-call-rider` y `restaurant-payment-method` usan `owns_restaurant` (antes `user_metadata`: cualquiera cobraba a la tarjeta de otro restaurante); `process-order-refund` reembolsa solo el total de ESE pedido con llave de idempotencia; `rider-call-expire-check` exige ser dueño con `callId`, cancela antes de reembolsar y no marca "reembolsado" si Stripe falló.

**Bug conocido sin arreglar:** `rating_dialog.dart` llama a la Edge Function `create-tip-payment-intent`, que no existe — si el cliente elige propina, el cobro falla y su calificación no se guarda.

## Moto 3D de GOGO (repartidor) — nov 2026

`assets/models/gogo_rider.glb` (~1 MB, formato glTF binario) — repartidor en moto construido en Blender con primitivas, a partir de la ilustración oficial. Se muestra con `GogoRider3D` (`lib/widgets/gogo_rider_3d.dart`, paquete `model_viewer_plus`) en el estado vacío de `repartidor_plus_screen.dart` ("Esperando pedidos...") y `repartidor_screen.dart` ("No hay pedidos por ahora"): gira solo y se puede girar con el dedo.

- Fuente: `documentos/modelos_3d/gogo_rider.py` (script de Blender) y `gogo_rider.blend`. Para regenerar: `blender --background --factory-startup --python documentos/modelos_3d/gogo_rider.py -- <carpeta_salida>` → copia el `.glb` resultante a `assets/models/`.
- Android: `model_viewer_plus` sirve el modelo por HTTP local → `res/xml/network_security_config.xml` permite texto plano SOLO para localhost/127.0.0.1 (no usar `usesCleartextTraffic="true"`, que lo abre para todo). iOS: `io.flutter.embedded_views_preview` en `Info.plist`/`Info-Pruebas.plist`.

---

## Ronda grande de pagos/pedidos/tiendas — nov 2026 (rama `fix/seguridad-dev`)

Aplicado y probado en Pruebas (`ymztoayxzewghbethahv`); **falta aplicar a GOGO Food** (`dlukaxbcyetcdbdjjgct`) y probar en dispositivo real antes de mezclar a `dev`. Commits de esta ronda: `6c5a164` (pagos), `2297e12` (pedidos/cuentas), `ee37ecd` (repartidor), `419d2d3` (tiendas), `5c78238` (admin/dueño).

**Pagos**: `confirmCardPayment` se reintenta 3 veces con espera creciente antes de rendirse; si Stripe de verdad cobró tarde, `abandonCardPayment` ya lo detecta (antes lo ignoraba). Pedido que se queda `awaiting_payment` más de 30 min: lo resuelve solo un job nuevo (`sweep-awaiting-payments`, pg_cron cada 10 min — **Edge Function sin desplegar todavía, pendiente de confirmación explícita**, ver abajo). Pedido de 2 restaurantes: si una pierna falla (efectivo o tarjeta) se cancela la otra en vez de dejarla huérfana; cancelar desde tracking_screen cancela las dos piernas. Propinas: `create-tip-payment-intent` + tabla `order_tips` (nueva), `get_rider_balance()` ya las suma, `rating_dialog` ya no pierde la calificación si falla el cobro.

**Repartidor**: GOGO Riders y Motos Flota retoman solas una entrega `accepted`/`delivering` al reabrir la app (antes se perdía); si ya iba `delivering` retoman directo ahí, no de vuelta al restaurante. Ambas pantallas detectan si el restaurante canceló el pedido mientras el rider seguía en camino. `releaseOrderFromRider` ya tiene try/catch.

**Cuentas/pedidos**: `getActiveOrders` (panel del dueño) ya no oculta un pedido activo viejo. Cerrar sesión/borrar cuenta vacían el carrito y el cupón. `deleteRestaurant` ya no borra historial (desactiva + cancela solo lo activo) ni trona (ya no toca `product_images`, que no existe). Ganancia mostrada al repartidor: envío real menos comisión, no 15% del total. `delete_my_account` ya no bloquea por un `awaiting_payment` viejo abandonado.

**Tiendas (Apple/Google)**: se quita el permiso de push al arrancar y `UIBackgroundModes=remote-notification` (FCM no está configurado todavía); textos de ubicación/cámara/red local más claros, ya no se pide ubicación "siempre"; nuevo `PrivacyInfo.xcprivacy` (**falta agregarlo al proyecto de Xcode a mano, ver pendiente abajo**); aviso de privacidad ampliado (datos de repartidor/dueño, chat, propinas, consentimiento para CLABE); `privacy_policy.html` reescrita (ya no tiene el Gmail personal); nuevo `eliminar_cuenta.html`; `profile_screen.dart` ya enlaza privacidad/términos. `STRIPE_PUBLISHABLE_KEY` ya sale por `--dart-define` (ver sección de compilación de producción, arriba) — antes GOGO Food habría compilado con la llave de pruebas.

**Admin/dueño**: Admin "Aceptar" ya no avanza `restaurant_accepted→accepted` sin repartidor asignado; Admin "Cancelar" pide confirmación. Dueño sin restaurante encontrado: se le ofrece ir a registrar su restaurante en la página web (el registro dentro de la app ya no existe). `clearDuenoSession` ya borra también el `restaurant_id` en caché. El banner con % de descuento tachado ahora sí se cobra de verdad en `place_order` (antes solo se mostraba).

**Pendiente, necesita algo de tu parte:**
- Correr a mano en el SQL Editor de Supabase (nunca en un archivo): guardar el `service_role_key` en Vault y la URL del proyecto — ver el comentario completo en `supabase/migrations/20261103000000_sweep_awaiting_payments.sql`. Sin esto el cron job (ya desplegado) existe pero no hace nada (falla en silencio, 401).
- `lib/core/legal_content.dart`: `kLegalFullAddress` sigue en `[DOMICILIO_COMPLETO]` — falta el domicilio fiscal/real.
- Probar en dispositivo real los flujos de esta ronda (efectivo y tarjeta de 1 y 2 restaurantes, 3DS tardado, cancelar un pedido de 2 restaurantes, el rider reiniciando la app a medio reparto, borrar cuenta con un `awaiting_payment` viejo) — no se pudo probar en un iPhone real desde esta sesión.
- `git push` de la rama `fix/seguridad-dev` — pendiente, el modo automático bloqueó pasar el token por la URL del remoto (por diseño); el usuario lo sube desde su propia terminal.

## Auditoría "pendientes-tiendas" — nov 2026 (misma rama `fix/seguridad-dev`)

Segunda ronda sobre el mismo trabajo de arriba: se re-verificó cada punto contra una lista de pendientes más detallada (incluyendo un Bloque 0 nuevo, el chat de soporte) en vez de reimplementar — casi todo ya estaba hecho. Lo que de verdad cambió esta vez:

- **Chat de soporte, auditado en vivo con 2 usuarios de prueba reales** (señales HTTP contra PostgREST, no solo lectura de código): nadie puede leer/escribir el hilo ajeno ni firmar como Admin (ya estaba bien). Sí se encontró un bug real: `support_messages.user_id` referenciaba `auth.users` con `NO ACTION` (el único caso en todo el proyecto sin `CASCADE`/`SET NULL`) — cualquier cuenta que hubiera escrito a soporte quedaba IMPOSIBLE de borrar (`delete-account` tronaba en la Admin API de GoTrue). Corregido a `ON DELETE SET NULL` (mismo criterio que `order_messages`), con `get_support_threads()` excluyendo hilos de cuentas ya borradas para no mezclar varias bajo un mismo renglón. Migración `20261103060000_support_messages_user_fk.sql`, aplicada y verificada en Pruebas.
- **`sweep-awaiting-payments` ya desplegada** (con tu confirmación) — solo falta el paso de Vault de arriba para que el cron de verdad funcione.
- **`PrivacyInfo.xcprivacy` ya quedó registrado en el proyecto de Xcode** (`ios/Runner.xcodeproj/project.pbxproj`) — ya no es un paso manual pendiente, se agregó directo por código (mismo patrón que `Info.plist`: `PBXFileReference` + entrada en la fase de Resources + en el grupo `Runner`).
- Bloques 1-4 de la lista nueva: todo revisado línea por línea contra el código actual (reintentos de pago, timeout quitado, cancelación de las 2 piernas, todo-o-nada en la 2.ª pierna, propinas con calificación garantizada, banner cobrándose de verdad, detección de cancelación del rider cada 8s, resume de entrega activa, filtro de fecha del dueño, confirmaciones de Admin, permisos/privacidad de tiendas, borrado de cuenta, carrito+cupón en logout, RLS de `rider_locations`, `deleteRestaurant` sin tocar `product_images`, ganancia real del rider) — todo ya coincidía con lo pedido, sin necesidad de volver a tocarlo.

## Ronda de auditoría profunda — nov 2026 (ya mezclada en `dev`)

Esta ronda se trabajó directo en `dev` (ya no en una rama aparte) — es una tercera pasada sobre pagos/propinas/repartidor/tiendas, más estricta que las dos anteriores, con pruebas en vivo con usuarios y pedidos de prueba de verdad (siempre borrados al final) contra Pruebas (`ymztoayxzewghbethahv`). Encontró y corrigió varios bugs reales que las rondas anteriores no habían visto:

**Dinero**:
- `reject-order` confundía "pedido ya cancelado" con "ya está en preparación" por el orden de los checks — nunca fue un hueco de seguridad (no se reembolsaba dos veces de cualquier forma), solo el mensaje salía mal.
- `sweep-awaiting-payments` solo revisaba la pierna vieja de un PaymentIntent compartido — si la otra pierna ya se había confirmado por separado, los ids nunca calzaban con `metadata.orderIds` y terminaba **cancelando una pierna ya pagada de verdad**. Ahora siempre carga las dos piernas del mismo PaymentIntent, y si Stripe dice `succeeded` pero algo no cuadra, deja una alerta en vez de tocar nada.
- Propinas: la llave de idempotencia de Stripe era fija por pedido — una tarjeta rechazada dejaba el PaymentIntent en estado muerto y el cliente nunca podía reintentar con otra tarjeta. Ahora un intento `failed` genera una llave nueva. `stripe-webhook` tampoco marcaba `paid` un reintento exitoso si antes había quedado `failed`. Si el insert en `order_tips` fallaba después de cobrar en Stripe, la función regresaba el `client_secret` igual — dinero huérfano; ahora cancela el PaymentIntent y regresa error.
- `delete_my_account()` cancelaba cualquier `awaiting_payment` propio directo con un UPDATE que chocaba con `guard_order_changes` (podía tronar la función completa). Ahora uno reciente (<30 min) bloquea el borrado con mensaje claro; uno viejo se deja para que `sweep-awaiting-payments` lo resuelva de verdad.
- `deleteRestaurant` cancelaba pedidos activos con un UPDATE directo — uno pagado con tarjeta se quedaba cobrado sin reembolso. Ahora usa `reject-order` (reembolsa) o la acción `abandon` de `create-payment-intent` (que ahora también acepta que Admin la use sobre pedidos ajenos, antes exigía ser el mismo cliente).
- El total mostrado en el checkout no incluía descuentos de banner general/por-producto (solo la promo del propio platillo) — el cliente veía un precio y pagaba otro (menor). `checkout_screen.dart` ya replica la misma prioridad que `place_order()`.

**Calificaciones**: no había ninguna restricción contra calificar el mismo pedido 2 veces. Ahora hay restricción única `(order_id, is_driver)` + `submitRating` hace upsert (con su política de UPDATE nueva). `rating_dialog.dart` ya no repite toda la calificación si solo falla la propina — aparece "Reintentar propina" aparte, y si cancelas la hoja de pago ahora sí te avisa (antes se quedaba sin ningún mensaje).

**Repartidor**: en un pedido de 2 restaurantes, la vigilancia de cancelación solo revisaba una pierna — si se cancelaba la otra nadie se enteraba; si se cancelaba la vigilada, se perdía todo el viaje aunque la otra entrega siguiera viva. Ahora se vigilan las 2 por separado (`entrega_activa_screen.dart` y `repartidor_screen.dart`), con aviso del restaurante que canceló, y las transiciones de estado/ganancia ya excluyen la pierna cancelada.

**Seguridad**: `get_rider_balance()` era la única función `SECURITY DEFINER` de todo el proyecto sin ningún `search_path` fijo — hueco real (aunque no explotado). Corregida, junto con otras 4 funciones de esta misma ronda que solo tenían `search_path TO public` sin `extensions, pg_temp`.

**Privacidad**: borrar la cuenta nunca anonimizaba `orders.customer_name` (JSON con nombre/teléfono/dirección/coordenadas de entrega) — el aviso de privacidad prometía esto pero no pasaba de verdad. Ahora se anonimiza (mismas llaves, conserva solo el método de pago). Los archivos reales del repartidor en el bucket privado `identificaciones` (INE, comprobante) tampoco se borraban nunca — la fila de `drivers` sí (`FK CASCADE`), las imágenes se quedaban huérfanas. Ahora `delete-account` las borra con `service_role` antes de borrar la cuenta. **Encontrado en vivo durante la prueba**: la primera versión de la anonimización tronaba si `customer_name` no era JSON válido (nada lo garantiza) — corregido con una función que atrapa el error.

**Tiendas (iOS)**: `geolocator_apple` seguía trayendo en el binario la llamada a pedir ubicación "siempre" aunque nunca se ejecuta — el escáner estático de Apple no lo sabe y puede rechazar con ITMS-90683 de todos modos. Se agregó `BYPASS_PERMISSION_LOCATION_ALWAYS=1` en el `Podfile`. `PrivacyInfo.xcprivacy` ya declara los datos reales que se recolectan (antes solo tenía el uso de UserDefaults, sin tipos de datos) y se agregó la razón `1C8F.1` (UserDefaults de App Group, que es justo lo que usa el widget). La extensión del widget (`GOGOTrackingWidgetExtension`) nunca tuvo su propio `PrivacyInfo.xcprivacy` — Apple lo exige por separado si la extensión usa APIs de "razón requerida" por su cuenta, y sí lee UserDefaults de App Group de forma independiente.

**Probado en vivo** (usuarios/pedidos de prueba reales, siempre borrados al final): borrar cuenta con `awaiting_payment` de 5 min (bloquea con mensaje claro) y de 40 min (si se puede, y ya no truena); propina con tarjeta rechazada (`4000 0000 0000 0002`) y reintento con tarjeta buena (queda pagada y suma al saldo del rider); calificar 2 veces (solo queda 1 fila); autorización de `abandon` para Admin vs. un tercero cualquiera (el tercero sí se rechaza); build de release de iOS limpio con todos los cambios de Podfile/Xcode.

**No se pudo probar desde aquí** (necesita acceso que esta sesión no tiene):
- El escenario completo de "pedido de 2 restaurantes pagado con una pierna vieja → el sweep no la cancela" — quedó montado pero el cron sigue en 401 (ver Vault abajo), así que no corrió de verdad.
- "Admin borra un restaurante con un pedido pagado activo" de punta a punta — no hay forma de loguearse como el Admin real (`admin@fercadi.com`) desde esta sesión; se verificó por separado que un tercero sin ese correo NO puede usar el nuevo permiso de Admin.
- Cualquier flujo de UI real en un dispositivo (los dos puntos de arriba sobre repartidor/calificaciones se verificaron por código y por API, no tocando la pantalla).

**Pendiente, necesita algo de tu parte:**
- El cron de limpieza de pagos (`sweep-awaiting-payments`) sigue fallando con 401 — el secreto en Vault sigue siendo el texto de ejemplo (`PEGA_AQUÍ_TU_SERVICE_ROLE_KEY`), nunca se reemplazó por la llave real a pesar de dos intentos. Corre en el SQL Editor de Pruebas:
  ```sql
  select vault.update_secret('c70f43a2-b35a-4d19-831e-093bf8083ae4', 'TU_SERVICE_ROLE_KEY_REAL');
  ```
- `lib/core/legal_content.dart`: `kLegalFullAddress` sigue en `[DOMICILIO_COMPLETO]` — falta el domicilio fiscal real (pedido varias veces, pendiente de tu patrón).
- `git push origin dev` — este entorno no tiene forma de autenticarse con GitHub (ni token ni SSH, bloqueado también por el modo automático al intentar generar credenciales nuevas); hay que subirlo con "Sync Changes" en VS Code o desde una Terminal normal.
- Probar en un iPhone/Android real los flujos de dinero y repartidor de esta ronda antes de considerar esto listo para producción.

## Ronda "Flota, App Group, registro web, tiendas" — nov 2026

Quinta ronda sobre `dev`. Resumen de los 5 bloques:

**Bloque 1 (seguridad de roles)**: el mismo problema de Flota (confiar en
`user_metadata.role` si `app_metadata.role` venía vacío) existía en 8 lugares más
(`router.dart`, `splash_screen.dart`, login de repartidor/dueño/cliente,
`reset_password_screen.dart`) — todos corregidos. Verificado en vivo: una cuenta de
prueba se puso `role=jefe_flota` en su propio `user_metadata` sin ningún problema
(`app_metadata` se quedó intacto) — antes de este fix eso la hubiera enrutado al panel
de Flota en el celular.

**Bloque 2 (App Group por flavor)**: GOGO Food y Pruebas ya no comparten
`group.com.fercadi.app` — Pruebas tiene el suyo (`group.com.fercadi.app.pruebas`), vía
un build setting nuevo `APP_GROUP_ID` (xcconfig de Runner + build settings inline del
target del widget, que no usa xcconfig) y `$(APP_GROUP_ID)` en ambos `.entitlements`.
El widget ya no trae el grupo fijo en Swift — lo lee de una clave nueva en su
`Info.plist`. Verificado con un build de release de cada flavor (resuelven al grupo
correcto); no se pudo probar en un dispositivo real que el widget muestre el pedido.
**Pendiente tuyo**: crear en developer.apple.com el App Group `group.com.fercadi.app.pruebas`
(el otro, `group.com.fercadi.app`, ya debe existir) y habilitarlo en los App IDs
`com.fercadi.app.pruebas` y `com.fercadi.app.pruebas.GOGOTrackingWidget`.

**Bloque 3 (registro web, investigación)**: no hay ningún restaurante en Pruebas con
`owner_id` nulo que debiera tener uno — los 12 sin dueño son los de datos de muestra
originales (normal). El registro web (`realSubmission.ts`) ya llena `owner_id`
correctamente, no hace falta ningún cambio ahí. Se encontró algo aparte: 2 cuentas
distintas tienen el mismo `restaurant_id` (`r_tacosshet_szfr`) en su `user_metadata` —
solo una de las dos es la dueña real según `owner_id`, así que no es un hueco de
seguridad (RLS usa `app_metadata`, que `sync_role_to_app_metadata` solo llena si
`owner_id` coincide), pero sí es un dato inconsistente que vale la pena que alguien
revise a mano (detalle de las 2 cuentas en el chat de esta sesión, no se deja aquí por
ser datos personales reales). Sobre `status` vs `approval_status`: `status` resultó ser una columna
**muerta** — ni la app, ni la web, ni ningún trigger la leen para nada; solo existe
porque el `insert` del registro web nunca la toca y cae a su valor por default. Ya hay 3
restaurantes con `status`/`approval_status` inconsistentes entre sí
(`en_revision`/`aprobado`), más evidencia de que nadie la mantiene. **Pendiente tuyo**:
decidir si se elimina la columna `status` (recomendado, ya que `approval_status` es la
única fuente de verdad real) o se deja como está (no hace daño, solo confunde).

**Bloque 4**: aviso persistente (no de una sola vez, como el que ya existía) cerca del
switch Abierto/Cerrado del panel del dueño mientras el restaurante siga cerrado, con
texto distinto según si ya tiene platillos o no. Tema naranja del dueño.

**Bloque 5**: `documentos/tiendas/GUIA_TIENDAS.md` (Data safety/App Privacy, URLs
públicas, cuenta de revisores, capturas, keystore y builds de producción) y
`documentos/tiendas/PASO_A_PRODUCCION.md` (orden exacto, con reversa si algo sale mal).
Comparación real Pruebas vs. producción (`dlukaxbcyetcdbdjjgct`): faltan 15 migraciones
y 2 Edge Functions (`create-tip-payment-intent`, `sweep-awaiting-payments`); los
nombres de secretos ya coinciden entre ambos proyectos. Las 15 migraciones se probaron
completas en modo ensayo (`begin`/`rollback`) contra los datos reales de producción (18
pedidos, 2 restaurantes, 7 usuarios) — **sin ningún error**. No se aplicó nada en
producción.

**Aparte, encontrado al revisar**: `documentos/CLAUDE.md` es una copia muy vieja de
este archivo (de antes de agosto 2026, le faltan Morelia, las zonas nuevas, toda la
ronda de seguridad, etc.) — alguien podría confundirse leyendo esa en vez de la de la
raíz. No se tocó (no era parte de esta tarea), pero vale la pena decidir si se borra o
se actualiza.
