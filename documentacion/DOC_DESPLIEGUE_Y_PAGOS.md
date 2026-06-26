# Documentación de Despliegue y Sistema de Pagos — GOGO Food

> Documento enfocado en: cómo se despliega la app, cómo fluye el dinero, dónde puede fallar y dónde puede ser lento.

---

## 1. Infraestructura de Despliegue

```
┌──────────────────────────────────────────────────────────┐
│                  INTERNET (usuarios finales)              │
└──────────────┬───────────────────────────────────────────┘
               │
       ┌───────▼────────┐          ┌──────────────────┐
       │    VERCEL      │          │  Google Play /    │
       │  (web app)     │          │  App Store        │
       │  CDN global    │          │  (APK Android)    │
       └───────┬────────┘          └────────┬─────────┘
               │                            │
       ┌───────▼────────────────────────────▼──────────┐
       │              SUPABASE CLOUD                    │
       │  ┌──────────┐ ┌──────────┐ ┌───────────────┐  │
       │  │PostgreSQL│ │   Auth   │ │Edge Functions │  │
       │  └──────────┘ └──────────┘ └───────┬───────┘  │
       └──────────────────────────────────── │ ─────────┘
                                             │
                                    ┌────────▼────────┐
                                    │     STRIPE      │
                                    │  (cobros reales)│
                                    └─────────────────┘
```

---

## 2. Proceso de Despliegue Web (Paso a Paso)

### Herramientas necesarias
- Flutter instalado y en el PATH
- Node.js 18+ instalado
- Cuenta de Vercel autenticada (`npx vercel login`)

### Comandos

```powershell
# Paso 1 — Compilar la app para web
flutter build web --release --pwa-strategy=none

# Paso 2 — Copiar la config de Vercel dentro del build
Copy-Item vercel.json build/web/vercel.json -Force

# Paso 3 — Subir a producción
cd build/web
npx vercel --prod --archive=tgz
```

### Qué hace cada paso

| Paso | Qué hace | Tiempo aproximado |
|---|---|---|
| `flutter build web` | Compila Dart a JavaScript optimizado (tree-shaking, minificación) | 45-60 segundos |
| `Copy-Item vercel.json` | Pone la configuración de rutas dentro del build para que Vercel la lea | Instantáneo |
| `npx vercel --prod` | Comprime el build, lo sube a la CDN de Vercel y lo publica | 15-30 segundos |

### Resultado

- URL pública: `https://web-iota-brown-32.vercel.app`
- El deploy es **inmediato** — los usuarios ven la nueva versión en segundos
- Vercel guarda historial de todos los deploys anteriores (se puede hacer rollback)

### Cuándo hacer deploy

Siempre que se cambie código en:
- `lib/screens/` — cambios visuales
- `lib/services/` — cambios de lógica de negocio
- `lib/models/` — cambios de estructura de datos
- `vercel.json` — cambios de configuración del servidor

**No** es necesario hacer deploy cuando solo cambian:
- Datos en Supabase (la app los lee en tiempo real)
- Variables de entorno en Supabase (Edge Functions)

---

## 3. Proceso de Despliegue Android (APKs)

```powershell
.\build_apks.ps1
```

Genera dos archivos:

| Archivo | Para quién | Cómo instalar |
|---|---|---|
| `build\GOGOFood.apk` | Clientes que piden comida | Compartir por WhatsApp/Drive → instalar en el teléfono |
| `build\GOGOAdmin.apk` | Administrador Fercadi | Solo para el equipo interno |

> ⚠️ Para publicar en Google Play Store se necesita un keystore firmado y cuenta de desarrollador ($25 USD pago único). Actualmente las APKs se distribuyen directamente (sideload).

---

## 4. Flujo Completo del Sistema de Pagos

La app tiene **3 métodos de pago**. Cada uno tiene un flujo diferente:

### 4.1 Efectivo (método actual más usado)

```
Cliente elige "Efectivo" en checkout
            │
            ▼
Se crea el pedido en Supabase (status = "pending")
            │
            ▼
Repartidor lleva el pedido y cobra en mano
            │
            ▼
El dueño registra el pago manualmente (fuera de la app)
```

**Riesgo:** No hay verificación digital del pago. Se depende de la honestidad del repartidor.

---

### 4.2 Pago con Tarjeta (Stripe)

