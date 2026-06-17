# Manual de GOGO Food — Grupo Fercadi

App de delivery para Maravatío, Michoacán. Este manual cubre el uso de la app desde la perspectiva de cada tipo de usuario (Cliente, Dueño de restaurante, Repartidor) y la administración/backend de la plataforma (Admin, base de datos, despliegue).

---

# PARTE 1 — MANUAL DE USUARIO

## 1.1 Cliente

### Iniciar sesión / Registro
- Email + contraseña (mínimo 6 caracteres)
- Google o Facebook (abre navegador, regresa a la app automáticamente)
- Modo demo: entra sin cuenta para probar la app

Según el rol guardado en la cuenta, la app te manda automáticamente a la pantalla correcta (cliente, dueño, repartidor). Los admins no pueden entrar por aquí — usan la app de administración aparte.

### Pantalla principal — Restaurantes
- Al entrar, la app detecta tu ubicación GPS. Si estás fuera de la zona de servicio (Maravatío y alrededores) verás un aviso y no podrás ver restaurantes.
- Si tienes un pedido en curso, aparece un banner abajo con acceso directo al seguimiento.
- Cada restaurante se expande al tocarlo: aparecen sus categorías (en pestañas horizontales) y, dentro, sus productos.
- Tocar un producto lo expande para ver foto grande, descripción, selector de cantidad y botón "Agregar al pedido".
- Puedes dar "like" 👍 a restaurantes y a productos individuales.
- **Regla importante:** el carrito solo puede tener productos de un restaurante a la vez. Si agregas algo de otro restaurante, se vacía el carrito anterior.

### Carrito
- Ajusta cantidades con los botones +/-. Si bajas la cantidad a 0, el producto se quita.
- Botón "Realizar pedido" lleva al checkout.

### Checkout (pagar)
1. Llena nombre, teléfono y dirección de entrega (puedes elegir una dirección guardada o marcar el punto en el mapa).
2. Elige método de pago:
   - **Efectivo** — pagas al repartidor.
   - **OXXO Pay** — pagas con referencia en tienda OXXO.
   - **Tarjeta** — pago con tarjeta vía Stripe (solo disponible en la app móvil, no en la versión web).
3. Confirmas y se crea el pedido.

### Seguimiento del pedido
- Mapa en tiempo real con tu ubicación, el restaurante y el repartidor (cuando ya fue asignado).
- Barra de progreso con 4 etapas: Pedido recibido → Restaurante preparando → Repartidor en camino → Entregado.
- Recibes notificaciones en cada cambio de estado.

### Historial de pedidos
- Lista de pedidos anteriores con fecha, restaurante, dirección y total.
- Si tienes un pedido activo, aparece marcado y puedes tocarlo para volver al seguimiento.

### Perfil
- Foto de perfil, nombre, dirección predeterminada, método de pago preferido y datos de tarjeta (guardados localmente en el dispositivo).
- Opción de "Cerrar sesión" (conserva tus datos guardados) o "Reiniciar aplicación" (borra todo: sesión, perfil, direcciones e historial — no se puede deshacer).

---

## 1.2 Dueño de Restaurante

### Acceso
Te registras desde la pantalla de login eligiendo la opción de restaurante, o inicias sesión si ya tienes cuenta. Al registrar tu restaurante por primera vez, completas: datos del restaurante (nombre, descripción, teléfono, dirección — puedes detectar tu ubicación por GPS), tus datos como propietario y tu contraseña.

### Panel del Dueño
El panel naranja tiene 4 secciones (pestañas inferiores):

**Dashboard** — ventas del día, número de pedidos, total de productos, tiempo promedio de entrega, y un resumen visual de en qué estado están tus pedidos (pendiente / en camino / entregado / cancelado).

**Pedidos** — lista en tiempo real de los pedidos que te llegan. Puedes filtrar por estado. Al recibir un pedido nuevo, suena una alerta y aparece un aviso emergente. Desde aquí:
- Aceptas el pedido (pasa de "pendiente" a "aceptado").
- Cambias el estado conforme avanza (en camino, entregado) o lo cancelas.
- Ves los datos del cliente: nombre, teléfono, dirección y los productos pedidos.

**Menú** — gestión de tu catálogo:
- Navega por categorías (pestañas horizontales).
- Agrega productos nuevos (nombre, descripción, precio, foto, categoría).
- Edita o elimina productos existentes.
- Activa/desactiva la disponibilidad de un producto con un switch — al desactivarlo, deja de aparecer para los clientes inmediatamente.

**Perfil del restaurante** — edita nombre, descripción, teléfono, dirección, foto/logo, y el switch general de "Abierto/Cerrado" (cuando lo cierras, tu restaurante deja de aparecer en la app del cliente).

---

## 1.3 Repartidor

### Acceso
Te registras desde la pantalla de login eligiendo la opción de repartidor (nombre, email, contraseña), o inicias sesión si ya tienes cuenta.

### Panel del Repartidor
- Switch de **Disponibilidad**: cuando está en "Disponible" recibes pedidos nuevos; en "No disponible" no te llegan pedidos nuevos (pero los que ya tienes asignados se mantienen).
- Mapa en tiempo real con tu posición GPS — se transmite automáticamente para que el cliente te vea en su pantalla de seguimiento.
- Lista de pedidos disponibles para aceptar: restaurante, cliente, dirección, productos, total.
- Estadísticas del día: número de entregas y ganancia acumulada.

