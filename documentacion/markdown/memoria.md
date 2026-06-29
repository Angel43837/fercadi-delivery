# Memoria del Proyecto — GOGO Food
### Contexto acumulado durante el desarrollo con Claude

---

> Este archivo recoge las decisiones, preferencias y contexto que se han ido definiendo a lo largo del desarrollo del proyecto. Sirve como punto de referencia para Claude y para cualquier desarrollador que entre al proyecto.

---

## Proyecto — Grupo Fercadi

**App de delivery Flutter para Maravatío, Michoacán.**  
Proyecto de Grupo Fercadi. Estilo DiDi/Rappi adaptado a la ciudad.  
Tema oscuro con color primario rosa/magenta `#E91E8C`.

### Stack actual

| Tecnología | Uso |
|---|---|
| Flutter + Dart 3.11.5 | Framework principal (web, Android, iOS) |
| Supabase | BD, Auth, Storage, Edge Functions |
| go_router ^14.0.0 | Navegación entre pantallas |
| provider ^6.1.2 | Estado global del carrito |
| flutter_map ^6.0.0 | Mapas OpenStreetMap (panel de flota en web) |
| latlong2 ^0.9.0 | Coordenadas geográficas para flutter_map |
| url_launcher ^6.3.0 | Abrir Google Maps externo |
| geolocator | GPS del dispositivo |
| flutter_stripe | Pagos con tarjeta (Stripe) |
| shared_preferences | Sesión persistente en disco |
| carousel_slider ^5.0.0 | Carrusel de banners |

### Roles implementados

| Rol | Ruta | Pantalla |
|---|---|---|
| Cliente | `/login` → `/restaurants` | App de delivery |
| Dueño | `/restaurante` → `/dueno` | Panel naranja |
| Repartidor | `/moto` → `/repartidor` | Solo móvil |
| Jefe de flota | `/flota-login` → `/flota` | Panel azul con mapas |
| Admin Fercadi | `GOGOAdmin.apk` → `/admin` | Panel oscuro |

### Geolocalización

- Centro de Maravatío: `19.8969°N, 100.4447°W`
- Radio de cobertura: 30 km
- Mock siempre simula estar dentro del radio

### Tablas de Supabase

`restaurants`, `categories`, `products`, `product_images`, `orders`, `order_items`, `product_likes`, `restaurant_banners`, `flota_members`, `rider_locations`

### Colores de la app

```
Cliente / Admin:  fondo #121212, superficie #1E1E1E, primario #E91E8C (rosa)
Dueño:            primario #FF5722 (naranja) — NO cambiar
Flota:            fondo #0F1117, acento #4F8EF7 (azul)
```

---

## Decisiones Técnicas Confirmadas

Estas son preferencias explícitas del equipo — respetar sin proponer alternativas salvo que se pida.

| Decisión | Tecnología elegida |
|---|---|
| Base de datos y backend | **Supabase** |
| Pagos | **Stripe** (flutter_stripe) |
| Mapas en web | **flutter_map + OpenStreetMap** (google_maps_flutter no funciona en web) |
| Mapas en móvil | **google_maps_flutter** |
| Abrir ubicación externa | **url_launcher** → Google Maps |
| Sesión persistente | **SharedPreferences** (no Clerk — se descartó) |
| Documentación | **Markdown** en `documentacion/markdown/` |

### Separación de sesiones (importante)

El `FlotaLoginScreen` **NO** llama a `AuthService.saveSession()` para no interferir con la sesión del cliente. El panel de flota depende únicamente de la sesión de Supabase.  

El `SplashScreen` solo redirige a `/flota` cuando SharedPreferences ya tiene ese valor guardado — no consulta Supabase directamente cuando no hay sesión local.

---

## Flujo de Deploy

### Regla por defecto

Después de cada cambio de código: **solo deploy a Vercel** (web).  
**NO** compilar APKs automáticamente — tardan 5-10 minutos cada uno.

**Solo compilar APKs cuando el usuario lo pida explícitamente** ("actualiza el APK", "genera el APK").

### Comandos de deploy web

```powershell
flutter build web --release --pwa-strategy=none
Copy-Item vercel.json build/web/vercel.json -Force
cd build/web
npx vercel --prod --archive=tgz
```

### URL de producción

```
https://web-iota-brown-32.vercel.app
```

---

## Sistema de Flota — Contexto

Implementado para empresarios con repartidores propios (ej. Eloy).

- El jefe de flota entra por `/flota-login` con su cuenta de Supabase (rol `jefe_flota`)
- Ve un panel con todos sus repartidores: mapa OSM, estado online/offline, entregas del día, ganancias
- Los repartidores transmiten GPS continuamente en `rider_locations` (upsert por `rider_id`)
- Online = `last_seen` hace menos de 5 minutos
- El panel hace polling automático cada 10 segundos
- Marcador del mapa: círculo azul + ícono `delivery_dining_rounded` + punta triangular custom

### Vincular un repartidor a un jefe de flota (SQL)

```sql
INSERT INTO flota_members (jefe_id, rider_id)
VALUES ('uuid-del-jefe', 'uuid-del-rider');
```

### Asignar rol jefe de flota (SQL)

```sql
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"role": "jefe_flota"}'::jsonb
WHERE email = 'correo@ejemplo.com';
```

---

## Resolución del Conflicto `Path` (dart:ui vs flutter_map)

`flutter_map` exporta un tipo `Path<LatLng>` que choca con `dart:ui.Path` usado en `CustomPainter`.

**Solución:** En `flota_screen.dart`, importar con alias:

```dart
import 'dart:ui' as ui;
// Y usar ui.Path() en vez de Path() en el CustomPainter
```

---

## Archivos Clave del Proyecto

| Archivo | Para qué |
|---|---|
| `lib/core/constants.dart` | Colores, URLs Supabase, claves Stripe |
| `lib/services/supabase_service.dart` | Toda la comunicación con Supabase (y mock data) |
| `lib/services/auth_service.dart` | Sesión con SharedPreferences |
| `lib/router.dart` | Todas las rutas de navegación |
| `lib/screens/flota_screen.dart` | Panel del jefe de flota con mapas OSM |
| `lib/screens/flota_login_screen.dart` | Login aislado del jefe de flota |
| `lib/screens/splash_screen.dart` | Lógica de redirección según rol |
| `vercel.json` | Config de rutas para Vercel (SPA rewrites) |
| `build_apks.ps1` | Script para generar GOGOFood.apk y GOGOAdmin.apk |

---

*Última actualización: Junio 2026*
