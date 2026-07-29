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
  owner_id     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
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
-- Repartidores de flota (rol: repartidor)
CREATE TABLE IF NOT EXISTS flota_members (
  rider_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  rider_name  TEXT        NOT NULL,
  rider_email TEXT        NOT NULL,
  joined_at   TIMESTAMPTZ DEFAULT now()
);

-- ── RIDER_LOCATIONS ──────────────────────────────────────────
-- Ubicación GPS en tiempo real del repartidor (upsert cada N segundos)
CREATE TABLE IF NOT EXISTS rider_locations (
  rider_id   UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat        DOUBLE PRECISION NOT NULL,
  lng        DOUBLE PRECISION NOT NULL,
  last_seen  TIMESTAMPTZ DEFAULT now()
);

-- ── RATINGS ──────────────────────────────────────────────────
-- Calificaciones bidireccionales: cliente -> repartidor (is_driver=false)
--                                  repartidor -> cliente (is_driver=true)
CREATE TABLE IF NOT EXISTS ratings (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   TEXT        REFERENCES orders(id) ON DELETE CASCADE,
  stars      INT         NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment    TEXT,
  tip        NUMERIC,
  is_driver  BOOLEAN     NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

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
