# Sistema de Coins y Tienda — GOGO Food Rider

## ¿De qué trata esto?

Los repartidores independientes (los que se registran solos, no los de la flota) van a ganar **coins** en cada entrega que hagan. Esos coins los pueden gastar en una tienda dentro de la app para canjear premios digitales como tarjetas de Spotify, Netflix, OXXO Pay, etc.

Los coins **no son dinero real** — son puntos de la app. Pero se pueden convertir en cosas de valor.

---

## ¿Quién tiene acceso a esto?

| Tipo de repartidor | ¿Tiene coins y tienda? |
|---|---|
| Repartidor independiente (repartidor_plus) | ✅ Sí |
| Repartidor de flota | ❌ No — ellos tienen sueldo fijo |

---

## ¿Cómo gana coins el rider?

Cada vez que completa una entrega, la app le suma coins automáticamente.

```
Rider entrega un pedido
        ↓
La app le suma coins
(ejemplo: 10 coins por km recorrido)
        ↓
El saldo aparece en su pantalla principal
```

El rider puede ver su saldo de coins en todo momento en la pantalla principal.

---

## ¿Cómo funciona la tienda?

El rider entra a la tienda, ve los productos disponibles con su precio en coins, y si tiene suficientes los canjea.

```
Rider entra a la Tienda
        ↓
Ve: "Tarjeta Spotify 1 mes — 500 coins"
        ↓
Toca "Canjear"
        ↓
La app descuenta 500 coins de su saldo
        ↓
Le aparece en pantalla el código de activación
        ↓
El rider activa su Spotify con ese código
        ↓
El código ya no existe en el sistema — se fue
```

**Nadie tiene que hacer nada manualmente.** Todo es automático.

---

## ¿Cómo se cargan los premios al sistema?

Cuando usted compra una tarjeta de Spotify (o cualquier otra), tiene un código de activación. Ese código se carga al sistema y queda esperando a que alguien lo canjee.

**Ejemplo:**

Usted compra 5 tarjetas de Spotify y recibe 5 códigos:
```
SPOT-1111-AAAA
SPOT-2222-BBBB
SPOT-3333-CCCC
SPOT-4444-DDDD
SPOT-5555-EEEE
```

Esos 5 códigos se guardan en el sistema. Cuando 5 riders los canjeen, los códigos se agotan y el producto desaparece de la tienda hasta que usted cargue más.

---

## ¿Dónde se guardan todos estos datos?

Todo vive en **Supabase** — la base de datos que ya usa la app. No se necesita ningún servicio externo.

Se crean 3 tablas nuevas:

### Tabla 1 — Catálogo de productos
Guarda qué productos están disponibles en la tienda.

| Campo | Ejemplo |
|---|---|
| Nombre | Tarjeta Spotify 1 mes |
| Imagen | (foto de la tarjeta) |
| Precio en coins | 500 |
| Disponible | Sí / No |

### Tabla 2 — Inventario de códigos
Guarda cada código que usted cargue. Cuando alguien lo canjea, se marca como usado y ya no se puede volver a usar.

| Campo | Ejemplo |
|---|---|
| Producto | Spotify 1 mes |
| Código | SPOT-1111-AAAA |
| ¿Usado? | No → Sí (cuando se canjea) |
| ¿Quién lo usó? | Carlos Rider |
| ¿Cuándo? | 01/07/2026 |

### Tabla 3 — Historial de coins
Guarda cada ganancia y cada gasto de coins de cada rider.

| Campo | Ejemplo |
|---|---|
| Rider | Carlos |
| Movimiento | +100 coins |
| Motivo | Entrega completada |
| Fecha | 01/07/2026 |

---

## ¿Qué pasa si dos riders compran al mismo tiempo?

El sistema está diseñado para que sea imposible que dos riders reciban el mismo código. La operación de canje es instantánea y atómica — el sistema toma el código, lo bloquea y lo entrega en milisegundos antes de que nadie más pueda tomarlo.

---

## ¿Qué pantallas tiene el rider?

| Pantalla | Para qué sirve |
|---|---|
| Pantalla principal | Ve su saldo de coins y estadísticas |
| Tienda | Ve los productos y sus precios en coins |
| Mis canjes | Ve el historial de lo que ha canjeado y puede releer sus códigos |

---

## Resumen en una línea

> El rider trabaja → gana coins → los gasta en la tienda → recibe un código digital automáticamente → listo, sin intermediarios.
