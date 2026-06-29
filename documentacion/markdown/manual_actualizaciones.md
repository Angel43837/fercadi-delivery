# Manual de Actualizaciones y Publicación en Tiendas — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿Qué pasa cuando se actualiza la app?

```
Se modifica el código
        │
        ▼
Se compila (flutter build)
        │
        ├── Web ──────► Se sube a Vercel ──────────► Usuarios lo ven en segundos
        │
        ├── Android ──► Se sube a Play Store ──────► Google revisa 1-3 días
        │                                             → Usuarios reciben notificación
        │
        └── iOS ──────► Se sube a App Store ────────► Apple revisa 1-7 días
                                                       → Usuarios reciben notificación
```

> **Los datos en Supabase NUNCA se tocan al actualizar.** Pedidos, usuarios, restaurantes, fotos — todo queda igual. Solo cambia la app instalada en el teléfono.

---

## 1. Numeración de Versiones

El número de versión está en `pubspec.yaml`:

```yaml
version: 1.0.0+1
#        │ │ │  └── Build number: entero que DEBE aumentar en cada subida a tienda
#        │ │ └────── Patch: corrección de bugs menores
#        │ └──────── Minor: funcionalidad nueva sin romper nada
#        └────────── Major: cambio grande o rediseño completo
```

| Tipo de cambio | Ejemplo | Versión anterior | Versión nueva |
|---|---|---|---|
| Bug menor | Imagen rota | `1.0.0+1` | `1.0.1+2` |
| Función nueva | Panel de flota | `1.0.1+2` | `1.1.0+3` |
| Rediseño | Nueva UI completa | `1.4.2+10` | `2.0.0+11` |

> Play Store y App Store rechazan el build si el `build number` no es mayor al anterior.

---

## 2. Actualizar la Versión Web

La web es el canal más rápido — en menos de 2 minutos todos los usuarios ven la nueva versión.

```powershell
# 1. Compilar
flutter build web --release --pwa-strategy=none

# 2. Copiar config de Vercel
Copy-Item vercel.json build/web/vercel.json -Force

# 3. Subir a producción
cd build/web
npx vercel --prod --archive=tgz
```

### ¿Qué pasa con los usuarios en ese momento?

- Siguen viendo la versión anterior hasta que recarguen la página
- Al recargar (`F5` o `Ctrl+R`) ven la nueva versión automáticamente
- Si necesitan forzar la carga: `Ctrl+Shift+R`

---

## 3. Actualizar la App Android (Play Store)

### Configuración única (primera vez)

1. **Crear el keystore** (firma digital — se hace UNA SOLA VEZ):
   ```powershell
   keytool -genkey -v -keystore gogofood.keystore -alias gogofood -keyalg RSA -keysize 2048 -validity 10000
   ```
   > ⚠️ **CRÍTICO:** Si se pierde el keystore, nunca más se puede actualizar la app en Play Store. Guardar en Drive, USB y correo.

2. **Crear cuenta de desarrollador:** [play.google.com/console](https://play.google.com/console) — $25 USD pago único.

3. **Primera publicación:** Crear la app en Play Console, llenar ficha (descripción, capturas, política de privacidad) y subir el APK.

### Para cada actualización

```powershell
# 1. Incrementar el número de versión en pubspec.yaml
#    version: 1.0.0+1  →  version: 1.0.1+2

# 2. Generar el nuevo APK
.\build_apks.ps1

# 3. En play.google.com/console:
#    → Tu app → Producción → Crear nueva versión → Subir APK → Publicar
```

### Tiempos del proceso

| Etapa | Tiempo |
|---|---|
| Compilar APK | 2-5 minutos |
| Subir a Play Console | 2-5 minutos |
| Revisión de Google | 1-3 días hábiles |
| Disponible para usuarios | Inmediato tras aprobación |

### Tipos de versiones en Play Store

| Tipo | Para qué |
|---|---|
| **Prueba interna** | Solo el equipo Fercadi (hasta 100 personas, sin revisión) |
| **Beta cerrada** | Testers elegidos antes del lanzamiento |
| **Producción** | Todos los usuarios |

---

## 4. Publicar en App Store de Apple (futuro)

> **Requisito:** Una Mac con Xcode instalado. No se puede compilar para iOS desde Windows.

**Costo:** $99 USD/año — Cuenta Apple Developer.

```bash
# En la Mac con Xcode
flutter build ipa --release
# Subir .ipa con Xcode o Transporter
# Luego en App Store Connect → Nueva versión → Subir build
```

### Tiempos

| Etapa | Tiempo |
|---|---|
| Compilar IPA en Mac | 5-15 minutos |
| Subir a App Store Connect | 5-10 minutos |
| Revisión de Apple | 1-7 días |

Apple rechaza apps que no tengan política de privacidad, no expliquen el uso del GPS/cámara o no cumplan sus guías de diseño (Human Interface Guidelines).

---

## 5. ¿Qué Necesita Actualización de App vs Qué No?

| Cambio | ¿Requiere compilar y subir? | ¿Requiere revisión de tienda? |
|---|---|---|
| Nueva pantalla o botón | ✅ Sí | ✅ Sí |
| Corrección de bug visual | ✅ Sí | ✅ Sí |
| Nuevo restaurante en la BD | ❌ No | ❌ No |
| Cambio de precio de producto | ❌ No | ❌ No |
| Nueva foto de producto | ❌ No | ❌ No |
| El dueño agrega categoría | ❌ No (él lo hace solo) | ❌ No |

El panel del dueño (`/dueno`) permite actualizar precios, productos y fotos **sin tocar el código** — los cambios se reflejan en tiempo real.

---

## 6. ¿Qué Datos se Pierden al Actualizar?

| Dato | Dónde vive | ¿Se afecta al actualizar? |
|---|---|---|
| Pedidos | Supabase (nube) | ❌ Nunca |
| Restaurantes y menús | Supabase (nube) | ❌ Nunca |
| Fotos de productos | Supabase Storage | ❌ Nunca |
| Sesión del usuario | SharedPreferences (teléfono) | ❌ El usuario sigue logueado |
| Carrito actual | Memoria RAM de la app | ⚠️ Se pierde si se cierra la app (es normal) |
| Dirección guardada | SharedPreferences | ❌ No, se conserva |

---

## 7. Checklist Antes de Subir Actualización

- [ ] Incrementar `build number` en `pubspec.yaml`
- [ ] Probar en web local: `flutter run -d chrome`
- [ ] Probar en Android: emulador o dispositivo real
- [ ] Verificar que login, carrito y pago funcionan correctamente
- [ ] Para Play Store: keystore disponible y accesible
- [ ] Subir primero a **prueba interna**, luego a producción
- [ ] Guardar nota de qué cambió (para el changelog de la tienda)

---

*Grupo Fercadi — GOGO Food | Junio 2026*
