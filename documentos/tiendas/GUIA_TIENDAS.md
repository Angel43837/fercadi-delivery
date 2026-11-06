# Guía para publicar GOGO Food en las tiendas

Basada en lo que la app de verdad recolecta hoy (`ios/Runner/PrivacyInfo.xcprivacy`,
`lib/core/legal_content.dart`) y en el estado real del proyecto a nov 2026.

---

## 1. Data safety (Google Play) / App Privacy (App Store Connect)

Son dos formularios con el mismo espíritu: decirle a cada tienda qué datos recolecta
la app, para qué, y si se vinculan a la identidad del usuario. **Ninguno de los dos
dato se usa para publicidad ni se comparte con terceros para sus propios fines** — solo
para operar el servicio (entregar pedidos, cobrar, dar soporte).

### App Store Connect — App Privacy

Para cada tipo, la respuesta es **"Sí, se recolecta"**, **vinculado a tu identidad**
(salvo donde se indique lo contrario), **nunca para tracking**:

| Tipo de dato (categoría de Apple) | Se recolecta | Vinculado a tu identidad | Para qué lo usa Apple (propósito) |
|---|---|---|---|
| Nombre | Sí | Sí | Funcionalidad de la app |
| Dirección de correo | Sí | Sí | Funcionalidad de la app |
| Número de teléfono | Sí | Sí | Funcionalidad de la app |
| Dirección física (dirección de entrega) | Sí | Sí | Funcionalidad de la app |
| Ubicación precisa | Sí | Sí | Funcionalidad de la app |
| Fotos o videos (foto de perfil) | Sí | Sí | Funcionalidad de la app |
| Historial de compras | Sí | Sí | Funcionalidad de la app |
| Información de pago | Sí (la procesa Stripe; GOGO Food nunca ve el número completo) | Sí | Funcionalidad de la app |
| ID de usuario | Sí | Sí | Funcionalidad de la app |
| Datos de fallos (crash data, vía Sentry) | Sí | Sí (Sentry puede incluir el id de sesión, no tu identidad real) | Funcionalidad de la app |
| Datos de uso del producto | No | — | — |
| Contactos, historial de navegación, identificadores de publicidad | No | — | — |

Marca **"Data Not Linked to You"** = No en todos; marca **"Used for Tracking"** = No en
todos (GOGO Food no usa SDKs de publicidad ni comparte datos entre apps/empresas para
targeting).

**Repartidores** (solo su propio flujo, no aplica al cliente normal): además se
recolecta identificación oficial e información financiera (CLABE) — en el formulario de
Apple esto cae dentro de "Sensitive Info" (identificación oficial) y "Other Financial
Info" (CLABE), ambos vinculados a la identidad, solo funcionalidad de la app.

**Dueños de restaurante**: datos de la cuenta de cobro de Stripe Connect — mismo
tratamiento que "Other Financial Info".

### Google Play — Data safety

Mismo contenido, otro formulario. Las categorías de Google son un poco distintas a las
de Apple — el mapeo:

| Categoría de Google Play | Qué marcar |
|---|---|
| Personal info → Name, Email address, Phone number, Address | Sí, recolectada, vinculada a la cuenta, para "App functionality" |
| Location → Precise location | Sí, recolectada, vinculada, para "App functionality" |
| Photos and videos → Photos | Sí (foto de perfil), vinculada, "App functionality" |
| Financial info → Purchase history | Sí, vinculada, "App functionality" |
| Financial info → Other financial info (CLABE, cuenta Stripe Connect) | Sí (solo repartidores/dueños), vinculada, "App functionality" |
| App activity → nada | No marcar — no se rastrea actividad dentro de otras apps |
| App info and performance → Crash logs | Sí (Sentry), vinculada, "App functionality" |
| Device or other IDs | No |

Google pregunta también si los datos se **cifran en tránsito** (sí, todo pasa por
HTTPS/TLS — Supabase y Stripe) y si el usuario puede **pedir que se borre su
información** (sí — desde la app, o por correo, ver `eliminar_cuenta.html`).

---

## 2. URLs públicas requeridas

Ambas tiendas piden una URL pública (sin login) de la política de privacidad; Google
además exige una URL de "cómo borrar tu cuenta" si el borrado no es solo dentro de la
app (GOGO Food sí lo permite dentro de la app, pero aun así conviene tener la página
pública como respaldo y para quien todavía no se instala la app).

**Cómo publicarlas** (mismo patrón que ya usa la web oficial, repo `Pagina_web_GoGo`,
desplegado en Vercel):

1. Copia `privacy_policy.html` y `eliminar_cuenta.html` (están en la raíz de este repo)
   a donde ya sirves contenido estático en Vercel — lo más simple es agregarlos al
   proyecto de la web oficial (`~/Pagina_web_GoGo`) como rutas públicas, ej.
   `public/privacy_policy.html` y `public/eliminar_cuenta.html` si usa Next.js con la
   carpeta `public/`, o el equivalente de tu framework.
2. Haz `vercel --prod` (o el deploy normal de ese repo).
3. Verifica que abran **sin iniciar sesión**, en una ventana de incógnito:
   - `https://<tu-dominio>/privacy_policy.html`
   - `https://<tu-dominio>/eliminar_cuenta.html`