```
Cliente elige "Tarjeta" en checkout
            │
            ▼
App llama a Supabase Edge Function "create-payment-intent"
  │  Envía: monto en MXN (centavos), moneda
  │
  ▼
Edge Function llama a la API de Stripe con la clave secreta (sk_...)
  │  Stripe devuelve: clientSecret (token de un solo uso)
  │
  ▼
App recibe el clientSecret
  │
  ▼
Flutter Stripe SDK abre el PaymentSheet (pantalla nativa de pago)
  │  Cliente ingresa: número de tarjeta, fecha, CVV
  │  Stripe valida con el banco del cliente
  │
  ▼
Si el banco aprueba → Stripe confirma el pago
  │
  ▼
App crea el pedido en Supabase con el cargo ya confirmado
```

**Archivos involucrados:**
- `lib/screens/checkout_screen.dart` → método `_payWithStripe()`
- Supabase Edge Function `create-payment-intent` (en el dashboard de Supabase)
- `lib/core/constants.dart` → `stripePublishableKey`

**Claves de Stripe:**

| Clave | Dónde está | Para qué |
|---|---|---|
| `pk_test_...` (publishable) | `constants.dart` en el código | La app la usa para inicializar el SDK |
| `sk_test_...` (secret) | Variable de entorno en Supabase Edge Function | El servidor la usa para crear cobros. NUNCA va en el código del cliente |

> ⚠️ Las claves con prefijo `pk_test_` y `sk_test_` son de **modo prueba** — no cobran dinero real. Para producción se usan `pk_live_` y `sk_live_`.

---

### 4.3 OXXO Pay

```
Cliente elige "OXXO" en checkout
            │
            ▼
Stripe genera un cupón con número de referencia
            │
            ▼
Cliente va al OXXO más cercano y paga con ese número
            │
            ▼
OXXO notifica a Stripe (puede tardar hasta 2-3 días)
            │
            ▼
Stripe manda webhook a la Edge Function
            │
            ▼
Edge Function actualiza el pedido en Supabase a "pagado"
```

**Estado actual:** La opción aparece en la pantalla pero el webhook de OXXO no está completamente configurado.

---

## 5. Posibles Problemas en el Despliegue

### P1 — Build web falla por dependencias desactualizadas
**Cuándo ocurre:** Después de actualizar Flutter o paquetes con `flutter pub upgrade`  
**Síntoma:** Error en compilación, menciona algún paquete incompatible  
**Solución:**
```powershell
flutter clean
flutter pub get
flutter build web --release --pwa-strategy=none
```

### P2 — Vercel muestra página en blanco después del deploy
**Cuándo ocurre:** Si el `vercel.json` no se copió correctamente al build  
**Síntoma:** La URL carga pero la app no aparece, solo pantalla blanca  
**Causa:** Sin `vercel.json`, Vercel no sabe redirigir todas las rutas a `index.html`  
**Solución:** Verificar que el paso 2 (Copy-Item) se ejecutó antes del deploy

### P3 — Vercel cachea la versión antigua
**Cuándo ocurre:** Después de un deploy, algunos usuarios siguen viendo la versión anterior  
**Causa:** Los archivos `flutter_service_worker.js` y `flutter_bootstrap.js` tienen header `no-cache` pero el navegador puede ignorarlo  
**Solución:** Los usuarios deben hacer Ctrl+Shift+R (recarga forzada). En el `vercel.json` ya está configurado `no-cache` para estos archivos

### P4 — Deploy falla por timeout en Vercel
**Cuándo ocurre:** Conexión lenta al subir el build  
**Síntoma:** Error "Request timeout" o "Upload failed"  
**Solución:** Reintentar el comando `npx vercel --prod --archive=tgz`. El archivo `.tgz` que genera Vercel comprime el build antes de subir, reduciendo el tamaño

### P5 — APK no instala en el teléfono
**Cuándo ocurre:** Al intentar instalar la APK directamente  
**Causa:** Android bloquea apps de "fuentes desconocidas" por defecto  
**Solución:** Ir a Configuración → Seguridad → Permitir instalación de fuentes desconocidas (o "Instalar apps desconocidas" en Android 8+)

---

## 6. Posibles Problemas en el Sistema de Pagos

### P6 — Edge Function "create-payment-intent" devuelve error 500
**Cuándo ocurre:** Al intentar pagar con tarjeta  
**Síntoma:** La app muestra "Error: No se obtuvo clientSecret"  
**Causas posibles:**
1. La variable de entorno `STRIPE_SECRET_KEY` no está configurada en Supabase → ir a Supabase → Edge Functions → Secrets
2. La Edge Function no está deployada → ir a Supabase → Edge Functions → verificar que existe `create-payment-intent`
3. La clave secreta de Stripe expiró o es incorrecta

