# Manual de Backend — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿Qué es el "backend" de GOGO Food?

El backend es todo lo que corre en los servidores — la base de datos, los usuarios, las imágenes y la lógica de negocio que no debe correr en el teléfono del usuario. En GOGO Food usamos **Supabase** como plataforma backend completa, lo que significa que no hay que administrar servidores manualmente.

---

## 1. Acceso al Panel de Supabase

**URL:** [supabase.com](https://supabase.com) → iniciar sesión → proyecto GOGO Food

El panel tiene estas secciones importantes:

| Sección | Para qué |
|---|---|
| **Table Editor** | Ver, editar y agregar datos directamente |
| **SQL Editor** | Ejecutar consultas SQL avanzadas |
| **Authentication** | Usuarios, roles, contraseñas |
| **Storage** | Imágenes de productos y restaurantes |
| **Edge Functions** | Lógica de servidor (Stripe, notificaciones) |
| **Logs** | Ver errores en tiempo real |
| **Settings → API** | Claves de conexión (URL y anon key) |

---

## 2. Base de Datos — Estructura Completa

### Tabla `restaurants`

Cada restaurante registrado en la app.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria (auto-generada) |
| `name` | text | Nombre del restaurante |
| `description` | text | Descripción breve |
| `address` | text | Dirección de texto libre |
| `image_url` | text | URL de la foto principal |
| `owner_id` | uuid | ID del usuario dueño (FK → auth.users) |
| `is_active` | boolean | Si aparece en la app del cliente |
| `created_at` | timestamptz | Fecha de registro |
| `phone` | text | Teléfono de contacto |

### Tabla `categories`

Categorías del menú por restaurante (Tacos, Bebidas, Postres, etc.)

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `restaurant_id` | uuid | FK → restaurants |
| `name` | text | Nombre de la categoría |
| `sort_order` | integer | Orden de aparición en el menú |

### Tabla `products`

Cada producto/plato del menú.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `restaurant_id` | uuid | FK → restaurants |
| `category_id` | uuid | FK → categories |
| `name` | text | Nombre del producto |
| `description` | text | Descripción (ingredientes, etc.) |
| `price` | numeric | Precio en MXN |
| `image_url` | text | Foto principal |
| `is_available` | boolean | Si está disponible para pedir |
| `promo_label` | text | Texto de promoción (ej. "2x1") |

### Tabla `product_images`

Imágenes adicionales por producto (galería).

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `product_id` | uuid | FK → products |
| `image_url` | text | URL de la imagen adicional |
| `sort_order` | integer | Orden en la galería |

### Tabla `orders`

Cada pedido realizado.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `restaurant_id` | uuid | FK → restaurants |
| `customer_id` | uuid | FK → auth.users (cliente) |
| `rider_id` | uuid | FK → auth.users (repartidor, puede ser null) |
| `status` | text | `pending`, `accepted`, `delivering`, `delivered`, `cancelled` |
| `total` | numeric | Total del pedido en MXN |
| `delivery_address` | text | Dirección de entrega |
| `payment_method` | text | `cash` o `card` |
| `payment_status` | text | `pending`, `paid`, `failed` |
| `notes` | text | Notas del cliente |
| `created_at` | timestamptz | Cuándo se hizo el pedido |
| `delivered_at` | timestamptz | Cuándo se entregó |

### Tabla `order_items`

Los productos dentro de cada pedido.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `order_id` | uuid | FK → orders |
| `product_id` | uuid | FK → products |
| `quantity` | integer | Cantidad pedida |
| `price` | numeric | Precio al momento del pedido (histórico) |

### Tabla `product_likes`

Likes de usuarios a restaurantes.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `user_id` | uuid | FK → auth.users |
| `restaurant_id` | uuid | FK → restaurants |
| `created_at` | timestamptz | Cuándo se dio el like |

### Tabla `restaurant_banners`

Banners promocionales en el panel del dueño.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `restaurant_id` | uuid | FK → restaurants |
| `image_url` | text | URL de la imagen del banner |
| `sort_order` | integer | Orden de aparición |

### Tabla `flota_members`

Relación entre un jefe de flota y sus repartidores.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `jefe_id` | uuid | FK → auth.users (jefe_flota) |
| `rider_id` | uuid | FK → auth.users (repartidor) |
| `created_at` | timestamptz | Cuándo se vinculó |

### Tabla `rider_locations`

Ubicación GPS en tiempo real de los repartidores.

| Columna | Tipo | Descripción |
|---|---|---|
| `id` | uuid | Clave primaria |
| `rider_id` | uuid | FK → auth.users (único — upsert) |
| `lat` | float8 | Latitud GPS |
| `lng` | float8 | Longitud GPS |
| `last_seen` | timestamptz | Cuándo fue la última actualización |

---

## 3. Autenticación y Roles (Supabase Auth)

### Cómo se crean los usuarios

Hay tres formas de registrarse:

1. **Cliente:** Se registra desde la app con email y contraseña
2. **Dueño de restaurante:** Se registra en `/registro-restaurante` — la app le asigna el rol `dueno` automáticamente
3. **Repartidor:** Se registra en `/registro-repartidor`
4. **Admin/Jefe de flota:** Se crea manualmente desde el panel de Supabase

### Asignar roles desde el panel de Supabase

1. Ir a **Authentication → Users**
2. Clic en el usuario
3. En la columna "Raw User Meta Data", editar el JSON:

```json
{
  "role": "jefe_flota"
}
```

O con SQL (más rápido):

```sql
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"role": "jefe_flota"}'::jsonb
WHERE email = 'eloy@eloy.com';
```

### Roles disponibles

| Rol | Valor en metadata | Acceso |
|---|---|---|
| Cliente | `cliente` (o sin rol) | Restaurantes, carrito, pedidos propios |
| Dueño | `dueno` | Panel naranja — su restaurante |
| Repartidor | `repartidor` | Pedidos asignados, GPS |
| Jefe de flota | `jefe_flota` | Panel de flota con mapa |
| Admin | `admin` | Todo sin restricciones |

---

## 4. Row Level Security (RLS)

RLS es el sistema de permisos de la base de datos. Cada tabla tiene políticas que definen quién puede leer o escribir.

### Lógica general

```sql
-- Cómo se verifica el rol en una política de Supabase
(auth.jwt() -> 'user_metadata' ->> 'role') = 'dueno'
```

### Ejemplos de políticas activas

**Los clientes solo ven sus propios pedidos:**
```sql
CREATE POLICY "clientes ven sus pedidos"
ON orders FOR SELECT
USING (auth.uid() = customer_id);
```

**El dueño solo ve los pedidos de SU restaurante:**
```sql
CREATE POLICY "dueno ve pedidos de su restaurante"
ON orders FOR SELECT
USING (
  restaurant_id IN (
    SELECT id FROM restaurants WHERE owner_id = auth.uid()
  )
);
```

**El admin ve todo:**
```sql
CREATE POLICY "admin acceso total"
ON orders FOR ALL
USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
```

### ¿Cómo ver las políticas?

En el panel de Supabase: **Database → Tables → (seleccionar tabla) → RLS Policies**

---

## 5. Storage (Almacenamiento de Imágenes)

Las imágenes se guardan en Supabase Storage, en buckets (carpetas):

| Bucket | Qué contiene |
|---|---|
| `product-images` | Fotos de los productos del menú |
| `restaurant-images` | Fotos principales de restaurantes |
| `banners` | Banners promocionales del panel del dueño |

### Subir una imagen desde Flutter

```dart
final file = File(imagePath);
final bytes = await file.readAsBytes();
final path = 'restaurants/$restaurantId/banner_${DateTime.now().millisecondsSinceEpoch}.jpg';

await Supabase.instance.client.storage
    .from('banners')
    .uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: 'image/jpeg'));

final publicUrl = Supabase.instance.client.storage
    .from('banners').getPublicUrl(path);
```

### ¿Las imágenes son públicas o privadas?

Por ahora todos los buckets son **públicos** — cualquiera con la URL puede ver la imagen. Esto es intencional para que las fotos de productos funcionen en la app sin autenticación.

---

## 6. Edge Functions (Lógica de Servidor)

Las Edge Functions son código TypeScript que corre en los servidores de Supabase. Se usan para cosas que no deben hacerse en el teléfono del cliente.

### Edge Functions activas

| Nombre | Para qué |
|---|---|
| `create-payment-intent` | Crea un cobro en Stripe desde el servidor |

### Cómo ver los logs de una Edge Function

Supabase Dashboard → **Edge Functions** → nombre de la función → **Logs**

Si hay errores de Stripe, aparecen aquí.

### Variables de entorno de las Edge Functions

Supabase Dashboard → **Edge Functions** → **Secrets**:

| Variable | Valor |
|---|---|
| `STRIPE_SECRET_KEY` | `sk_test_...` o `sk_live_...` |

### Deploy de una Edge Function actualizada

```bash
# Requiere Supabase CLI instalado
supabase functions deploy create-payment-intent --project-ref <tu-project-ref>
```

---

## 7. Tiempo Real (Realtime)

Supabase tiene un sistema de suscripciones en tiempo real. Se usa para que el cliente vea el mapa con la ubicación del repartidor actualizándose en vivo.

### Cómo funciona en el panel de tracking del cliente

```dart
// tracking_screen.dart
_locationSub = Supabase.instance.client
    .from('orders')
    .stream(primaryKey: ['id'])
    .eq('id', orderId)
    .listen((data) {
  if (data.isNotEmpty) {
    final order = data.first;
    setState(() {
      _riderLat = order['rider_lat'];
      _riderLng = order['rider_lng'];
    });
  }
});
```

---

## 8. Cómo Crear un Nuevo Usuario desde el Panel

### Usuario cliente normal

1. El usuario se registra solo desde la app — no hay que hacer nada

### Dueño de restaurante

1. **Authentication → Users → Invite user** (o que se registre por la app)
2. Editar `raw_user_meta_data`:
   ```json
   { "role": "dueno" }
   ```
3. Crear su restaurante desde la tabla `restaurants` con `owner_id = <uuid del usuario>`

### Jefe de flota

1. **Authentication → Users → Add user**
2. Ingresar email y contraseña
3. Agregar en metadata: `{ "role": "jefe_flota" }`
4. En la tabla `flota_members`, vincular sus repartidores:
   ```sql
   INSERT INTO flota_members (jefe_id, rider_id)
   VALUES ('uuid-del-jefe', 'uuid-del-rider');
   ```

---

## 9. Operaciones Comunes en SQL Editor

### Ver todos los pedidos de hoy

```sql
SELECT o.id, o.status, o.total, o.payment_method, r.name as restaurante
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.id
WHERE o.created_at >= CURRENT_DATE
ORDER BY o.created_at DESC;
```

### Ver los repartidores online (activos en últimos 5 min)

```sql
SELECT u.email, rl.lat, rl.lng, rl.last_seen
FROM rider_locations rl
JOIN auth.users u ON rl.rider_id = u.id
WHERE rl.last_seen > now() - interval '5 minutes';
```

### Cambiar el estado de un pedido manualmente

```sql
UPDATE orders SET status = 'delivered' WHERE id = 'uuid-del-pedido';
```

### Ver los productos de un restaurante

```sql
SELECT p.name, p.price, p.is_available, c.name as categoria
FROM products p
JOIN categories c ON p.category_id = c.id
WHERE p.restaurant_id = 'uuid-del-restaurante'
ORDER BY c.sort_order, p.name;
```

### Resetear la contraseña de un usuario

```sql
UPDATE auth.users
SET encrypted_password = crypt('nueva-contraseña-aqui', gen_salt('bf'))
WHERE email = 'usuario@ejemplo.com';
```

---

## 10. Backup y Recuperación de Datos

### Plan gratuito (actual en desarrollo)
- No hay backups automáticos
- La BD se pausa a los 7 días sin actividad
- **Riesgo:** No usar en producción

### Plan Pro ($25 USD/mes)
- Backups automáticos diarios
- Point-in-time recovery (volver a cualquier momento de las últimas 7 días)
- La BD nunca se pausa

### Hacer backup manual (SQL Editor)

```sql
-- Exportar todos los restaurantes
SELECT * FROM restaurants;

-- Exportar todos los pedidos del último mes
SELECT * FROM orders
WHERE created_at >= now() - interval '30 days';
```

Clic en **"Download CSV"** para guardar los resultados.

---

## 11. Monitoreo y Errores

### Ver logs en tiempo real

Supabase Dashboard → **Logs** → seleccionar:
- `API Logs` — peticiones HTTP (errores 400, 500)
- `Postgres Logs` — errores SQL
- `Edge Function Logs` — errores en funciones del servidor

### Qué buscar cuando algo falla

| Síntoma | Dónde buscar |
|---|---|
| La app no carga datos | API Logs → buscar status 401, 403, 500 |
| Los pagos fallan | Edge Function Logs → buscar "Stripe error" |
| Las imágenes no cargan | Storage → verificar que el bucket es público |
| Un usuario no puede entrar | Authentication → buscar el email, verificar metadata |
| GPS no actualiza | Revisar tabla `rider_locations` → buscar `last_seen` |

---

*Grupo Fercadi — GOGO Food | Junio 2026*
