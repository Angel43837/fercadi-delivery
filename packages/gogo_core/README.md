# gogo_core

Código compartido por las tres apps de GOGO Food:

| App | Repo | Cómo usa gogo_core |
|---|---|---|
| GOGO Food (cliente, dueño, repartidor) | [fercadi-delivery](https://github.com/Angel43837/fercadi-delivery) | Directo de esta carpeta (`path: packages/gogo_core`): siempre la última versión |
| GOGO Admin | [GOGO-ADMIN](https://github.com/Angel43837/GOGO-ADMIN) | Desde git, fijado a un tag |
| GOGO Flota | [gogo-flota](https://github.com/Angel43837/gogo-flota) | Desde git, fijado a un tag |

Contiene `services/` (Supabase, auth, ubicación), `models/`, `core/` (constantes, textos legales, categorías), `repositories/` de retiros y `providers/app_data_provider.dart`.

**Un arreglo en estos archivos se hace AQUÍ, una sola vez.** Ninguna app tiene copia propia.

## Cómo lo usan Admin y Flota

```yaml
dependencies:
  gogo_core:
    git:
      url: https://github.com/Angel43837/fercadi-delivery.git
      path: packages/gogo_core
      ref: gogo-core-v1.0.0
```

```dart
import 'package:gogo_core/services/supabase_service.dart';
```

## Sacar una versión nueva

1. Haz el cambio aquí (rama `dev` de fercadi-delivery), `flutter analyze` sin errores, commit y push. GOGO Food ya lo usa en ese momento.
2. Sube `version:` en este `pubspec.yaml`, anota el cambio en `CHANGELOG.md` y crea el tag:
   ```bash
   git tag gogo-core-v1.0.1
   git push origin gogo-core-v1.0.1
   ```
3. En GOGO-ADMIN y gogo-flota: cambia `ref: gogo-core-v1.0.1` en su `pubspec.yaml`, corre `flutter pub get`, prueba y haz commit.

Versiones: `1.0.x` arreglos, `1.x.0` cosas nuevas que no rompen nada, `x.0.0` cambios que obligan a tocar las apps.

## Probar un cambio en Admin o Flota antes de sacar versión

En GOGO-ADMIN o gogo-flota, con fercadi-delivery clonado al lado, crea `pubspec_overrides.yaml` (no se sube, está en su `.gitignore`):

```yaml
dependency_overrides:
  gogo_core:
    path: ../fercadi-delivery/packages/gogo_core
```

Bórralo al terminar.