### P7 — Pago aparece como "cobrado" pero el pedido no se creó
**Cuándo ocurre:** Si la app se cierra entre el pago de Stripe y la creación del pedido en Supabase  
**Síntoma:** El cliente ve el cargo en su tarjeta pero el dueño no recibe el pedido  
**Causa:** Son dos operaciones separadas sin transacción atómica entre ellas  
**Solución temporal:** Verificar en Stripe Dashboard si el cobro existe y contactar al cliente para confirmar/reembolsar manualmente

### P8 — PaymentSheet no abre en web
**Cuándo ocurre:** Cliente intenta pagar con tarjeta desde el navegador  
**Causa:** `flutter_stripe` tiene soporte limitado en web — el `PaymentSheet` está pensado para apps nativas  
**Síntoma:** No pasa nada al tocar "Pagar con tarjeta" en la versión web  
**Solución a futuro:** Implementar Stripe Elements para web en lugar del PaymentSheet nativo

### P9 — Tarjeta rechazada sin mensaje claro
**Cuándo ocurre:** El banco rechaza el cargo  
**Síntoma:** La app muestra "Pago cancelado" pero no explica por qué  
**Causa:** Stripe devuelve `StripeException` con `localizedMessage` que a veces es genérico  
**Cómo diagnosticar:** Revisar en Stripe Dashboard → Payments → el intento fallido tiene el código de rechazo exacto del banco

### P10 — Modo prueba activo en producción
**Cuándo ocurre:** Se olvidó cambiar las claves de test a live  
**Síntoma:** Los cobros no son reales aunque los usuarios ingresen tarjetas reales  
**Verificación:** Revisar `constants.dart` — si `stripePublishableKey` empieza con `pk_test_` está en modo prueba  
**Solución:** Cambiar a `pk_live_...` en el código y `sk_live_...` en Supabase Secrets → recompilar y deployar

---

## 7. Cuellos de Botella Específicos

### B1 — Llamada a la Edge Function de Stripe (el más crítico en pagos)
**Dónde:** `checkout_screen.dart` → `_payWithStripe()` → llamada a `create-payment-intent`  
**Problema:** La Edge Function de Supabase tiene un "cold start" de 1-3 segundos si no ha sido invocada recientemente. El usuario ve el spinner sin saber qué pasa.  
**Impacto:** Alta fricción en el momento más crítico del flujo (el pago)  
**Mejora posible:** Invocar la Edge Function unos segundos antes de que el usuario presione "Pagar" (precalentar con una petición dummy)

### B2 — Build web tarda ~60 segundos
**Dónde:** Proceso de compilación en la terminal  
**Problema:** Cada deploy requiere compilar desde cero. No hay caché de compilación entre deploys.  
**Impacto:** Un hotfix urgente tarda mínimo 2-3 minutos en llegar a producción  
**Mejora posible:** Usar GitHub Actions para automatizar el build+deploy (se ejecuta en servidores más rápidos)

### B3 — Supabase Free Tier tiene límites
**Problema:** El plan gratuito de Supabase tiene:
- 500 MB de base de datos
- 5 GB de storage de imágenes
- 50,000 peticiones/mes a Edge Functions
- La base de datos se "duerme" después de 1 semana sin actividad (plan free)

**Impacto:** Si la app crece, puede llegar al límite y dejar de funcionar  
**Solución:** Pasar al plan Pro de Supabase ($25 USD/mes) cuando haya usuarios activos regulares

### B4 — Sin webhook de Stripe configurado
**Problema:** Stripe puede confirmar un pago pero si la app se cae en ese momento, no hay mecanismo automático para actualizar el pedido en Supabase  
**Impacto:** Pedidos pagados que quedan en estado "pending" indefinidamente  
**Solución:** Configurar un webhook en Stripe Dashboard → apuntar a una Edge Function de Supabase que actualice el estado del pedido cuando Stripe confirme el pago

### B5 — APKs distribuidas manualmente
**Problema:** Cada actualización requiere generar nueva APK y enviarla manualmente a cada usuario vía WhatsApp/Drive  
**Impacto:** Los usuarios pueden tener versiones diferentes, lo que complica el soporte  
**Solución:** Publicar en Google Play Store — las actualizaciones se distribuyen automáticamente

---

## 8. Dónde Se Paga y Cuánto Cuesta Cada Servicio

Esta sección explica todos los servicios que cobran dinero, cuánto cobran, cuándo se paga y a dónde va ese dinero.

---

### 8.1 Stripe — Comisión por cada cobro con tarjeta

**¿Qué es?** El procesador de pagos. Cada vez que un cliente paga con tarjeta, Stripe cobra una comisión.

