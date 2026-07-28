# Manual de iOS / iPhone — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## Estado actual

La app **ya corre en iPhones físicos** (incluye la app cliente y los widgets de pantalla de inicio, ver [`manual_widgets.md`](manual_widgets.md)), pero todavía con una **cuenta Apple Developer gratuita ("Personal Team")**, no la de pago. Eso trae limitaciones importantes que hay que tener claras antes de intentar instalar la app en un iPhone nuevo.

---

## 1. Limitaciones de la cuenta gratuita

- **No hay forma de compartir un link de descarga.** Ni TestFlight ni App Store funcionan sin cuenta de pago ($99 USD/año). La única forma de instalar la app en un iPhone es **conectarlo por cable** a la Mac que tiene el proyecto y compilar directo ahí.
- **Máximo ~10 dispositivos registrados por año** en la cuenta gratuita.
- Cada certificado de desarrollo dura 7 días si no se renueva (no suele ser problema si se sigue compilando seguido).

---

## 2. Instalar la app en un iPhone nuevo (paso a paso)

1. **Conectar el iPhone por cable** a la Mac
2. En el iPhone: **Configuración → Privacidad y Seguridad → Modo de desarrollador** → activarlo (pide reiniciar el teléfono — solo la primera vez por dispositivo)
3. Al reconectar y desbloquear el teléfono, va a salir el aviso **"¿Confiar en esta computadora?"** → aceptar (puede pedir el código del teléfono)
4. Compilar e instalar:
   ```bash
   flutter run --release -d <id-del-dispositivo>
   # el id se obtiene con: flutter devices
   ```
5. **Si el ícono aparece pero la app no abre**, es porque iOS todavía no confía en el certificado del desarrollador:
   En el iPhone → **Configuración → General → VPN y administración de dispositivos** → seleccionar el perfil del desarrollador (algo como "Apple Development: correo@...") → **Confiar**

### Si el dispositivo da error al compilar/instalar

| Error | Causa | Solución |
|---|---|---|
| `iPhone may need to be unlocked to recover from previously reported preparation errors` | El teléfono está bloqueado | Desbloquear la pantalla y reintentar |
| `Luis david iPhone... is not available because it is unpaired` | Falta confiar en la computadora o activar Modo Desarrollador | Repetir pasos 2-3 de arriba |
| `Could not run build/ios/iphoneos/Runner.app on <id>` (genérico) | El dispositivo nunca se registró en la cuenta de desarrollador | Registrarlo manualmente (ver abajo) |

**Registrar un dispositivo nuevo manualmente** (cuando `flutter run` no lo hace solo):
```bash
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination "id=<UDID-del-dispositivo>" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build
```
El UDID clásico (el que usa `flutter run`, distinto al identificador de `devicectl`) se obtiene con:
```bash
xcrun xctrace list devices
```

### El error de "Inicia sesión con cuenta escolar o de trabajo"

Si alguien intenta instalar la app por otro medio (un link, un archivo raro) puede salirle esta pantalla — es la inscripción a **MDM (administración remota de dispositivos)** de Apple, **no tiene nada que ver** con instalar esta app. Con cuenta gratuita ese camino no aplica: siempre hay que instalar por cable como arriba.

---

## 3. Flavor "GOGO Admin" en iOS

La app admin (`com.fercadi.admin`) es un segundo target/flavor dentro del mismo proyecto de Xcode, separado de la app cliente (`com.fercadi.app`):

- `ios/Runner/Info-Admin.plist` — nombre "GOGO Admin", esquema de URL `fercadiadmin://`
- `ios/Flutter/Debug-admin.xcconfig`, `Release-admin.xcconfig`, `Profile-admin.xcconfig`
- Se corre con: `flutter run --flavor admin --target lib/main_admin.dart`

---

## 4. Publicar en App Store (cuando se pague la cuenta)

> **Requisito:** Mac con Xcode. No se puede compilar para iOS desde Windows.
> **Costo:** $99 USD/año — cuenta Apple Developer.

1. Crear cuenta en [developer.apple.com](https://developer.apple.com)
2. Registrar Bundle ID: `com.fercadi.gogofood`
3. Crear certificados de distribución en el portal de Apple Developer
4. Compilar: `flutter build ipa --release`
5. Subir con Xcode o Transporter a App Store Connect
6. Esperar revisión de Apple: 1-7 días hábiles (más estricta que Google)

Apple rechaza apps que no tengan política de privacidad, no expliquen el uso del GPS/cámara, o no cumplan sus guías de diseño (Human Interface Guidelines).

Una vez pagada la cuenta, además se habilita **TestFlight** (compartir la app por link sin pasar por revisión completa) y **notificaciones push nativas** (APNs) para los widgets — ver [`manual_widgets.md`](manual_widgets.md).

---

*Grupo Fercadi — GOGO Food | Julio 2026*
