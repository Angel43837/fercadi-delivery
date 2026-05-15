# Grupo Fercadi — Delivery App

App de delivery para el municipio de Maravatío, Michoacán.
Desarrollada en Flutter con tema oscuro y diseño rosa/magenta.

---

## Stack Tecnológico

| Tecnología | Uso |
|---|---|
| Flutter | Framework principal (Dart 3.11.5) |
| Supabase | Base de datos y autenticación (pendiente configurar) |
| go_router ^14.0.0 | Navegación entre pantallas |
| provider ^6.1.2 | Estado global (carrito) |
| geolocator ^13.0.2 | Detección de ubicación GPS |
| carousel_slider ^5.0.0 | Carrusel de imágenes en detalle |
| supabase_flutter ^2.8.0 | Cliente de Supabase |

---

## Cómo correr la app

```bash
# Instalar dependencias
flutter pub get

# Correr en emulador Android
flutter run -d emulator-5554

# Correr en Chrome (web)
flutter run -d chrome
```

> **Nota:** El emulador puede tardar en arrancar. Abrirlo desde Android Studio → Device Manager antes de correr `flutter run`.

---

## Modo Demo (Mock)

En `lib/services/supabase_service.dart`:

```dart
static const bool useMock = true;  // ← true = datos falsos, false = Supabase real
```

Con `useMock = true`:
- No se conecta a Supabase (no necesita credenciales)
- Simula estar ubicado en Maravatío
- Usa restaurantes/categorías/productos de prueba

Para conectar Supabase real: cambiar a `false` y poner las credenciales en `lib/core/constants.dart`.

---

## Estructura de Archivos

```
lib/
├── main.dart                    # Punto de entrada, Provider, tema
├── router.dart                  # Rutas con go_router
├── core/
│   └── constants.dart           # Colores, URLs de Supabase
├── models/
│   ├── restaurant.dart          # Modelo Restaurante
│   ├── category.dart            # Modelo Categoría
│   ├── product.dart             # Modelo Producto
│   └── cart_item.dart           # Modelo ítem del carrito
├── providers/
│   └── cart_provider.dart       # Estado del carrito (ChangeNotifier)
├── services/
│   ├── supabase_service.dart    # CRUD Supabase + datos mock
│   └── location_service.dart   # GPS y verificación de zona
└── screens/
    ├── splash_screen.dart       # Pantalla de carga con logo
    ├── login_screen.dart        # Login / registro
    ├── restaurants_screen.dart  # Pantalla principal (acordeón)
    ├── menu_screen.dart         # Menú por categorías (no en uso activo)
    ├── product_detail_screen.dart # Detalle de producto
    ├── cart_screen.dart         # Carrito de compras
    └── home_shell.dart          # Shell anterior (reemplazado)
```

---

## Flujo de la App

```
Splash (logo Fercadi, 3s)
    ↓
Login (email + contraseña / botón demo)
    ↓
Restaurantes (lista acordeón)
    ├── Logo Fercadi centrado arriba de la lista
    ├── Cada restaurante se expande al tocarlo
    │   ├── Like 👍 funcional (toca para dar/quitar like)
    │   ├── Pestañas de categorías con colores (scroll horizontal)
    │   └── Lista de platillos — cada platillo también se expande
    │       ├── Imagen del platillo
    │       ├── Descripción completa
    │       ├── Precio + selector de cantidad (- 1 +)
    │       └── Botón "Agregar al pedido • $XX MXN"
    └── Ícono de carrito en AppBar → pantalla de carrito
```

---

## Diseño / Tema

```dart
bgColor      = Color(0xFF121212)  // Negro oscuro — fondo principal
surfaceColor = Color(0xFF1E1E1E)  // Gris oscuro — tarjetas
surface2Color= Color(0xFF2A2A2A)  // Gris más oscuro — sub-tarjetas
primaryColor = Color(0xFFE91E8C)  // Rosa/magenta — color principal
```

Colores de las pestañas de categorías (van rotando por índice):
1. Rosa `#E91E8C`
2. Naranja `#FF6D00`
3. Verde azulado `#00BFA5`
4. Morado `#7C4DFF`
5. Azul `#2196F3`
6. Ámbar `#FFB300`

---

## Geolocalización

- Centro de Maravatío: `19.8969° N, 100.4447° W`
- Radio de servicio: **30 km**
- Si el usuario está fuera, ve pantalla de "Fuera de zona de servicio"
- En modo mock siempre simula estar dentro del radio

Permisos en `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

---

## Assets

```
assets/
└── images/
    └── logo.png    # Logo oficial de Grupo Fercadi
```

Registrado en `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/images/
```

---

## Base de Datos (Supabase — pendiente)

Tablas necesarias:
| Tabla | Campos clave |
|---|---|
| `restaurants` | id, name, description, address, image_url, rating, is_open |
| `categories` | id, restaurant_id, name, emoji_icon |
| `products` | id, category_id, name, description, price, image_url, is_available |
| `product_images` | id, product_id, image_url |
| `orders` | id, user_id, restaurant_id, total, status |
| `order_items` | id, order_id, product_id, quantity, price |

---

## Pendiente / Próximos pasos

- [ ] Configurar Supabase real (poner URL y anon key en `constants.dart`)
- [ ] Sistema de roles: cliente / repartidor / admin
- [ ] Panel de administrador (dueño): gestionar restaurantes, pedidos, usuarios
- [ ] Vista de repartidor: pedidos pendientes para entregar
- [ ] Autenticación con Clerk (actualmente usa Supabase Auth)
- [ ] Integración de Google Maps para mostrar restaurantes en mapa
- [ ] Imágenes reales de restaurantes y platillos
- [ ] Agregar restaurantes reales de Maravatío

---

## Datos Mock de Prueba

Restaurantes: McDonalds (id:1), Starbucks (id:2), Sushi Roll (id:3)

McDonalds tiene 6 categorías de ejemplo:
🍔 Hamburguesas | 🍟 Papas | 🥤 Bebidas | 🍦 Postres | 🥗 Ensaladas | 🥞 Desayunos

Productos de ejemplo: Big Mac ($89), Quarter Pounder ($95), McPollo Crispy ($79),
Café Americano ($65), California Roll ($120), etc.
