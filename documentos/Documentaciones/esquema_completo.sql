-- ============================================================
-- Esquema completo — GOGO Food / Grupo Fercadi
-- Supabase (PostgreSQL)
-- Ejecutar en: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── RESTAURANTS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurants (
  id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  name         TEXT        NOT NULL,
  description  TEXT,
  address      TEXT,
  image_url    TEXT,
  emoji_icon   TEXT        DEFAULT '🍽️',
  is_open      BOOLEAN     DEFAULT true,
  rating       NUMERIC(3,1) DEFAULT 0,
  lat          DOUBLE PRECISION,
  lng          DOUBLE PRECISION,
  zona         TEXT,       -- 'maravatio' | 'acambaro' — se detecta sola desde lat/lng o dirección
  categorias   TEXT[]      NOT NULL DEFAULT '{}', -- lista fija (ver lib/core/restaurant_categories.dart), elegida por el dueño al registrarse o desde su panel — NO son las categorías del menú
  is_premium   BOOLEAN     NOT NULL DEFAULT false,  -- GOGO Premium: desbloquea banners, promo por platillo y sube el tope de platillos de 7 a 20
  owner_id     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,  -- solo se escribe al auto-registrarse; el panel del dueño usa user_metadata.restaurant_id, no esta columna
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- ── RESTAURANT_BANNERS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_banners (
  id            TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  restaurant_id TEXT        REFERENCES restaurants(id) ON DELETE CASCADE,
  image_url     TEXT        NOT NULL,
  title         TEXT,
  link_url      TEXT,
  sort_order    INT         DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- ── CATEGORIES ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
  id            TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  restaurant_id TEXT        REFERENCES restaurants(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL,
  emoji_icon    TEXT        DEFAULT '🍴',
  sort_order    INT         DEFAULT 0
);

-- ── PRODUCTS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id            TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  category_id   TEXT        REFERENCES categories(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL,
  description   TEXT,
  price         NUMERIC(10,2) NOT NULL DEFAULT 0,
  image_url     TEXT,
  is_available  BOOLEAN     DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- ── PRODUCT_IMAGES ───────────────────────────────────────────
-- Imágenes adicionales por producto (galería)
CREATE TABLE IF NOT EXISTS product_images (
  id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  product_id  TEXT        REFERENCES products(id) ON DELETE CASCADE,
  image_url   TEXT        NOT NULL,
  sort_order  INT         DEFAULT 0
);

-- ── ORDERS ───────────────────────────────────────────────────
-- customer_name: JSON string con { name, phone, address, payment, lat, lng }
-- status: pending | accepted | delivering | delivered | cancelled
CREATE TABLE IF NOT EXISTS orders (
  id                        TEXT        PRIMARY KEY,
  restaurant_id             TEXT        REFERENCES restaurants(id) ON DELETE SET NULL,
  total                     NUMERIC(10,2) NOT NULL DEFAULT 0,
  delivery_fee              NUMERIC(10,2) DEFAULT 0,
  status                    TEXT        NOT NULL DEFAULT 'pending',
  customer_name             TEXT,       -- JSON: { name, phone, address, payment, lat, lng }
  customer_id               UUID        REFERENCES auth.users(id) ON DELETE SET NULL, -- para mostrarle su foto/nombre real al repartidor (como Uber)
  repartidor_id             UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  -- Solo se usan para pagos vía Stripe (OXXO/tarjeta) — null para efectivo.
  -- payment_status: 'pending' (OXXO, esperando que el cliente pague en tienda),
  --                 'paid' (confirmado por webhook o por Stripe PaymentSheet), 'failed'
  payment_status            TEXT,
  stripe_payment_intent_id  TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

-- ── ORDER_ITEMS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS order_items (
  id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  order_id    TEXT        REFERENCES orders(id) ON DELETE CASCADE,
  product_id  TEXT        REFERENCES products(id) ON DELETE SET NULL,
  quantity    INT         NOT NULL DEFAULT 1,
  price       NUMERIC(10,2) NOT NULL DEFAULT 0,
  notes       TEXT
);

-- ── PRODUCT_LIKES ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_likes (
  id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  product_id  TEXT        REFERENCES products(id) ON DELETE CASCADE,
  user_email  TEXT        NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (product_id, user_email)
);

-- ── RESTAURANT_LIKES ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_likes (
  id             TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  restaurant_id  TEXT        REFERENCES restaurants(id) ON DELETE CASCADE,
  user_email     TEXT        NOT NULL,
  created_at     TIMESTAMPTZ DEFAULT now(),
  UNIQUE (restaurant_id, user_email)
);

-- ── FLOTA_MEMBERS ────────────────────────────────────────────
-- Repartidores de flota (rol: repartidor), vinculados a su jefe_flota.
-- rider_plate: placa de la moto, editable desde el panel de flota.
CREATE TABLE IF NOT EXISTS flota_members (
  rider_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  jefe_id     UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
  rider_name  TEXT        NOT NULL,
  rider_email TEXT        NOT NULL,
  rider_plate TEXT,
  joined_at   TIMESTAMPTZ DEFAULT now()
);

-- ── RIDER_LOCATIONS ──────────────────────────────────────────
-- Ubicación GPS en tiempo real del repartidor (upsert cada N segundos).
-- is_active: false al cerrar sesión (setRiderInactive), true mientras transmite.
CREATE TABLE IF NOT EXISTS rider_locations (
  rider_id   UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat        DOUBLE PRECISION NOT NULL,
  lng        DOUBLE PRECISION NOT NULL,
  is_active  BOOLEAN     DEFAULT true,
  last_seen  TIMESTAMPTZ DEFAULT now()
);

-- ── ALERTS ───────────────────────────────────────────────────
-- Alertas del panel de administrador (módulo "Alertas").
-- priority: critica | alta | media | baja
-- status:   pendiente | en_proceso | resuelta
-- category: pagos | servidor | restaurante | base_datos | conexion | otro
CREATE TABLE IF NOT EXISTS alerts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL,
  description TEXT,
  category    TEXT        NOT NULL DEFAULT 'otro',
  priority    TEXT        NOT NULL DEFAULT 'media',
  status      TEXT        NOT NULL DEFAULT 'pendiente',
  created_at  TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

-- ── RIDER_STORE_ITEMS ────────────────────────────────────────
-- Catálogo de la "Tienda de Coins" del rider (repartidor_plus).
-- Administrable desde el panel de Admin (tab "Tienda"); antes de
-- agosto 2026 vivía hardcodeado en tienda_rider_screen.dart.
-- Lectura pública (RLS: read_rider_store_items), escritura solo
-- para role = 'admin' (RLS: write_rider_store_items).
CREATE TABLE IF NOT EXISTS rider_store_items (
  id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::text,
  emoji       TEXT        NOT NULL DEFAULT '🎁',
  name        TEXT        NOT NULL,
  description TEXT,
  cost_coins  INTEGER     NOT NULL,
  image_url   TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── RATINGS ──────────────────────────────────────────────────
-- Calificaciones bidireccionales: cliente -> repartidor (is_driver=false)
--                                  repartidor -> cliente (is_driver=true)
CREATE TABLE IF NOT EXISTS ratings (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      TEXT        REFERENCES orders(id) ON DELETE CASCADE,
  stars         INT         NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment       TEXT,
  tip           NUMERIC,
  is_driver     BOOLEAN     NOT NULL DEFAULT false,
  is_hidden     BOOLEAN     NOT NULL DEFAULT false,  -- moderación admin (módulo "Reseñas")
  is_flagged    BOOLEAN     NOT NULL DEFAULT false,
  report_reason TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- ── RATING_MODERATION_LOG ────────────────────────────────────
-- Historial de acciones de moderación sobre `ratings` (módulo "Reseñas" de
-- Admin). action: 'hide' | 'unhide' | 'delete' | 'flag' | 'unflag'.
CREATE TABLE IF NOT EXISTS rating_moderation_log (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  rating_id   UUID        REFERENCES ratings(id) ON DELETE CASCADE,
  admin_email TEXT        NOT NULL,
  action      TEXT        NOT NULL,
  note        TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── RIDER_PAYOUT_ACCOUNTS ────────────────────────────────────
-- Uno por rider (repartidor_plus). Hoy solo se usa `clabe` (destino manual
-- mientras no hay Stripe Connect). Las columnas stripe_* quedan preparadas
-- para cuando se automatice el pago, sin lógica todavía.
CREATE TABLE IF NOT EXISTS rider_payout_accounts (
  rider_id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  clabe                     TEXT,
  stripe_connect_account_id TEXT,
  stripe_onboarding_status  TEXT NOT NULL DEFAULT 'not_started',
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── RIDER_WITHDRAWALS ────────────────────────────────────────
-- Retiros de saldo de repartidores independientes (repartidor_plus). Los
-- repartidores de flota no usan esto — su jefe de flota les paga fuera de
-- la plataforma. `status` es TEXT libre a propósito (agregar un estado
-- nuevo no requiere ALTER TYPE): pendiente | en_proceso | completado |
-- rechazado | cancelado. El saldo se calcula siempre en vivo con
-- get_rider_balance() (SUM de delivery_fee de pedidos entregados menos
-- retiros completados/reservados) — nunca un contador guardado, para no
-- repetir el drift que ya se encontró en rider_stats.dinero.
CREATE TABLE IF NOT EXISTS rider_withdrawals (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount                NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  status                TEXT NOT NULL DEFAULT 'pendiente',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at          TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  rejection_reason      TEXT,
  transaction_reference TEXT,
  stripe_payout_id      TEXT,   -- futuro: id del payout/transfer de Stripe Connect
  stripe_payout_status  TEXT,
  admin_notes           TEXT,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Único retiro abierto (pendiente/en_proceso) por rider a la vez — esta es
-- la garantía real contra dos solicitudes simultáneas (no una validación
-- de aplicación, que sí puede tener condición de carrera).
CREATE UNIQUE INDEX IF NOT EXISTS one_open_withdrawal_per_rider ON rider_withdrawals (rider_id)
  WHERE status IN ('pendiente', 'en_proceso');
CREATE INDEX IF NOT EXISTS idx_rider_withdrawals_rider ON rider_withdrawals(rider_id);
CREATE INDEX IF NOT EXISTS idx_rider_withdrawals_status ON rider_withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_rider_withdrawals_created ON rider_withdrawals(created_at DESC);

-- ── WITHDRAWAL_STATUS_LOG ────────────────────────────────────
-- Historial de quién aprobó/rechazó/completó/canceló cada retiro.
CREATE TABLE IF NOT EXISTS withdrawal_status_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id UUID NOT NULL REFERENCES rider_withdrawals(id) ON DELETE CASCADE,
  admin_email TEXT NOT NULL,
  action TEXT NOT NULL,   -- 'approve' | 'complete' | 'reject' | 'cancel'
  from_status TEXT, to_status TEXT, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_withdrawal_status_log_withdrawal ON withdrawal_status_log(withdrawal_id);

-- Funciones RPC del módulo de retiros (SECURITY DEFINER):
--   get_rider_balance(p_rider_id uuid DEFAULT NULL) — saldo en vivo; sin
--     parámetro regresa el saldo de quien llama, con parámetro solo un
--     admin puede consultar el de otro rider.
--   request_withdrawal(p_amount numeric) — valida (monto>0, mínimo $200,
--     no ser de flota, no tener ya un retiro abierto, no exceder el saldo)
--     e inserta el retiro en 'pendiente'. auth.uid() siempre, nunca un id
--     recibido del cliente.
--   admin_transition_withdrawal(p_withdrawal_id, p_new_status,
--     p_rejection_reason, p_transaction_reference, p_admin_notes) — solo
--     admin; máquina de estados simple (pendiente→en_proceso/rechazado/
--     cancelado, en_proceso→completado/rechazado/cancelado); actualiza y
--     escribe withdrawal_status_log en la misma transacción.
-- Definiciones completas: ver sesión 2026-08-05 / manual_backend.md.
--
-- is_admin() se corrigió para regresar siempre boolean (antes regresaba
-- NULL cuando quien llama no tiene sesión, y un `IF NOT is_admin()` en
-- plpgsql trata NULL como "no entrar al bloque" — un llamado anónimo casi
-- lograba pasar el checkeo de administrador. Ahora usa COALESCE(..., false).

-- ── STORAGE BUCKETS ──────────────────────────────────────────
-- Crear desde Dashboard → Storage, o con service key vía API:
-- product-images  (público)
-- profile-photos  (público)

-- ── RLS ──────────────────────────────────────────────────────
-- Ver: supabase_rls.sql (en la raíz del proyecto)

-- ── ÍNDICES recomendados ──────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_restaurant   ON orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status       ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_repartidor   ON orders(repartidor_id);
CREATE INDEX IF NOT EXISTS idx_products_category   ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_categories_restaurant ON categories(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order   ON order_items(order_id);