4. Esas 2 URLs son las que se pegan en App Store Connect (App Privacy → Privacy Policy
   URL) y en Google Play Console (App content → Privacy policy, y Data safety → Account
   deletion → URL).

**Pendiente**: el dominio real donde van a vivir depende de dónde termines publicando
la web oficial — dime cuál usar (¿`pagina-web-gogo-rho.vercel.app` o un dominio propio
nuevo?) y te doy la URL exacta una vez publicadas.

---

## 3. Cuenta de prueba para los revisores

Ambas tiendas piden credenciales de una cuenta real para que el revisor humano navegue
la app completa (pedir, pagar, ver el panel de dueño/repartidor si aplica).

**No crear esta cuenta en producción todavía** — créala tú cuando decidas que es el
momento (un día antes de mandar a revisión, para no dejarla viva mucho tiempo sin uso).
Texto sugerido para el campo de notas de cada tienda:

> Cuenta de cliente de prueba: correo `revision-apple@fercadi.com` (o el que uses),
> contraseña `<la que pongas>`. Para probar un pedido completo, usa efectivo como
> método de pago (la tarjeta de prueba de Stripe no funciona en producción). Si
> necesitas probar el panel de repartidor o de dueño de restaurante, avísanos por este
> mismo medio y te damos credenciales de esos roles también.

Si Apple/Google insisten en probar el pago con tarjeta: no hay forma de dar una
"tarjeta de prueba" en modo producción (Stripe real) — avísame si llega ese caso,
hay que decidir si se les da una tarjeta real con un monto chico reembolsable o se les
explica que el pago en efectivo ya cubre el flujo completo.

---

## 4. Capturas de pantalla y clasificación de edad

### Tamaños de capturas

**App Store Connect** (al menos un set; los demás se pueden generar a partir de este
con el simulador):
- iPhone 6.9" (iPhone 16 Pro Max y similares): 1320 × 2868 px — **obligatorio**
- iPhone 6.5" (iPhone 11 Pro Max, XS Max): 1242 × 2688 px — si quieres cubrir
  dispositivos más viejos
- iPad 13" (si la app corre en iPad — revisar si se soporta oficialmente): 2064 × 2752 px

**Google Play Console**:
- Teléfono: mínimo 2 capturas, 320–3840 px de lado, relación 16:9 o 9:16
- Ícono de la app: 512×512 px, 32 bits PNG (con alpha)
- Gráfico de funciones (feature graphic): 1024×500 px

Pantallas recomendadas para ambas tiendas (mismo set sirve para las dos): lista de
restaurantes, menú de un restaurante con el carrito, checkout, seguimiento del pedido
en el mapa, panel del dueño, panel del repartidor.

### Clasificación de edad sugerida

- **App Store**: 4+ (no hay contenido para adultos; si hay chat libre entre
  cliente/repartidor considera 12+ por "contenido generado por el usuario sin
  moderación" — recomendado: **12+** para cubrirte, ya que el chat de pedido y el de
  soporte son texto libre sin filtro de contenido hoy).
- **Google Play**: completa el cuestionario IARC — por el chat libre y el manejo de
  pagos, el resultado esperado es **PEGI 12 / Teen**, no All Ages. Si prefieres evitar
  esto, habría que agregar moderación/filtro de palabras al chat (fuera de alcance de
  esta ronda).

---

## 5. Build de producción

### Android — keystore

**Nunca se guarda el keystore en este repo.** Pasos (una sola vez):

```bash
keytool -genkey -v -keystore ~/gogo-food-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias gogo-food
```

Guarda `~/gogo-food-release.jks` y su contraseña en un gestor de contraseñas, **no en
el repo ni en Slack/WhatsApp**. Crea `android/key.properties` (ya debe estar en
`.gitignore` — confírmalo) con:

```properties
storePassword=<tu contraseña>
keyPassword=<tu contraseña>
keyAlias=gogo-food
storeFile=/ruta/absoluta/a/gogo-food-release.jks
```

Build del AAB (lo que pide Google Play):

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://dlukaxbcyetcdbdjjgct.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key real de producción> \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_... \
  --dart-define=APP_GROUP_ID=group.com.fercadi.app
```

(`APP_GROUP_ID` no afecta Android — no hace daño dejarlo, por si el mismo comando se
reusa como plantilla para iOS.)

### iOS — IPA

```bash
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://dlukaxbcyetcdbdjjgct.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key real de producción> \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_... \
  --dart-define=APP_GROUP_ID=group.com.fercadi.app
```

Necesitas: cuenta de Apple Developer activa, certificado de distribución y perfil de
aprovisionamiento (Xcode los maneja solo si "Automatically manage signing" está
activado — ya es el caso en este proyecto). Sube con Xcode (Window → Organizer) o
`xcrun altool`/`xcrun notarytool` según la versión de Xcode que tengas.

**Antes de generar el build real**: confirma cuál es la `SUPABASE_ANON_KEY` pública
real de `dlukaxbcyetcdbdjjgct` (Settings → API → anon/public key en el dashboard —
no es secreta, pero mejor verificarla en el momento en vez de copiarla de memoria) y la
`pk_live_...` de la cuenta de Stripe de producción (dashboard de Stripe, modo Live,
Developers → API keys).
