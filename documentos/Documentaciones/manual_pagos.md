# Manual de Pagos y Costos — GOGO Food
### Grupo Fercadi | Maravatío, Michoacán

---

## Métodos de Pago Disponibles

| Método | Estado | Requiere internet |
|---|---|---|
| **Efectivo** | ✅ Activo | No (el repartidor cobra en mano) |
| **Tarjeta (Stripe)** | ✅ Activo (modo prueba) | Sí |
| **OXXO Pay** | ⚠️ Parcial (webhook pendiente) | Sí |

---

## 1. Pago en Efectivo

El más sencillo. No hay integración técnica.

```
Cliente elige "Efectivo" en checkout
    → Se crea el pedido en Supabase
    → Repartidor entrega y cobra en mano
    → El dueño registra el pago manualmente
```

**Riesgo:** No hay verificación digital del pago. Depende de la honestidad del repartidor.

---

## 2. Pago con Tarjeta — Stripe

### Flujo completo

```
Cliente toca "Pagar con tarjeta"
    │
    ▼
checkout_screen.dart llama a Supabase Edge Function
    │  Envía: monto en centavos MXN, moneda "mxn"
    ▼
Edge Function "create-payment-intent"
    │  Usa la clave secreta de Stripe (sk_...)
    │  Crea el cobro en Stripe
    ▼
Stripe devuelve clientSecret (token único de un solo uso)
    │
    ▼
App abre el PaymentSheet de Stripe (pantalla nativa)
    │  Cliente ingresa: número de tarjeta, fecha, CVV
    │  Stripe valida con el banco del cliente
    ▼
Banco aprueba → Pago confirmado
    │
    ▼
App crea el pedido en Supabase con status = "pending"
```

### Claves de Stripe

| Clave | Prefijo | Dónde va |
|---|---|---|
| Publishable key | `pk_test_...` / `pk_live_...` | `lib/core/constants.dart` |
| Secret key | `sk_test_...` / `sk_live_...` | Supabase → Edge Functions → Secrets |

> ⚠️ La clave **secreta** (`sk_...`) **NUNCA** va en el código del cliente. Solo en el servidor (Supabase Edge Function).

### Tarjetas de prueba (modo test)

Para probar sin dinero real:

| Número de tarjeta | Resultado |
|---|---|
| `4242 4242 4242 4242` | Pago aprobado |
| `4000 0000 0000 0002` | Pago rechazado |
| `4000 0025 0000 3155` | Requiere autenticación 3D Secure |

CVV y fecha: cualquier valor válido (ej. `123` y `12/29`).

### Pasar a producción

1. Cambiar `pk_test_...` → `pk_live_...` en `lib/core/constants.dart`
2. Cambiar `sk_test_...` → `sk_live_...` en Supabase → Edge Functions → Secrets
3. Verificar que la cuenta bancaria (CLABE) está registrada en Stripe Dashboard
4. Compilar y hacer deploy

---

## 3. OXXO Pay

```
Cliente elige "OXXO" → Stripe genera número de referencia
→ Cliente va al OXXO y paga con ese número
→ OXXO notifica a Stripe (puede tardar 1-3 días)
→ Stripe manda webhook a Supabase
→ Pedido se actualiza como pagado
```

**Estado actual:** La opción aparece en la UI pero el webhook de OXXO no está configurado en Supabase. Pendiente de implementar.

---

## 4. Comisiones de Stripe (Producción)

Cada vez que un cliente paga con tarjeta, Stripe descuenta su comisión automáticamente antes de depositar:

| Tipo de tarjeta | Comisión por transacción |
|---|---|
| Nacional (México) | **3.6% + $3 MXN** |
| Internacional | **4.6% + $3 MXN** |

### Ejemplo con pedido de $150 MXN

```
$150.00 × 3.6%  =  $5.40
               +   $3.00 (fijo)
               = $8.40 que se queda Stripe
               = $141.60 que recibe Fercadi
```

Stripe deposita el saldo neto a la cuenta bancaria registrada (transferencias cada 2-7 días hábiles).

