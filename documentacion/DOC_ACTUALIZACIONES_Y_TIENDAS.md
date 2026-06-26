# Documentación de Actualizaciones y Publicación en Tiendas — GOGO Food

> Cómo funciona el proceso de actualizar la app, cómo se publica en Play Store y App Store, y qué pasa con los datos cuando se actualiza.

---

## 1. Cómo Funciona una Actualización

Cuando se modifica el código de la app, los usuarios no lo ven automáticamente. Primero hay que compilar el código nuevo y distribuirlo por el canal correspondiente.

```
Tú modificas el código
        │
        ▼
Compilas la app (flutter build)
        │
        ├── Web ──────► Subes a Vercel ──────────────► Usuarios lo ven en segundos
        │
        ├── Android ──► Subes a Play Store ──────────► Google revisa 1-3 días
        │                                               → usuarios reciben notificación
        │
        └── iOS ──────► Subes a App Store Connect ───► Apple revisa 1-7 días
                                                        → usuarios reciben notificación
```

**Los datos en Supabase NUNCA se tocan al actualizar.** Pedidos, usuarios, restaurantes, fotos — todo queda igual. Solo cambia la app que está instalada en el teléfono.

---

## 2. Actualizar la Versión Web

La web es el canal más rápido. En menos de 2 minutos todos los usuarios ven la nueva versión.

### Pasos

```powershell
# 1. Compilar
flutter build web --release --pwa-strategy=none

# 2. Copiar configuración de Vercel
Copy-Item vercel.json build/web/vercel.json -Force

# 3. Subir a producción
cd build/web
npx vercel --prod --archive=tgz
```

### ¿Qué pasa con los usuarios que están usando la app en ese momento?
- Siguen en la versión anterior hasta que recarguen la página
- Al recargar (F5 o Ctrl+R) ven la nueva versión automáticamente
- Si tiene Service Worker activo, pueden necesitar hacer Ctrl+Shift+R (recarga forzada)

