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

## Seguimiento del pedido — ya existía, solo se corrigieron bugs de UI/GPS

`tracking_screen.dart` (cliente) ya es una pantalla completa de seguimiento (stepper de 4 pasos + mapa en vivo) — no había que construir nada nuevo ahí. Correcciones aplicadas:

- El marcador del repartidor en el mapa del cliente ya no se muestra si el pedido está `delivered`/`cancelled` (antes seguía "parado" ahí si se reabría un pedido viejo desde el historial).
- GPS en `entrega_activa_screen.dart`/`repartidor_screen.dart`: antes solo se usaba `getPositionStream()`, que puede tardar mucho en entregar su primer punto en frío — el "arreglo" de abrir Google Maps y volver funcionaba porque eso *despierta* el GPS del sistema, no por nada que hiciera la app. Ahora se pide también un `getCurrentPosition()` puntual al iniciar (mismo efecto, sin salir de la app), y en `entrega_activa_screen.dart` aparece un botón "Reintentar" si sigue sin llegar nada después de 12s.
- Elementos encimados en el paso "En camino" (`entrega_activa_screen.dart`/`repartidor_screen.dart`): el aviso verde "Transmitiendo ubicación en vivo" se dibujaba en la misma franja que la fila de arriba (chip de paso + "Cómo llegar") — se movió más abajo. Los avisos de "Buscando ubicación"/"Dirección no encontrada" (mismo `Positioned`) ahora se apilan en una `Column` en vez de superponerse si ambos aplican a la vez.
- Panel de `entrega_activa_screen.dart` ahora es un `DraggableScrollableSheet` (mismo patrón que el sheet de "Retos" en `repartidor_plus_screen.dart`) — el repartidor puede arrastrarlo para ver más mapa o más info del pedido, con los botones de acción siempre fijos abajo.
