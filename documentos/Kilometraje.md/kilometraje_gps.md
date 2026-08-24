# Documentación: Kilometraje GPS y APIs — GOGO Food Rider

## ¿Qué hace el sistema?

Cuando un repartidor (con rol `repartidor_plus`) abre su pantalla, la app empieza a escuchar su posición GPS en tiempo real. Cada vez que el GPS detecta que el rider se movió cierta distancia, se suma ese tramo al contador de kilómetros del día. Con eso se calcula cuánto gastó en gasolina y cuánto ganó **en neto** descontando ese costo.

---

## ¿Dónde está el código?

| Archivo | Línea aprox. | Qué contiene |
|---|---|---|
| `lib/screens/repartidor_plus_screen.dart` | ~97 | Función `_startGPS()` — arranca el stream GPS |
| `lib/screens/repartidor_plus_screen.dart` | ~77 | Función `_fetchGasPrice()` — obtiene precio de gasolina |
| `lib/screens/repartidor_plus_screen.dart` | ~45 | Getter `_costoGasHoy` — calcula el costo |
| `lib/screens/repartidor_plus_screen.dart` | ~46 | Getter `_gananciaNeta` — calcula la ganancia neta |

---

## El parámetro que controla cada cuántos metros se actualiza

Dentro de `_startGPS()` está esta línea:

```dart
locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10   // ← AQUÍ se cambia
),
```

### ¿Qué significa `distanceFilter`?

`distanceFilter` es el **mínimo de metros que el rider tiene que moverse** para que el GPS registre una nueva posición y sume distancia al contador.

| Valor | Comportamiento |
|---|---|
| `distanceFilter: 10` | Se actualiza cada **10 metros** de movimiento |
| `distanceFilter: 20` | Se actualiza cada **20 metros** de movimiento |
| `distanceFilter: 50` | Se actualiza cada **50 metros** de movimiento |
| `distanceFilter: 0`  | Se actualiza **constantemente** (drena batería) |

### ¿Se puede cambiar de 10 a 20?

**Sí, sin problema.** Solo hay que cambiar el número en esa línea. El cálculo de distancia no cambia — la app sigue sumando correctamente los metros entre cada punto registrado. La única diferencia es que con 20 el GPS "muestrea" menos seguido, lo que:

- ✅ Gasta menos batería
- ✅ Consume menos datos de localización
- ⚠️ Puede perder trayectos cortos o en zigzag (por ejemplo entregar y regresar en 15 metros no lo registraría)

### Cómo hacer el cambio

Abre el archivo:

```
lib/screens/repartidor_plus_screen.dart
```

Busca la función `_startGPS()` y cambia el valor:

```dart
// Antes (10 metros):
distanceFilter: 10

// Después (20 metros):
distanceFilter: 20
```

---

## Rendimiento de la moto (km por litro)

El cálculo del costo de gasolina usa el rendimiento de la moto del rider:

```
Costo de gasolina = (km recorridos ÷ rendimiento) × precio del litro
Ganancia neta     = dinero acumulado − costo de gasolina
```

### Valor por defecto

El rendimiento por defecto es **40 km/L**, definido aquí:

```dart
// lib/screens/repartidor_plus_screen.dart ~línea 41
double _rendimiento = 40.0;  // km por litro, editable en perfil
```

Si quieres cambiar el default (para todos los riders nuevos que no hayan guardado el suyo), cambia ese número.

### El rider puede cambiarlo desde la app

En la pantalla del rider, al tocar su foto de perfil se abre un sheet que tiene el campo **"Rendimiento moto (km/L)"**. El rider lo puede editar y al guardar se graba en su `user_metadata` en Supabase, por lo que persiste entre sesiones.

---

## Precio de gasolina (API CRE)

Al cargar la pantalla se hace una llamada automática a la API pública de la Comisión Reguladora de Energía:

```
https://publicacionexterna.azurewebsites.net/publicaciones/prices
```

La app descarga todos los precios de gasolineras en México, filtra las de tipo `regular` (Magna) y calcula el promedio nacional. Ese precio se usa para el cálculo del día.

- Si la API falla o hay sin señal → se usa el precio default de `$23.50/L`
- El precio mostrado en la tarjeta de stats se actualiza automáticamente cada vez que el rider abre la app
- En la versión **web** la API puede no funcionar por restricciones CORS del navegador — en ese caso también queda el default

---

## Resumen visual del flujo

```
Rider abre pantalla
        │
        ├─── Fetch CRE API ──→ precio Magna promedio ($23.XX/L)
        │
        └─── Start GPS stream
                  │
                  │  cada X metros (distanceFilter)
                  ▼
             nueva posición
                  │
                  └─→ suma distancia al contador _kmHoy
                                  │
                                  ▼
                    Costo gas = (km ÷ rendimiento) × precio
                    Ganancia neta = dinero − costo gas
                                  │
                                  ▼
                          se muestra en la tarjeta azul
```

---

## Tabla de cambios rápidos

