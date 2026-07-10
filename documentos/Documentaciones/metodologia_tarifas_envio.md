# Metodología de Tarifas de Envío — GOGO Food

## ¿Cómo se calcula el costo de envío?

El costo de envío se calcula en el momento en que el cliente llega al checkout, usando la distancia real entre el restaurante y la dirección del cliente.

**Fórmula:**

```
Costo de envío = Tarifa base + (Tarifa por km × distancia en km)
```

**Ejemplo con valores actuales:**

| Variable | Valor | Descripción |
|---|---|---|
| Tarifa base | $15.00 MXN | Se cobra siempre, sin importar la distancia |
| Tarifa por km | $5.00 MXN/km | Se suma por cada km de distancia |
| Distancia | 3 km | Entre el restaurante y la dirección del cliente |
| **Total envío** | **$30.00 MXN** | `15 + (5 × 3) = $30` |

---

## ¿De dónde viene la distancia?

La distancia se calcula con la función `Geolocator.distanceBetween()`, que usa la fórmula de Haversine entre dos coordenadas GPS:

- **Origen:** las coordenadas `(lat, lng)` del restaurante, guardadas en la tabla `restaurants` de Supabase
- **Destino:** la posición GPS del cliente (del dispositivo) o la dirección que escribió manualmente

```dart
// checkout_screen.dart
final distanciaKm = Geolocator.distanceBetween(
  restaurante.lat,
  restaurante.lng,
  posicionCliente.latitude,
  posicionCliente.longitude,
) / 1000;   // metros → kilómetros
```

Si no se tienen las coordenadas del restaurante o el cliente no dio permiso de GPS, se cobra únicamente la **tarifa base** ($15.00 MXN).

---

## ¿Dónde están definidas las tarifas?

Las tarifas se guardan en la tabla `platform_config` de Supabase:

| Clave | Valor por defecto | Descripción |
|---|---|---|
| `tarifa_base` | `15.0` | Cuota base en MXN |
| `tarifa_por_km` | `5.0` | Costo adicional por km en MXN |

El admin de la plataforma puede cambiarlas desde el panel **Admin → Config** sin tocar código. Los cambios aplican inmediatamente para todos los pedidos nuevos.

El archivo `lib/services/location_service.dart` las carga al inicio de la app con `LocationService.loadTarifas()` y las guarda en variables estáticas que usa `calcularCostoEnvio()`.

---

## Flujo completo

```
Cliente llega a Checkout
        │
        ├── ¿Tiene coordenadas de GPS?
        │       Sí → Geolocator.distanceBetween(restaurante, cliente) / 1000
        │       No → distanciaKm = null
        │
        ▼
LocationService.calcularCostoEnvio(distanciaKm)
        │
        ├── distanciaKm == null → devuelve tarifaBase ($15)
        │
        └── distanciaKm > 0   → devuelve tarifaBase + (tarifaPorKm × km)
                                         $15      +    ($5     × km)
        ▼
Se guarda en orders.delivery_fee al crear el pedido
```

---

## ¿Quién puede cambiar las tarifas?

Solo el usuario con rol `admin` (panel oscuro de Grupo Fercadi).

**Ruta:** Panel Admin → tab "Config" → sección "Tarifas de Envío"

Desde ahí se puede cambiar la tarifa base y la tarifa por km. El cambio se guarda en Supabase y aplica para todos los clientes en el próximo pedido.

---

## SQL necesario (ejecutar una sola vez en Supabase)

```sql
-- Crear tabla de configuración de la plataforma
CREATE TABLE IF NOT EXISTS platform_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Valores por defecto
INSERT INTO platform_config (key, value) VALUES
  ('tarifa_base',    '15.0'),
  ('tarifa_por_km',  '5.0')
ON CONFLICT (key) DO NOTHING;

-- RLS: todos pueden leer, solo admin puede escribir
ALTER TABLE platform_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lectura pública" ON platform_config
  FOR SELECT USING (true);

CREATE POLICY "Solo admin puede modificar" ON platform_config
  FOR ALL USING (
    auth.jwt() -> 'user_metadata' ->> 'role' = 'admin'
  );
```

---

## Tabla de cambios rápidos

| ¿Qué quieres cambiar? | Dónde |
|---|---|
| Tarifa base o por km | Panel Admin → Config (sin tocar código) |
| Fallback si Supabase falla | `location_service.dart` → `tarifaBase` / `tarifaPorKm` |
| Fórmula de cálculo | `location_service.dart` → `calcularCostoEnvio()` |
| Radio de cobertura del municipio | `location_service.dart` → `_radioMetros` |
