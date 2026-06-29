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

El rol se guarda en `user_metadata.role` en Supabase Auth y en SharedPreferences.
La sesión persiste: el splash espera el evento `initialSession` de Supabase antes de rutear.

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
- [ ] Icono 1024×1024 sin transparencia
- [ ] Screenshots para ambas tiendas

---

## Geolocalización

- Centro Maravatío: `19.8969° N, 100.4447° W`, radio 30 km
- Mock siempre simula estar dentro del radio
