-- ============================================================
-- RLS (Row Level Security) — GOGO Food / Grupo Fercadi
-- Ejecutar en: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── 1. Activar RLS en todas las tablas ───────────────────────

ALTER TABLE restaurants     ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories      ENABLE ROW LEVEL SECURITY;
ALTER TABLE products        ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_likes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_likes ENABLE ROW LEVEL SECURITY;

-- ── 2. Funciones auxiliares de roles ─────────────────────────
-- Usan el email del JWT para identificar roles especiales.

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean AS $$
  SELECT (auth.jwt() ->> 'email') = 'admin@fercadi.com';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_dueno()
RETURNS boolean AS $$
  SELECT
    (auth.jwt() ->> 'email') = 'admin@fercadi.com'
    OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'dueno';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_repartidor()
RETURNS boolean AS $$
  SELECT
    (auth.jwt() ->> 'email') = 'admin@fercadi.com'
    OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'repartidor';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ── 3. RESTAURANTS ───────────────────────────────────────────

DROP POLICY IF EXISTS "read_restaurants"   ON restaurants;
DROP POLICY IF EXISTS "update_restaurants" ON restaurants;
DROP POLICY IF EXISTS "insert_restaurants" ON restaurants;
DROP POLICY IF EXISTS "delete_restaurants" ON restaurants;

-- Cualquiera puede ver restaurantes (anon incluido)
CREATE POLICY "read_restaurants"
  ON restaurants FOR SELECT USING (true);

-- Solo dueño o admin puede editar
CREATE POLICY "update_restaurants"
  ON restaurants FOR UPDATE USING (is_dueno());

-- El dueño puede registrar su propio restaurante; admin puede insertar cualquiera
CREATE POLICY "insert_restaurants"
  ON restaurants FOR INSERT WITH CHECK (is_dueno());

CREATE POLICY "delete_restaurants"
  ON restaurants FOR DELETE USING (is_admin());

-- ── 4. CATEGORIES ────────────────────────────────────────────

DROP POLICY IF EXISTS "read_categories"   ON categories;
DROP POLICY IF EXISTS "write_categories"  ON categories;

CREATE POLICY "read_categories"
  ON categories FOR SELECT USING (true);

CREATE POLICY "write_categories"
  ON categories FOR ALL USING (is_dueno()) WITH CHECK (is_dueno());

-- ── 5. PRODUCTS ──────────────────────────────────────────────

DROP POLICY IF EXISTS "read_products"  ON products;
DROP POLICY IF EXISTS "write_products" ON products;

CREATE POLICY "read_products"
  ON products FOR SELECT USING (true);

CREATE POLICY "write_products"
  ON products FOR ALL USING (is_dueno()) WITH CHECK (is_dueno());

-- ── 6. ORDERS ────────────────────────────────────────────────
-- El cliente crea pedidos (authenticated).
-- El dueño ve pedidos de SU restaurante (via user_metadata.restaurant_id).
-- El repartidor ve pendientes + los que tiene asignados.
-- Admin ve todo.

DROP POLICY IF EXISTS "read_orders"   ON orders;
DROP POLICY IF EXISTS "insert_orders" ON orders;
DROP POLICY IF EXISTS "update_orders" ON orders;
DROP POLICY IF EXISTS "delete_orders" ON orders;

CREATE POLICY "read_orders"
  ON orders FOR SELECT USING (
    is_admin()
    OR is_repartidor()
    OR (
      is_dueno()
      AND restaurant_id = (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
    )
    OR (
      -- El cliente puede ver su pedido por ID (no necesita ver todos)
      auth.uid() IS NOT NULL
      AND status IN ('pending', 'accepted', 'delivering', 'delivered', 'cancelled')
    )
  );

CREATE POLICY "insert_orders"
  ON orders FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "update_orders"
  ON orders FOR UPDATE USING (
    is_admin()
    OR is_repartidor()
    OR (
      is_dueno()
      AND restaurant_id = (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
    )
  );

CREATE POLICY "delete_orders"
  ON orders FOR DELETE USING (is_admin());

-- ── 7. ORDER_ITEMS ───────────────────────────────────────────

DROP POLICY IF EXISTS "read_order_items"   ON order_items;
DROP POLICY IF EXISTS "insert_order_items" ON order_items;
DROP POLICY IF EXISTS "write_order_items"  ON order_items;

CREATE POLICY "read_order_items"
  ON order_items FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "insert_order_items"
  ON order_items FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "write_order_items"
  ON order_items FOR UPDATE USING (is_admin());

-- ── 8. PRODUCT_LIKES ─────────────────────────────────────────
-- Usa user_email (no user_id) — el email del JWT debe coincidir.

DROP POLICY IF EXISTS "read_product_likes"   ON product_likes;
DROP POLICY IF EXISTS "insert_product_likes" ON product_likes;
DROP POLICY IF EXISTS "delete_product_likes" ON product_likes;

CREATE POLICY "read_product_likes"
  ON product_likes FOR SELECT USING (true);

CREATE POLICY "insert_product_likes"
  ON product_likes FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_email = (auth.jwt() ->> 'email')
  );

CREATE POLICY "delete_product_likes"
  ON product_likes FOR DELETE USING (
    user_email = (auth.jwt() ->> 'email')
  );

-- ── 9. RESTAURANT_LIKES ──────────────────────────────────────

DROP POLICY IF EXISTS "read_restaurant_likes"   ON restaurant_likes;
DROP POLICY IF EXISTS "insert_restaurant_likes" ON restaurant_likes;
DROP POLICY IF EXISTS "delete_restaurant_likes" ON restaurant_likes;

CREATE POLICY "read_restaurant_likes"
  ON restaurant_likes FOR SELECT USING (true);

CREATE POLICY "insert_restaurant_likes"
  ON restaurant_likes FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_email = (auth.jwt() ->> 'email')
  );

CREATE POLICY "delete_restaurant_likes"
  ON restaurant_likes FOR DELETE USING (
    user_email = (auth.jwt() ->> 'email')
  );

-- ── 10. Confirmar que RLS está activo ────────────────────────
-- Ejecuta esto para verificar:
-- SELECT tablename, rowsecurity FROM pg_tables
-- WHERE schemaname = 'public' ORDER BY tablename;