---

## 5. Costos de Todos los Servicios

### Tabla resumen

| Servicio | Ahora (desarrollo) | Al lanzar | Mensual en producción |
|---|---|---|---|
| **Stripe** | Gratis (prueba) | Activar claves live | 3.6% + $3 MXN por transacción |
| **Supabase** | Gratis | Pagar Pro desde día 1 | **$25 USD/mes** (~$500 MXN) |
| **Vercel** | Gratis | Gratis | $0 (o $20 USD con dominio propio) |
| **Google Maps** | Gratis | Gratis | $0 (< 28,500 cargas/mes) |
| **Google Play** | N/A | **$25 USD** (único pago) | $0 |
| **Apple Store** | N/A | **$99 USD/año** | $8.25 USD/mes |
| **FCM (notificaciones)** | Gratis | Gratis siempre | $0 |
| **Sentry (errores)** | No activo | Gratis al inicio | $0 |

### ¿Por qué Supabase Pro es obligatorio al lanzar?

El plan **gratuito** pausa la base de datos después de **7 días sin actividad**. Cuando alguien intenta hacer un pedido, la primera petición tarda ~30 segundos en "despertar" la BD. Eso es inaceptable para una app de delivery.

El plan **Pro ($25 USD/mes)** nunca pausa la BD, tiene backups diarios automáticos y soporta hasta 2 millones de llamadas a Edge Functions por mes.

### Costo mínimo para lanzar

```
Sin iOS:   $50 USD = $25 Supabase Pro + $25 Google Play
Con iOS:  $149 USD = $50 anterior    + $99 Apple Developer
```

### Costo mensual fijo

```
Mínimo: $25 USD/mes  (Supabase Pro)
Normal: $45 USD/mes  (Supabase + Vercel con dominio propio)
```

---

## 6. Problemas Comunes en Pagos

### Edge Function devuelve error 500
**Cuándo:** Al intentar pagar con tarjeta.  
**Causa más común:**
1. La variable `STRIPE_SECRET_KEY` no está en Supabase → Edge Functions → Secrets
2. La Edge Function `create-payment-intent` no está deployada en Supabase
3. La clave secreta de Stripe es incorrecta o de otro proyecto

### Pago cobrado pero pedido no creado
**Cuándo:** Si la app se cierra entre el cobro de Stripe y la creación del pedido.  
**Solución temporal:** Verificar en Stripe Dashboard si el cobro existe → contactar al cliente → reembolsar manualmente si es necesario.  
**Solución definitiva:** Configurar webhook de Stripe que crea el pedido automáticamente cuando Stripe confirma el pago.

### PaymentSheet no abre en web
**Causa:** `flutter_stripe` tiene soporte limitado en web. El PaymentSheet está diseñado para apps nativas.  
**Solución a futuro:** Implementar Stripe Elements para web.

### Tarjeta rechazada sin mensaje claro
**Diagnóstico:** Stripe Dashboard → Payments → buscar el intento fallido → tiene el código exacto del banco.

### Modo prueba activo en producción
**Verificación:** Si `stripePublishableKey` en `constants.dart` empieza con `pk_test_`, está en modo prueba y no cobra dinero real.

---

## 7. Checklist para Activar Pagos Reales

- [ ] Crear cuenta en [dashboard.stripe.com](https://dashboard.stripe.com) con datos del negocio
- [ ] Registrar CLABE bancaria (18 dígitos) para recibir depósitos
- [ ] Verificar identidad del negocio en Stripe (INE + comprobante de domicilio)
- [ ] Copiar `pk_live_...` → `lib/core/constants.dart`
- [ ] Poner `sk_live_...` en Supabase → Edge Functions → Secrets → `STRIPE_SECRET_KEY`
- [ ] Configurar webhook de Stripe apuntando a una Edge Function de Supabase
- [ ] Hacer prueba de pago real con $1 MXN antes de lanzar
- [ ] Compilar y hacer deploy con las claves live

---

*Grupo Fercadi — GOGO Food | Junio 2026*
