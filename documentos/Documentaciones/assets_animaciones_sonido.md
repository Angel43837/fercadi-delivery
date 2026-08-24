# Estructura de Assets — Animaciones & Sonido
**GOGO Food · Grupo Fercadi · Flutter + Supabase**

---

## Dónde van los archivos

```
assets/
├── images/                        ← ya existe
│   └── logo.png, banner_rider.png …
│
├── animations/                    ← NUEVO
│   ├── lottie/                    ← archivos .json (After Effects / LottieFiles)
│   │   ├── pedido_enviado.json    ← check animado al confirmar pedido
│   │   ├── cargando.json          ← spinner de carga
│   │   └── moto_en_camino.json    ← moto animada en tracking
│   │
│   └── rive/                      ← archivos .riv (animaciones con estados)
│       └── rider_status.riv       ← moto idle → en movimiento → llegó
│
└── sounds/                        ← NUEVO
    └── sfx/                       ← efectos cortos (.mp3)
        ├── nuevo_pedido.mp3        ← notificación al repartidor
        ├── pedido_aceptado.mp3     ← confirmación al cliente
        └── coins_ganados.mp3       ← gamificación repartidor plus
```

---

## Paquetes a agregar

| Paquete | Versión | Para qué |
|---|---|---|
| `lottie` | `^3.1.3` | Animaciones decorativas exportadas de After Effects o LottieFiles |
| `rive` | `^0.13.19` | Animaciones con estados (idle → activo → completado). Se diseña en rive.app |
| `audioplayers` | `^6.1.0` | Efectos de sonido cortos, notificaciones, feedback de gamificación |
| `just_audio` | `^0.9.40` | *(opcional)* Si se necesita música de fondo con loop. No necesitas ambos |

Todos soportan Web, Android e iOS.

---

## Cambios en pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  # ... dependencias existentes ...

  # Animaciones
  lottie: ^3.1.3
  rive: ^0.13.19

  # Sonido
  audioplayers: ^6.1.0

flutter:
  uses-material-design: true

  assets:
    - assets/images/              # ya existe
    - assets/animations/lottie/  # nuevo
    - assets/animations/rive/    # nuevo
    - assets/sounds/sfx/         # nuevo
```

---

## Formatos y cuándo usar cada uno

| Formato | Tipo | Cuándo usarlo | Peso aprox. |
|---|---|---|---|
| `.json` (Lottie) | Animación | Animaciones decorativas exportadas de After Effects o descargadas de LottieFiles | 5–100 KB |
| `.riv` (Rive) | Animación | Cuando la animación tiene estados. Se diseña en rive.app | 50–300 KB |
| `.mp3` | Sonido | Efectos cortos (<3 seg): notificaciones, feedback, coins | 10–80 KB |
| `.ogg` | Sonido | Alternativa a .mp3 con mejor compresión para Android | 5–50 KB |
| `.wav` | Sonido | Máxima calidad sin compresión (poco recomendado por el peso) | 100 KB+ |

---

## Cómo se usan en el código

**Lottie — animación decorativa**
```dart
import 'package:lottie/lottie.dart';

Lottie.asset(
  'assets/animations/lottie/pedido_enviado.json',
  width: 200,
  repeat: false, // solo 1 vez
)
```

**Rive — animación con estados**
```dart
import 'package:rive/rive.dart';

RiveAnimation.asset(
  'assets/animations/rive/rider_status.riv',
  animations: ['idle'],
)
```

**audioplayers — reproducir sonido**
```dart
import 'package:audioplayers/audioplayers.dart';

final player = AudioPlayer();

// Reproducir al aceptar pedido
await player.play(AssetSource('sounds/sfx/pedido_aceptado.mp3'));
```

---

## Dónde descargar assets gratis

| Recurso | URL | Tipo |
|---|---|---|
| LottieFiles | lottiefiles.com | Lottie `.json` |
| useAnimations | useanimations.com | Lottie `.json` |
| Rive Community | rive.app/community | Rive `.riv` |
| Mixkit | mixkit.co/free-sound-effects | Sonidos `.mp3` |
| Freesound | freesound.org | Sonidos `.mp3 / .wav` |

---

> **Nota:** No superar **50 KB por archivo Lottie** ni **80 KB por sonido** para no inflar el APK. Los archivos Rive suelen ser más pesados pero se cargan una sola vez. En web todos los assets se descargan al primer acceso — usar con moderación.
