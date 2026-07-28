# Manual de Widgets de Pantalla de Inicio (iOS) — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## ¿Qué son?

Widgets nativos de iOS (WidgetKit) que el cliente puede agregar a su pantalla de inicio para ver el estado de su pedido sin abrir la app. Requiere iOS 17+ (usan la API `containerBackground`). Ver también [`manual_ios.md`](manual_ios.md) para todo lo relacionado con instalar/compilar en iPhone.

Target nativo: `GOGOTrackingWidget`, código en `ios/GOGOTrackingWidget/GOGOTrackingWidget.swift`.

---

## 1. Los dos widgets

| Widget (kind) | Tamaño | Qué muestra |
|---|---|---|
| `GOGOTrackingWidget` | Pequeño / Mediano | Mini-mapa (`MKMapSnapshotter`) con la posición del restaurante, el repartidor y el cliente |
| `GOGOTrackingStepsWidget` | Mediano | Tarjeta con los 4 pasos del pedido — mismo diseño y colores que la pantalla de seguimiento de la app |

Ambos están agrupados en `GOGOWidgetBundle` (`@main`).

### Colores de la tarjeta de pasos (igual que `tracking_screen.dart`)

- **Paso completado:** verde
- **Paso actual:** azul
- **Paso futuro:** blanco muy transparente (`opacity 0.15`)
- Fondo de la tarjeta: naranja (color de marca)

---

## 2. Cómo comparten datos con la app

La app y el widget viven en procesos separados (la extensión de widget no puede leer memoria de la app). Comparten datos mediante:

- **App Group:** `group.com.fercadi.app` (declarado en `Runner.entitlements` y `GOGOTrackingWidget.entitlements`)
- **Paquete Flutter `home_widget`:** `lib/screens/tracking_screen.dart` → `_updateHomeWidget()` guarda en cada actualización de estado: `hasActiveOrder`, `orderId`, `authToken`, `restaurantName`, `statusText`, `address`, `total`, `stepIndex`, y las coordenadas de restaurante/repartidor/cliente
- Después de guardar, llama `HomeWidget.updateWidget(iOSName: ...)` para forzar el refresco inmediato de ambos widgets

---

## 3. Actualización en segundo plano (sin abrir la app)

Antes: el widget solo se actualizaba cuando el usuario abría la app (porque solo ahí se escriben los datos compartidos).

Ahora el widget **también se puede refrescar solo**, sin que la app esté abierta: `refreshOrderFromSupabase()` en el Swift del widget hace una consulta **directa a Supabase** (REST/PostgREST, con el token guardado en el App Group) para traer el estado más reciente del pedido antes de dibujar el timeline.

> Esta es la opción **gratuita**. La alternativa (notificaciones push vía APNs para forzar el refresco al instante en cuanto cambia el pedido) requiere cuenta Apple Developer de pago — ver [`manual_ios.md`](manual_ios.md#4-publicar-en-app-store-cuando-se-pague-la-cuenta). Por ahora el widget se refresca solo, con un intervalo (no instantáneo como el push).

---

## 4. Archivos relevantes

```
ios/GOGOTrackingWidget/
├── GOGOTrackingWidget.swift       ← Todo el código: providers, vistas, mapa, tarjeta
├── Info.plist                     ← Mínimo, depende de GENERATE_INFOPLIST_FILE
└── GOGOTrackingWidget.entitlements← App Group

ios/Runner/Runner.entitlements     ← Mismo App Group, lado de la app
lib/screens/tracking_screen.dart   ← _updateHomeWidget(): escribe los datos
lib/main.dart                      ← HomeWidget.setAppGroupId(...) al iniciar
```

---

## 5. Problemas ya resueltos (para no repetir el diagnóstico)

| Síntoma | Causa | Solución |
|---|---|---|
| Ícono de "no disponible" en el mapa del widget | iOS pausa la descarga de tiles de mapa en segundo plano (`dasd`, throttling del sistema) | Cambiar de `Map` declarativo a `MKMapSnapshotter` imperativo con timeout explícito (4s) y vista de reserva si falla |
| Warning "Please adopt containerBackground API" | iOS 17+ exige `.containerBackground()` en vez de fondo manual con `ZStack` | Helper `widgetBackground()` con chequeo de disponibilidad |
| "Embedded binary's bundle identifier is not prefixed..." al compilar | `GENERATE_INFOPLIST_FILE = NO` en el target del widget, no inyectaba el bundle id | Cambiar a `YES` |
| "does not have a CFBundleVersion..." | Faltaban `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` en el target del widget | Agregarlos en build settings |
| Ciclo de dependencias al compilar | Fase "Embed Foundation Extensions" estaba después de "Thin Binary"/CocoaPods en el orden de build phases | Moverla justo después de "Embed Frameworks" |

---

*Grupo Fercadi — GOGO Food | Julio 2026*