**¿Cuánto cobra?**

| Tipo de tarjeta | Comisión |
|---|---|
| Tarjeta nacional (México) | **3.6% + $3 MXN** por transacción |
| Tarjeta internacional | **4.6% + $3 MXN** por transacción |

**Ejemplo:** Un pedido de $150 MXN con tarjeta nacional:
```
$150 × 3.6% = $5.40
+ $3.00 fijo
= $8.40 MXN que se queda Stripe
= $141.60 MXN que recibe Fercadi/restaurante
```

**¿Cuándo se paga?** Automáticamente. Stripe descuenta su comisión de cada cobro antes de depositar.

**¿A dónde va el dinero?** Stripe deposita el saldo neto a la cuenta bancaria registrada en el Stripe Dashboard (transferencias cada 2-7 días hábiles).

**¿Dónde se configura?**
- Crear cuenta: [dashboard.stripe.com](https://dashboard.stripe.com)
- Registrar cuenta bancaria MX (CLABE 18 dígitos)
- Verificar identidad del negocio (INE + comprobante de domicilio)

> ⚠️ Actualmente las claves son `pk_test_` / `sk_test_` — en modo prueba NO hay cobros reales. Cambiar a `pk_live_` / `sk_live_` para producción.

---

### 8.2 Supabase — Base de datos, autenticación y almacenamiento

**¿Qué es?** El servidor central de la app. Guarda todos los datos (restaurantes, pedidos, usuarios, fotos).

**Planes:**

| Plan | Costo | Límites |
|---|---|---|
| **Free** (actual) | $0 USD/mes | 500 MB BD, 5 GB storage, 50K Edge Function calls/mes. La BD se pausa después de 7 días sin actividad |
| **Pro** | $25 USD/mes | 8 GB BD, 100 GB storage, 2M Edge Function calls/mes. Sin pausa automática. Backups diarios |
| **Team** | $599 USD/mes | Para apps con miles de usuarios simultáneos |

**¿Cuándo hay que pagar?** Cuando la app tenga usuarios activos regulares. Con el plan Free, si la BD se pausa, nadie puede pedir comida hasta que se reactive (tarda ~30 segundos la primera petición).

**¿Dónde se paga?** [supabase.com/dashboard](https://supabase.com/dashboard) → tu proyecto → Settings → Billing

**Recomendación:** Pasar a Pro desde el primer día de lanzamiento real ($25 USD/mes ≈ $500 MXN/mes).

---

### 8.3 Vercel — Hosting del sitio web

**¿Qué es?** El servidor que aloja la versión web de la app (lo que ven los clientes en el navegador).

**Planes:**

| Plan | Costo | Límites |
|---|---|---|
| **Hobby** (actual) | $0 USD/mes | 100 GB de transferencia/mes, sin dominio propio con SSL automático para `.vercel.app` |
| **Pro** | $20 USD/mes por miembro del equipo | Dominio propio, 1 TB transferencia, analíticas avanzadas |

**¿Cuándo hay que pagar?** Solo si:
- Se quiere dominio propio (ej. `gogofood.mx`) — el dominio en sí cuesta ~$200-400 MXN/año aparte
- El tráfico web supera los 100 GB/mes (muy difícil de alcanzar con una sola ciudad)

**Conclusión:** Vercel puede quedarse gratis por mucho tiempo. Solo pagar si se quiere dominio personalizado.

**¿Dónde se paga?** [vercel.com/account/billing](https://vercel.com/account/billing)

---

### 8.4 Google Maps API — Mapa para selección de dirección

**¿Qué es?** El mapa interactivo que aparece en la app móvil cuando el cliente elige su dirección de entrega (`MapPickerScreen`).

**Costo:**

| Uso | Precio |
|---|---|
| Primeras 28,500 cargas de mapa/mes | **GRATIS** |
| Después de eso | $7 USD por cada 1,000 cargas adicionales |

**¿Cuándo hay que pagar?** Con una ciudad pequeña como Maravatío, es muy difícil superar 28,500 usos al mes. Probablemente nunca se pague.

**¿Dónde se paga?** [console.cloud.google.com](https://console.cloud.google.com) → Billing. Se requiere tarjeta registrada pero Google cobra solo si se supera el límite gratuito.

**Nota importante:** Aunque no se pague, Google **requiere** una tarjeta registrada para usar la API. Sin tarjeta, la API deja de funcionar después del período de prueba.

**¿Dónde está la clave?** En `android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY`

---

### 8.5 Google Play Store — Publicar la app Android

**¿Qué es?** La tienda oficial de Android donde los usuarios descargan la app.

| Concepto | Costo |
|---|---|
| Registro de cuenta de desarrollador | **$25 USD pago único** (para siempre) |
| Publicar apps | Gratis (ilimitadas) |
| Comisión por compras dentro de la app | 15-30% (no aplica aquí, los pagos van por Stripe) |

**¿Dónde se paga?** [play.google.com/console](https://play.google.com/console)

**¿Qué se necesita además del pago?**
- Keystore (archivo de firma digital) — se genera una sola vez con `keytool`
- Capturas de pantalla de la app
- Descripción y política de privacidad
- Verificación de identidad

**Tiempo de revisión:** 1-7 días hábiles para la primera publicación.

---

### 8.6 Apple App Store — Publicar en iPhone (futuro)

| Concepto | Costo |
|---|---|
| Cuenta Apple Developer | **$99 USD/año** (se renueva cada año) |
| Publicar apps | Incluido en la membresía |

**¿Dónde se paga?** [developer.apple.com](https://developer.apple.com)

**Nota:** Actualmente la app no está configurada para iOS. Requeriría una Mac con Xcode para compilar y una cuenta de Apple Developer activa.

---

### 8.7 Sentry — Monitoreo de errores (opcional pero recomendado)

**¿Qué es?** Servicio que captura automáticamente los errores que ocurren en la app en producción y los manda por email.

| Plan | Costo | Límites |
|---|---|---|
| **Free** | $0 | 5,000 errores/mes |
| **Team** | $26 USD/mes | 50,000 errores/mes + alertas avanzadas |

**¿Dónde se paga?** [sentry.io](https://sentry.io)

**Estado actual:** El DSN de Sentry está vacío en `constants.dart` — Sentry no está activo. Para activarlo, crear proyecto en sentry.io y pegar el DSN.

---

### 8.8 Firebase Cloud Messaging (FCM) — Notificaciones push

**¿Qué es?** El servicio que envía las notificaciones al repartidor y al dueño cuando llega un pedido.

**Costo:** **GRATIS** — Google no cobra por notificaciones push sin importar cuántas se envíen.

**¿Dónde se configura?** [console.firebase.google.com](https://console.firebase.google.com) — crear proyecto, descargar `google-services.json` y ponerlo en `android/app/`

---

### 8.9 Resumen de Costos — Cuándo Lanzar

| Servicio | Hoy (desarrollo) | Al lanzar | Mensual en producción |
|---|---|---|---|
| Stripe | Gratis (prueba) | Se activa automáticamente | 3.6% + $3 MXN por transacción |
| Supabase | Gratis | Pagar Pro desde día 1 | $25 USD (~$500 MXN) |
| Vercel | Gratis | Gratis si se queda en .vercel.app | $0 o $20 USD si se quiere dominio |
| Google Maps | Gratis | Gratis (menos de 28,500 cargas/mes) | $0 |
| Google Play | No aplica | $25 USD pago único | $0 |
| Apple Store | No aplica | $99 USD/año si se hace iOS | $99 USD/año |
| Sentry | No activo | Gratis es suficiente al inicio | $0 o $26 USD |
| FCM (notificaciones) | Gratis | Gratis | $0 |

**Costo mínimo para lanzar:**
- Sin iOS: **$50 USD** ($25 Supabase Pro primer mes + $25 Google Play)
- Con iOS: **$149 USD** (+ $99 Apple Developer)

**Costo mensual fijo después de lanzar:** ~$25-45 USD/mes (Supabase + Vercel opcional)

---

## 9. Checklist para Pasar a Producción Real

- [ ] Cambiar `pk_test_...` → `pk_live_...` en `constants.dart`
- [ ] Cambiar `sk_test_...` → `sk_live_...` en Supabase Edge Function Secrets
- [ ] Activar webhook de Stripe apuntando a Supabase
- [ ] Cambiar plan de Supabase a Pro ($25 USD/mes)
- [ ] Configurar dominio propio en Vercel (ej. `gogofood.mx`)
- [ ] Configurar SSL en el dominio (Vercel lo hace automáticamente)
- [ ] Crear keystore para firmar APK de Android (necesario para Play Store)
- [ ] Crear cuenta Google Play ($25 USD pago único)
- [ ] Activar monitoreo de errores en Sentry (poner el DSN real en `constants.dart`)
- [ ] Hacer prueba de pago completa con tarjeta real antes de lanzar

---

*Documentación de despliegue y pagos — Grupo Fercadi*  
*Versión: Junio 2026*
