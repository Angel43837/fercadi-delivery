# Manual de Despliegue — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## Requisitos Previos

Antes de hacer cualquier deploy, verificar que tienes instalado:

- **Flutter** en el PATH → `flutter --version`
- **Node.js 18+** → `node -v`
- **Vercel CLI autenticado** → `npx vercel whoami`

---

## 1. Despliegue Web (Vercel)

### URL de producción
```
https://web-iota-brown-32.vercel.app
```

### Pasos para deployar

```powershell
# Paso 1 — Compilar Flutter a JavaScript
flutter build web --release --pwa-strategy=none
# Tarda: ~60 segundos

# Paso 2 — Copiar la configuración de rutas al build
# (sin este paso Vercel no sabe redirigir /flota, /dueno, etc.)
Copy-Item vercel.json build/web/vercel.json -Force

# Paso 3 — Subir a producción
cd build/web
npx vercel --prod --archive=tgz
# Tarda: ~20 segundos
```

### ¿Cuándo hacer deploy?

Hacer deploy cuando se cambie algo en:
- `lib/screens/` — pantallas o diseño visual
- `lib/services/` — lógica de negocio
- `lib/router.dart` — rutas de navegación
- `vercel.json` — configuración del servidor

**NO** es necesario hacer deploy cuando solo cambian datos en Supabase (restaurantes, precios, fotos) — esos se leen en tiempo real.

### Rollback (volver a versión anterior)

Si algo sale mal:
1. Ir a [vercel.com](https://vercel.com) → tu proyecto → **Deployments**
2. Clic en cualquier deploy anterior → **"Promote to Production"**
3. En 30 segundos la versión anterior está activa

### Rutas disponibles en la web

| URL | Pantalla |
|---|---|
| `/` | Splash (redirige según sesión) |
| `/login` | Login del cliente |
| `/restaurants` | App principal del cliente |
| `/restaurante` | Login del dueño (tema naranja) |
| `/dueno` | Panel del dueño |
| `/moto` | Login del repartidor |
| `/flota-login` | Login del jefe de flota |
| `/flota` | Panel del jefe de flota |

---

## 2. Despliegue Android — APKs

Se generan **dos APKs independientes**:

| APK | Para quién | Entry point |
|---|---|---|
| `GOGOFood.apk` | Clientes y repartidores | `lib/main.dart` |
| `GOGOAdmin.apk` | Administrador Fercadi | `lib/main_admin.dart` |

### Generar las APKs

```powershell
.\build_apks.ps1
# Resultado:
#   build\GOGOFood.apk    (~35 MB)
#   build\GOGOAdmin.apk   (~35 MB)
```

### Instalar en teléfonos (sin Play Store)

1. Transferir el `.apk` al teléfono (WhatsApp, Google Drive, cable USB)
2. Abrir el archivo desde el teléfono
3. Si Android bloquea: **Configuración → Seguridad → Fuentes desconocidas → Permitir**

---

## 3. Variables de Entorno y Credenciales

Todas las credenciales están en `lib/core/constants.dart`:

| Constante | Dónde obtenerla |
|---|---|
| `supabaseUrl` | Supabase Dashboard → Settings → API |
| `supabaseAnonKey` | Supabase Dashboard → Settings → API |
| `stripePublishableKey` | dashboard.stripe.com → Developers → API Keys |
| `sentryDsn` | sentry.io → tu proyecto → Settings → Client Keys |

> ⚠️ La clave **secreta** de Stripe (`sk_...`) **NUNCA** va en el código. Se pone como variable de entorno en Supabase → Edge Functions → Secrets.

### Modo Mock vs Producción

En `lib/services/supabase_service.dart`:

```dart
static const bool useMock = false;
// true  = datos de prueba hardcodeados (sin internet)
// false = Supabase real (producción)
```

---

## 4. Problemas Comunes en el Despliegue

### Build web falla por dependencias
```powershell
flutter clean
flutter pub get
flutter build web --release --pwa-strategy=none
```

### Vercel muestra página en blanco
**Causa:** El `vercel.json` no se copió al build.  
**Solución:** Repetir el Paso 2 del proceso de deploy antes de volver a subir.

### Vercel cachea la versión antigua
Los usuarios siguen viendo la versión anterior.  
**Solución para el usuario:** `Ctrl + Shift + R` (recarga forzada).  
El `vercel.json` ya tiene `no-cache` configurado para los archivos del Service Worker.

### APK no instala en el teléfono
**Causa:** Android bloquea apps fuera de Play Store por defecto.  
**Solución:** Configuración → Seguridad → Permitir fuentes desconocidas (o "Instalar apps desconocidas" en Android 8+).

---

## 5. Checklist de Deploy Web

- [ ] El código fue probado en local (`flutter run -d chrome`)
- [ ] `useMock = false` en `supabase_service.dart`
- [ ] Se ejecutó `flutter build web --release --pwa-strategy=none` sin errores
- [ ] Se copió `vercel.json` a `build/web/`
- [ ] Se ejecutó `npx vercel --prod --archive=tgz` y salió "READY"
- [ ] Se verificó la URL pública en el navegador

---

*Grupo Fercadi — GOGO Food | Junio 2026*