### ¿Se puede revertir una actualización web?
Sí. En [vercel.com](https://vercel.com) → tu proyecto → Deployments → cualquier deploy anterior tiene un botón "Promote to Production" para volver a esa versión.

---

## 3. Actualizar la App Android (Play Store)

### Antes de la primera vez — configuración única

1. **Crear el keystore** (archivo de firma digital — se hace una sola vez y se guarda para siempre):
```powershell
keytool -genkey -v -keystore gogofood.keystore -alias gogofood -keyalg RSA -keysize 2048 -validity 10000
```
> ⚠️ Este archivo es crítico. Si se pierde, no se puede actualizar la app en Play Store nunca más. Guardarlo en un lugar seguro (Drive, USB, etc.)

2. **Crear cuenta de desarrollador** en [play.google.com/console](https://play.google.com/console) — $25 USD pago único

3. **Primera publicación:** Crear la app en Play Console, llenar la ficha (descripción, capturas, política de privacidad) y subir el primer APK/AAB

### Para cada actualización posterior

```powershell
# 1. Incrementar el número de versión en pubspec.yaml
# version: 1.0.0+1  →  version: 1.0.1+2

# 2. Generar el nuevo APK firmado
.\build_apks.ps1

# 3. Ir a play.google.com/console
# → tu app → Producción → Crear nueva versión → subir el archivo .aab o .apk
```

### Tiempos del proceso Android

| Etapa | Tiempo |
|---|---|
| Compilar APK | 2-5 minutos |
| Subir a Play Console | 2-5 minutos |
| Revisión de Google | 1-3 días hábiles (puede ser más en primera publicación) |
| Disponible para todos los usuarios | Inmediato después de aprobación |

### ¿Los usuarios tienen que hacer algo?
- Si tienen actualizaciones automáticas: la app se actualiza sola (de noche, con WiFi)
- Si no: les llega notificación en Play Store → tocan "Actualizar"
- Nadie pierde sus datos ni su sesión al actualizar

### Tipos de versiones en Play Store

| Tipo | Para qué |
|---|---|
| **Producción** | Todos los usuarios |
| **Beta cerrada** | Solo testers elegidos (recomendado para probar antes de lanzar) |
| **Beta abierta** | Cualquiera puede unirse como tester voluntario |
| **Prueba interna** | Solo el equipo de Fercadi (hasta 100 personas, sin revisión de Google) |

---

## 4. Publicar en App Store de Apple (iOS)

> **Requisito:** Una Mac con Xcode instalado. No se puede compilar para iOS desde Windows.

### Antes de la primera vez — configuración única

1. **Cuenta Apple Developer:** [developer.apple.com](https://developer.apple.com) — $99 USD/año
2. **Certificado de distribución** y **Provisioning Profile** — se generan en el portal de Apple Developer
3. **Registrar el Bundle ID** de la app: `com.fercadi.gogofood`
4. **Crear la app** en App Store Connect: [appstoreconnect.apple.com](https://appstoreconnect.apple.com)

### Para cada actualización

```bash
# En la Mac con Xcode
flutter build ipa --release

# El archivo .ipa generado se sube con Xcode o Transporter
# Luego en App Store Connect → tu app → Nueva versión → subir build
```

### Tiempos del proceso iOS

| Etapa | Tiempo |
|---|---|
| Compilar IPA en Mac | 5-15 minutos |
| Subir a App Store Connect | 5-10 minutos |
| Revisión de Apple | 1-7 días (Apple es más estricta que Google) |
| Disponible para usuarios | Inmediato después de aprobación |

### ¿Por qué Apple tarda más?
Apple revisa manualmente cada app y actualización. Rechazan apps que:
- No funcionan correctamente
- No tienen política de privacidad visible
- Usan APIs sin explicar para qué (ej. GPS, cámara)
- El diseño no cumple sus guías (Human Interface Guidelines)

---

## 5. Versionar la App Correctamente

El número de versión en `pubspec.yaml` tiene dos partes:

```yaml
version: 1.0.0+1
         │ │ │  └── build number (entero, debe incrementar en cada upload)
         │ │ └────── patch (corrección de bugs pequeños)
         │ └──────── minor (nueva funcionalidad sin romper nada)
         └────────── major (cambio grande o rediseño)
```

**Ejemplos:**
- Corregir imagen rota: `1.0.0+1` → `1.0.1+2`
- Agregar nueva pantalla: `1.0.1+2` → `1.1.0+3`
- Rediseño completo: `1.1.0+3` → `2.0.0+4`

> Play Store y App Store rechazan el build si el `build number` no es mayor al anterior.

---

## 6. Qué Pasa con los Datos al Actualizar

Esta es la pregunta más importante. La respuesta corta: **nada se borra**.

| Dato | Dónde vive | ¿Se afecta al actualizar? |
|---|---|---|
| Pedidos | Supabase (nube) | ❌ No, nunca |
| Restaurantes y menús | Supabase (nube) | ❌ No, nunca |
| Fotos de productos | Supabase Storage (nube) | ❌ No, nunca |
| Sesión del usuario | SharedPreferences (teléfono) | ❌ No, el usuario sigue logueado |
| Carrito actual | Memoria de la app | ⚠️ Se pierde si el usuario cierra la app (es normal) |
| Dirección guardada | SharedPreferences (teléfono) | ❌ No, se conserva |

La app en el teléfono es solo la "pantalla". Toda la información real vive en Supabase, que nunca se toca cuando actualizas la app.

---

## 7. Diferencia entre Actualización de App y Actualización de Datos

| Tipo | Ejemplo | ¿Requiere actualizar la app? | ¿Requiere revisión de tienda? |
|---|---|---|---|
| **Cambio de código** | Nueva pantalla, botón nuevo, fix de bug | ✅ Sí | ✅ Sí |
| **Cambio de datos** | Nuevo restaurante, cambio de precio, nueva foto | ❌ No | ❌ No |
| **Cambio de diseño** | Nuevo color, nueva fuente | ✅ Sí | ✅ Sí |
| **Cambio de menú** | Agregar producto, quitar categoría | ❌ No (el dueño lo hace desde su panel) | ❌ No |

El panel del dueño (`/dueno`) permite actualizar precios, productos y fotos **sin tocar el código** — esos cambios se reflejan en tiempo real para todos los usuarios.

---

## 8. Checklist Antes de Subir una Actualización

- [ ] Incrementar el `build number` en `pubspec.yaml`
- [ ] Probar en web local (`flutter run -d chrome`) que todo funciona
- [ ] Probar en Android emulador o dispositivo real
- [ ] Verificar que el login, carrito y pago funcionan correctamente
- [ ] Para Play Store: asegurarse que el keystore está disponible
- [ ] Para cambios importantes: subir primero a **prueba interna** antes de producción
- [ ] Guardar nota de qué cambió (para el changelog de la tienda)

---

*Documentación de actualizaciones y tiendas — Grupo Fercadi*  
*Versión: Junio 2026*