| ¿Qué quieres cambiar? | Archivo | Qué buscar |
|---|---|---|
| Metros entre actualizaciones GPS | `repartidor_plus_screen.dart` | `distanceFilter:` |
| Rendimiento default de la moto | `repartidor_plus_screen.dart` | `double _rendimiento = 40.0;` |
| Precio de gasolina default (fallback) | `repartidor_plus_screen.dart` | `double _precioGas = 23.50;` |
| URL de la API de precios CRE | `repartidor_plus_screen.dart` | `publicacionexterna.azurewebsites.net` |

---

---

# APIs utilizadas en GOGO Food

Esta sección documenta todas las APIs externas que usa la app, para qué sirven, dónde se llaman y qué pasa si fallan.

---

## 1. Supabase

**Qué es:** El backend principal de la app. Maneja la base de datos, autenticación de usuarios, almacenamiento de archivos y suscripciones en tiempo real.

**URL base:** `https://mmjzyqvjdwhzefbaiums.supabase.co`

**Dónde se configura:**
```
lib/core/constants.dart        ← URL y anon key
lib/services/supabase_service.dart  ← todas las queries
```

**Para qué lo usamos:**

| Función | Qué hace |
|---|---|
| **Auth** | Login con email/contraseña, registro, sesión persistente, roles en `user_metadata` |
| **Database** | Tablas de restaurantes, productos, pedidos, items, likes, flota |
| **Storage** | Avatares de riders (bucket `rider-avatars`), imágenes de productos |
| **Realtime** | Actualización automática de pedidos (sin recargar) en panel dueño y repartidor |
| **Edge Functions** | Crear el `PaymentIntent` de Stripe desde el servidor |

**Admin API (creación de usuarios sin confirmar email):**

```dart
// lib/services/supabase_service.dart
POST https://mmjzyqvjdwhzefbaiums.supabase.co/auth/v1/admin/users
Authorization: Bearer SERVICE_ROLE_KEY
```

Esto lo usa el jefe de flota para crear cuentas de repartidores directamente desde la app, sin que les llegue correo de confirmación. Requiere la `service_role_key` (no la `anon_key`).

**Si falla:** La app muestra snackbar de error. Sin Supabase no hay login, pedidos ni datos — la app entra en modo mock si `useMock = true` en `supabase_service.dart`.

---

## 2. Stripe

**Qué es:** Procesador de pagos con tarjeta de crédito/débito.

**Dónde se configura:**
```
lib/core/constants.dart     ← stripePublishableKey (pk_test_...)
lib/main.dart               ← Stripe.publishableKey = ...
lib/screens/checkout_screen.dart   ← _payWithStripe()
lib/screens/rating_dialog.dart     ← propinas con tarjeta
```

**Flujo de pago:**
```
Cliente elige "Tarjeta"
        │
        ▼
App llama Supabase Edge Function
        │  (la Edge Function tiene la SECRET_KEY de Stripe,
        │   nunca se expone en la app)
        ▼
Supabase Edge Function crea PaymentIntent
        │  → regresa clientSecret
        ▼
App abre PaymentSheet de Stripe
(formulario nativo de tarjeta)
        │
        ▼
Stripe cobra → confirma pago → se crea el pedido
```

**Clave pública actual:** `pk_test_51ThAd...` (modo prueba / sandbox)

**Para producción** hay que cambiar a `pk_live_...` en `constants.dart` y actualizar la Edge Function con `sk_live_...`.

**Si falla:** Se muestra error de Stripe al usuario. El pedido no se crea si el pago no se confirma.

---

## 3. CRE — Comisión Reguladora de Energía

**Qué es:** API pública del gobierno mexicano con precios de gasolineras en todo México, actualizada diariamente.

**URL:**
```
https://publicacionexterna.azurewebsites.net/publicaciones/prices
```

**Dónde se llama:**
```
lib/screens/repartidor_plus_screen.dart  →  _fetchGasPrice()
```

**Qué devuelve:** XML con miles de gasolineras y sus precios (`regular`, `premium`, `diesel`). La app filtra solo `regular` (Magna) y calcula el promedio nacional.

**Si falla:** La app usa el precio default de `$23.50/L` definido en `double _precioGas = 23.50`. En web puede fallar siempre por CORS del navegador.

**No requiere API key** — es pública y gratuita.

---

## 4. Nominatim / OpenStreetMap — Geocoding

**Qué es:** API gratuita de OpenStreetMap para convertir entre coordenadas GPS y direcciones de texto (y viceversa).

**URLs:**
```
https://nominatim.openstreetmap.org/search   ← dirección → coordenadas
https://nominatim.openstreetmap.org/reverse  ← coordenadas → dirección
```

**Dónde se llama:**

| Archivo | Uso |
|---|---|
| `lib/services/location_service.dart` | Convierte dirección del cliente a coords para mostrar en mapa |
| `lib/services/geocoding_service.dart` | Geocoding genérico reutilizable |
| `lib/screens/registro_restaurante_screen.dart` | Convierte la dirección del restaurante nuevo a coords |

**Límite de uso:** Nominatim es gratuita pero tiene límite de **1 petición por segundo**. Para producción con muchos usuarios conviene mover a Google Maps Geocoding API (de pago) o un servidor propio con Nominatim.

