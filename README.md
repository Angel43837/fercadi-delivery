# GOGO Food — Grupo Fercadi

App de delivery de comida para Maravatío, Michoacán. Flutter + Supabase + Stripe.

Permite a los clientes pedir comida desde su teléfono o navegador, a los dueños de restaurante gestionar su menú y pedidos, a los repartidores entregar con rastreo GPS en tiempo real, y a los administradores supervisar toda la operación.

## Documentación

Toda la documentación del proyecto vive en [`documentos/`](documentos/):

- [`documentos/CLAUDE.md`](documentos/CLAUDE.md) — guía rápida (stack, roles, temas, deploy, pendientes)
- [`documentos/Documentaciones/`](documentos/Documentaciones/) — arquitectura, manuales de frontend/backend/pagos/despliegue/actualizaciones
- [`documentos/sesiones/`](documentos/sesiones/) — bitácora de sesiones de desarrollo
- [`documentos/Manual_Usuario/`](documentos/Manual_Usuario/) — manual para el usuario final

## Correr el proyecto

```bash
flutter pub get
flutter run -d chrome              # Web
flutter run -d emulator-5554       # Android
flutter run -d <id-del-iphone>     # iOS (requiere cable + Mac con Xcode)
```

Datos de prueba: `lib/services/supabase_service.dart` → `useMock = true`.
Con Supabase real: `useMock = false` + credenciales en `lib/core/constants.dart`.

## Stack

Flutter (Dart) · Supabase (BD/Auth/Storage/Realtime) · Stripe (pagos) · go_router · provider.

Ver [`documentos/Documentaciones/arquitectura.md`](documentos/Documentaciones/arquitectura.md) para el detalle completo.