### Flujo de una entrega
1. **Aceptar** el pedido — queda asignado a ti, el cliente recibe notificación.
2. Ir al restaurante a recoger — marcas el pedido como "en camino".
3. Llevarlo al cliente y marcarlo como **entregado** al llegar.
4. Se suma a tus estadísticas del día y vuelves a ver la lista de pedidos disponibles.

### Datos bancarios
En tu perfil puedes guardar tu CLABE interbancaria (18 dígitos) para recibir tus pagos.

---

# PARTE 2 — MANUAL DE BACKEND / ADMINISTRACIÓN

## 2.1 App de Administración

La administración corre como **una app aparte** (`lib/main_admin.dart`), con su propio login. Solo el correo `admin@fercadi.com` puede entrar — cualquier otro correo es rechazado aunque la contraseña sea correcta.

### Panel de Admin
4 secciones:

**Dashboard global** — ventas totales del día, pedidos totales, entregados, número de restaurantes registrados, y un resumen visual del estado de todos los pedidos de la plataforma.

**Todos los pedidos** — vista de cada pedido de cada restaurante, con filtro por estado. El admin puede cambiar el estado de cualquier pedido o cancelarlo, sin restricción de a qué restaurante pertenezca.

**Gestión de restaurantes** — lista de todos los restaurantes con su dueño, estado (abierto/cerrado), número de productos y rating. Desde aquí el admin puede:
- Editar cualquier dato del restaurante.
- Cerrarlo temporalmente.
- **Eliminarlo** — esto borra en cascada sus productos, categorías y pedidos asociados. Se hace con `SupabaseService.deleteRestaurant(id)`. Es una acción irreversible, hay que confirmar con cuidado antes de usarla.

**Usuarios y repartidores** — listado de repartidores (con sus estadísticas de entregas y ganancias) y de clientes (con su historial de gasto). Permite suspender o eliminar cuentas si es necesario.

## 2.2 Base de datos (Supabase)

Tablas principales:

| Tabla | Para qué sirve |
|---|---|
| `restaurants` | Catálogo de restaurantes (nombre, dirección, dueño, abierto/cerrado, rating) |
| `categories` | Categorías de productos por restaurante |
| `products` | Productos/platillos (precio, disponibilidad, imagen) |
| `product_images` | Imágenes asociadas a productos |
| `orders` | Pedidos (cliente, total, estado, método de pago, ubicación) |
| `order_items` | Detalle de productos dentro de cada pedido |
| `product_likes` | "Me gusta" de productos por usuario |

Seguridad: **RLS (Row Level Security) activa** en todas las tablas. Los permisos se basan en el rol guardado en el JWT (`auth.jwt() -> 'user_metadata' ->> 'role'`):
- Cliente: solo ve y crea sus propios pedidos.
- Dueño: solo ve/edita los datos de su propio restaurante.
- Repartidor: ve pedidos pendientes y los que tiene asignados.
- Admin: acceso total.

El rol se asigna al registrarse (`user_metadata.role` en Supabase Auth) y se replica en el dispositivo vía `SharedPreferences` para que la sesión persista sin tener que volver a iniciar sesión cada vez que se abre la app.

## 2.3 Pagos (Stripe)

El pago con tarjeta usa Stripe a través de una Edge Function de Supabase (`create-payment-intent`) que genera el `clientSecret`, y el SDK `flutter_stripe` muestra la hoja de pago nativa. Solo funciona en la app móvil (Android/iOS) — en la versión web esa opción no está disponible y se ofrece efectivo u OXXO en su lugar.

## 2.4 Notificaciones

- **Locales**: sonido y vibración para avisos dentro de la misma app (nuevo pedido para el dueño, cambios de estado para el cliente).
- **Firebase Cloud Messaging (FCM)**: permite notificaciones push aunque la app esté cerrada. El token del cliente se guarda en el pedido (`client_fcm_token`) para poder notificarle cuando cambia el estado.

## 2.5 Mapas y ubicación

- El mapa interactivo (`google_maps_flutter`) solo funciona en la app móvil — en web no está soportado, así que la dirección se captura como texto libre.
- El repartidor transmite su posición GPS en tiempo real; el cliente la recibe consultando el pedido cada pocos segundos desde la pantalla de seguimiento.
- Zona de servicio: centro en Maravatío (19.8969° N, 100.4447° W), radio de 30 km. Fuera de ese radio la app no muestra restaurantes.

## 2.6 Despliegue

**Web** (Vercel):
```powershell
flutter build web --release
Copy-Item vercel.json build/web/vercel.json -Force
cd build/web
npx vercel --prod --archive=tgz
```

**Android** — genera los dos APKs (cliente y admin) con un solo comando:
```powershell
.\build_apks.ps1
# build\GOGOFood.apk (app cliente/dueño/repartidor)
# build\GOGOAdmin.apk (app de administración)
```

**iOS** — se compila vía CI (GitHub Actions o Codemagic) porque no hay Mac disponible localmente; el resultado es un IPA sin firma para instalar con AltStore/Sideloadly mientras no haya cuenta de Apple Developer.

## 2.7 Pendientes conocidos antes de publicar en tiendas

- Cambiar bundle ID de `com.example.landing_test` a `com.fercadi.gogofood`.
- Crear keystore para firmar el APK/AAB de Google Play.
- Cuenta de Google Play Console ($25 USD único pago) y Apple Developer ($99 USD/año).
- Icono 1024×1024 sin transparencia y capturas de pantalla para ambas tiendas.