**Si falla:** El mapa no muestra el pin de la dirección. El pedido igual se puede crear con dirección en texto.

---

## 5. OSRM — Cálculo de ruta

**Qué es:** Open Source Routing Machine, servidor público para calcular rutas de manejo entre dos puntos.

**URL:**
```
https://router.project-osrm.org/route/v1/driving/{lon1},{lat1};{lon2},{lat2}
```

**Dónde se llama:**
```
lib/screens/repartidor_screen.dart   ← calcula la ruta al cliente en el mapa
```

**Qué devuelve:** JSON con la ruta en formato polilínea codificada (polyline), distancia en metros y duración estimada.

**Si falla:** El mapa del repartidor no dibuja la línea de ruta, pero sigue funcionando el GPS y los marcadores de origen/destino.

**No requiere API key** — servidor público gratuito. Para producción con mucho tráfico se puede montar un servidor OSRM propio.

---

## 6. OpenStreetMap Tiles — Mapa visual

**Qué es:** Los "tiles" (cuadritos de imagen) que forman el mapa visual que se ve en pantalla.

**URL:**
```
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

**Dónde se usa:**
```
lib/screens/repartidor_screen.dart   ← mapa del repartidor
lib/screens/flota_screen.dart        ← mapa del jefe de flota
```

**No requiere API key.** Gratis para uso razonable. Si la app escala mucho conviene usar Mapbox o Google Maps para evitar el rate limit de OSM.

---

## 7. Google OAuth

**Qué es:** Login con cuenta de Google, manejado por Supabase Auth como intermediario.

**Dónde se llama:**
```
lib/screens/login_screen.dart  →  _signInWithGoogle()
```

**Flujo:** La app abre el navegador de Google → el usuario autoriza → Google redirige de vuelta con un token → Supabase registra o autentica al usuario → la app navega a la pantalla del rol correspondiente.

**Requiere configuración en:** Supabase Dashboard → Authentication → Providers → Google (Client ID y Secret de Google Cloud Console).

---

## 8. Facebook OAuth

**Qué es:** Login con cuenta de Facebook, también manejado por Supabase Auth.

**Dónde se llama:**
```
lib/screens/login_screen.dart  →  _signInWithFacebook()
```

**Mismo flujo que Google.** Requiere configuración en Supabase Dashboard → Providers → Facebook (App ID y Secret de Meta for Developers).

---

## 9. Firebase FCM — Notificaciones push (pendiente)

**Qué es:** Firebase Cloud Messaging para enviar notificaciones cuando la app está cerrada.

**Estado actual:** El archivo `lib/services/fcm_service.dart` existe como placeholder/stub pero **no está integrado activamente**. La app guarda `client_fcm_token` en la tabla de pedidos pero el envío real de notificaciones está comentado.

**Para activarlo habría que:**
1. Crear proyecto en `console.firebase.google.com`
2. Agregar `firebase_core` y `firebase_messaging` al `pubspec.yaml`
3. Descomentar el código en `fcm_service.dart`
4. Agregar los archivos `google-services.json` (Android) y `GoogleService-Info.plist` (iOS)

---

## 10. Google Maps / Google Maps Dir (enlaces externos)

**Qué es:** No es una API integrada, sino links que abren la app de Google Maps instalada en el dispositivo.

**URLs:**
```
https://maps.google.com/           ← abrir mapa en general
https://www.google.com/maps/dir/   ← abrir ruta de A a B
```

**Dónde se usan:**
```
lib/screens/flota_screen.dart      ← ver rider en Google Maps
lib/screens/repartidor_screen.dart ← abrir ruta al cliente en Google Maps
```

No requieren API key. Solo abren el navegador o la app de Maps.

---

## Resumen de todas las APIs

| API | Uso | Requiere key | Costo | Si falla |
|---|---|---|---|---|
| **Supabase** | BD, Auth, Storage, Realtime | Sí (anon + service_role) | Gratis hasta cierto límite | App no funciona (sin datos) |
| **Stripe** | Pagos con tarjeta | Sí (pk + sk) | % por transacción | Pago no se procesa |
| **CRE** | Precio gasolina Magna | No | Gratis | Usa precio default $23.50 |
| **Nominatim OSM** | Geocoding de direcciones | No | Gratis (1 req/seg) | Pin de mapa no aparece |
| **OSRM** | Ruta de manejo en mapa | No | Gratis | Línea de ruta no se dibuja |
| **OSM Tiles** | Imágenes del mapa | No | Gratis | Mapa aparece en blanco |
| **Google OAuth** | Login con Google | Sí (Google Cloud) | Gratis | No se puede entrar con Google |
| **Facebook OAuth** | Login con Facebook | Sí (Meta) | Gratis | No se puede entrar con Facebook |
| **FCM Firebase** | Notificaciones push | Sí (Firebase) | Gratis hasta 1M/mes | Notificaciones no llegan |
| **Google Maps links** | Abrir Maps externo | No | Gratis | Link no abre nada |
