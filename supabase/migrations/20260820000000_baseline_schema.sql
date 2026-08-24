


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."rider_withdrawals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rider_id" "uuid" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "status" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "rejection_reason" "text",
    "transaction_reference" "text",
    "stripe_payout_id" "text",
    "stripe_payout_status" "text",
    "admin_notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "rider_withdrawals_amount_check" CHECK (("amount" > (0)::numeric))
);


ALTER TABLE "public"."rider_withdrawals" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_transition_withdrawal"("p_withdrawal_id" "uuid", "p_new_status" "text", "p_rejection_reason" "text" DEFAULT NULL::"text", "p_transaction_reference" "text" DEFAULT NULL::"text", "p_admin_notes" "text" DEFAULT NULL::"text") RETURNS "public"."rider_withdrawals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_row   rider_withdrawals;
  v_prev_status text;
  v_email text := auth.jwt() ->> 'email';
BEGIN
  IF NOT COALESCE(is_admin(), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  SELECT * INTO v_row FROM rider_withdrawals WHERE id = p_withdrawal_id;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'retiro_no_encontrado';
  END IF;
  v_prev_status := v_row.status;

  IF NOT (
    (v_row.status = 'pendiente'  AND p_new_status IN ('en_proceso','rechazado','cancelado'))
    OR (v_row.status = 'en_proceso' AND p_new_status IN ('completado','rechazado','cancelado'))
  ) THEN
    RAISE EXCEPTION 'transicion_invalida';
  END IF;

  UPDATE rider_withdrawals SET
    status = p_new_status,
    processed_at = CASE WHEN p_new_status = 'en_proceso' THEN now() ELSE processed_at END,
    completed_at = CASE WHEN p_new_status IN ('completado','rechazado','cancelado') THEN now() ELSE completed_at END,
    rejection_reason = COALESCE(p_rejection_reason, rejection_reason),
    transaction_reference = COALESCE(p_transaction_reference, transaction_reference),
    admin_notes = COALESCE(p_admin_notes, admin_notes),
    updated_at = now()
  WHERE id = p_withdrawal_id
  RETURNING * INTO v_row;

  INSERT INTO withdrawal_status_log (withdrawal_id, admin_email, action, from_status, to_status, note)
  VALUES (
    p_withdrawal_id, v_email,
    CASE p_new_status WHEN 'en_proceso' THEN 'approve' WHEN 'completado' THEN 'complete'
                       WHEN 'rechazado' THEN 'reject' ELSE 'cancel' END,
    v_prev_status, p_new_status, p_admin_notes
  );

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."admin_transition_withdrawal"("p_withdrawal_id" "uuid", "p_new_status" "text", "p_rejection_reason" "text", "p_transaction_reference" "text", "p_admin_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_rider_balance"("p_rider_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("total_ganado" numeric, "total_retirado" numeric, "total_reservado" numeric, "saldo_disponible" numeric)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_rider uuid := COALESCE(p_rider_id, auth.uid());
BEGIN
  IF v_rider IS NULL THEN
    RAISE EXCEPTION 'no_autenticado';
  END IF;
  IF v_rider IS DISTINCT FROM auth.uid() AND NOT COALESCE(is_admin(), false) THEN
    RAISE EXCEPTION 'no_autorizado';
  END IF;

  RETURN QUERY
  SELECT ganado, retirado, reservado, ganado - retirado - reservado
  FROM (
    SELECT
      COALESCE((SELECT SUM(delivery_fee) FROM orders
                 WHERE repartidor_id = v_rider AND status = 'delivered'), 0) AS ganado,
      COALESCE((SELECT SUM(amount) FROM rider_withdrawals
                 WHERE rider_id = v_rider AND status = 'completado'), 0) AS retirado,
      COALESCE((SELECT SUM(amount) FROM rider_withdrawals
                 WHERE rider_id = v_rider AND status IN ('pendiente','en_proceso')), 0) AS reservado
  ) s;
END;
$$;


ALTER FUNCTION "public"."get_rider_balance"("p_rider_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_rider_stats"("p_rider_id" "uuid", "p_coins_add" integer DEFAULT 0, "p_repartos_add" integer DEFAULT 0, "p_dinero_add" numeric DEFAULT 0) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO rider_stats (rider_id, coins, repartos, dinero, updated_at)
  VALUES (p_rider_id, p_coins_add, p_repartos_add, p_dinero_add, now())
  ON CONFLICT (rider_id) DO UPDATE SET
    coins     = rider_stats.coins     + EXCLUDED.coins,
    repartos  = rider_stats.repartos  + EXCLUDED.repartos,
    dinero    = rider_stats.dinero    + EXCLUDED.dinero,
    updated_at = now();
END; $$;


ALTER FUNCTION "public"."increment_rider_stats"("p_rider_id" "uuid", "p_coins_add" integer, "p_repartos_add" integer, "p_dinero_add" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT COALESCE((auth.jwt() ->> 'email') = 'admin@fercadi.com', false);
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_dueno"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT
    (auth.jwt() ->> 'email') = 'admin@fercadi.com'
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'dueno';
$$;


ALTER FUNCTION "public"."is_dueno"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_jefe_flota"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT
    (auth.jwt() ->> 'email') = 'admin@fercadi.com'
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'jefe_flota';
$$;


ALTER FUNCTION "public"."is_jefe_flota"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_repartidor"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT
    (auth.jwt() ->> 'email') = 'admin@fercadi.com'
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'repartidor'
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'repartidor_plus';
$$;


ALTER FUNCTION "public"."is_repartidor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_withdrawal"("p_amount" numeric) RETURNS "public"."rider_withdrawals"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_rider uuid := auth.uid();
  v_saldo numeric;
  v_row   rider_withdrawals;
BEGIN
  IF v_rider IS NULL THEN
    RAISE EXCEPTION 'no_autenticado';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'monto_invalido';
  END IF;
  IF p_amount < 200 THEN
    RAISE EXCEPTION 'monto_minimo';
  END IF;

  IF EXISTS (SELECT 1 FROM flota_members WHERE rider_id = v_rider) THEN
    RAISE EXCEPTION 'rider_de_flota';
  END IF;

  IF EXISTS (SELECT 1 FROM rider_withdrawals
             WHERE rider_id = v_rider AND status IN ('pendiente','en_proceso')) THEN
    RAISE EXCEPTION 'retiro_en_curso';
  END IF;

  SELECT saldo_disponible INTO v_saldo FROM get_rider_balance(v_rider);
  IF p_amount > v_saldo THEN
    RAISE EXCEPTION 'saldo_insuficiente';
  END IF;

  BEGIN
    INSERT INTO rider_withdrawals (rider_id, amount, status)
    VALUES (v_rider, p_amount, 'pendiente')
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'retiro_en_curso';
  END;

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."request_withdrawal"("p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_role_to_app_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.raw_user_meta_data->>'role' IS NOT NULL AND 
     (NEW.raw_app_meta_data->>'role' IS NULL OR NEW.raw_app_meta_data->>'role' = '') THEN
    NEW.raw_app_meta_data = NEW.raw_app_meta_data || 
      jsonb_build_object('role', NEW.raw_user_meta_data->>'role');
  END IF;
  IF NEW.raw_user_meta_data->>'restaurant_id' IS NOT NULL AND 
     NEW.raw_app_meta_data->>'restaurant_id' IS NULL THEN
    NEW.raw_app_meta_data = NEW.raw_app_meta_data || 
      jsonb_build_object('restaurant_id', NEW.raw_user_meta_data->>'restaurant_id');
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_role_to_app_metadata"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "category" "text" DEFAULT 'otro'::"text" NOT NULL,
    "priority" "text" DEFAULT 'media'::"text" NOT NULL,
    "status" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "resolved_at" timestamp with time zone
);


ALTER TABLE "public"."alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "text" NOT NULL,
    "restaurant_id" "text",
    "name" "text" NOT NULL,
    "emoji_icon" "text"
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."flota_members" (
    "jefe_id" "uuid" NOT NULL,
    "rider_id" "uuid" NOT NULL,
    "rider_name" "text",
    "rider_email" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "rider_plate" "text"
);


ALTER TABLE "public"."flota_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "text" DEFAULT ("gen_random_uuid"())::"text" NOT NULL,
    "order_id" "text",
    "product_id" "text",
    "name" "text",
    "quantity" integer,
    "price" numeric,
    "notes" "text"
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "text" DEFAULT ("gen_random_uuid"())::"text" NOT NULL,
    "restaurant_id" "text",
    "customer_name" "text",
    "total" numeric,
    "status" "text" DEFAULT 'pendiente'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "current_lat" double precision,
    "current_lng" double precision,
    "delivery_fee" numeric DEFAULT 0,
    "repartidor_id" "uuid",
    "payment_status" "text",
    "stripe_payment_intent_id" "text",
    "customer_id" "uuid"
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."platform_config" (
    "key" "text" NOT NULL,
    "value" "text" NOT NULL
);


ALTER TABLE "public"."platform_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_likes" (
    "product_id" "text" NOT NULL,
    "user_email" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."product_likes" REPLICA IDENTITY FULL;


ALTER TABLE "public"."product_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "text" NOT NULL,
    "category_id" "text",
    "restaurant_id" "text",
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric NOT NULL,
    "image_url" "text",
    "is_available" boolean DEFAULT true,
    "promo_discount_percent" integer,
    "promo_is_2x1" boolean DEFAULT false,
    "promo_expires_at" timestamp with time zone
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rating_moderation_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rating_id" "uuid",
    "admin_email" "text" NOT NULL,
    "action" "text" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rating_moderation_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ratings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "text",
    "stars" integer NOT NULL,
    "comment" "text",
    "tip" numeric,
    "is_driver" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_hidden" boolean DEFAULT false NOT NULL,
    "is_flagged" boolean DEFAULT false NOT NULL,
    "report_reason" "text",
    CONSTRAINT "ratings_stars_check" CHECK ((("stars" >= 1) AND ("stars" <= 5)))
);


ALTER TABLE "public"."ratings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."restaurant_banners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "restaurant_id" "text" NOT NULL,
    "image_url" "text" NOT NULL,
    "title" "text" DEFAULT ''::"text",
    "subtitle" "text" DEFAULT ''::"text",
    "badge" "text" DEFAULT ''::"text",
    "badge_color_hex" "text" DEFAULT '#E53935'::"text",
    "product_id" "text",
    "discount_percent" integer,
    "expires_at" timestamp with time zone,
    "sort_order" integer DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "restaurant_banners_discount_percent_check" CHECK ((("discount_percent" >= 1) AND ("discount_percent" <= 100)))
);


ALTER TABLE "public"."restaurant_banners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."restaurant_likes" (
    "restaurant_id" "text" NOT NULL,
    "user_email" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."restaurant_likes" REPLICA IDENTITY FULL;


ALTER TABLE "public"."restaurant_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."restaurants" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "address" "text",
    "emoji_icon" "text",
    "rating" numeric DEFAULT 0,
    "likes" integer DEFAULT 0,
    "is_open" boolean DEFAULT true,
    "owner_id" "uuid",
    "lat" double precision,
    "lng" double precision,
    "image_url" "text",
    "zona" "text" DEFAULT 'maravatio'::"text" NOT NULL,
    "is_premium" boolean DEFAULT false NOT NULL,
    "categorias" "text"[] DEFAULT '{}'::"text"[] NOT NULL
);


ALTER TABLE "public"."restaurants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_locations" (
    "rider_id" "uuid" NOT NULL,
    "lat" double precision,
    "lng" double precision,
    "is_active" boolean DEFAULT true,
    "last_seen" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rider_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_payout_accounts" (
    "rider_id" "uuid" NOT NULL,
    "clabe" "text",
    "stripe_connect_account_id" "text",
    "stripe_onboarding_status" "text" DEFAULT 'not_started'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."rider_payout_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_stats" (
    "rider_id" "uuid" NOT NULL,
    "coins" integer DEFAULT 0,
    "repartos" integer DEFAULT 0,
    "dinero" numeric(10,2) DEFAULT 0,
    "nivel" integer DEFAULT 1,
    "nivel_progress" integer DEFAULT 0,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rider_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rider_store_items" (
    "id" "text" DEFAULT ("gen_random_uuid"())::"text" NOT NULL,
    "emoji" "text" DEFAULT '🎁'::"text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "cost_coins" integer NOT NULL,
    "image_url" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rider_store_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."withdrawal_status_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "withdrawal_id" "uuid" NOT NULL,
    "admin_email" "text" NOT NULL,
    "action" "text" NOT NULL,
    "from_status" "text",
    "to_status" "text",
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."withdrawal_status_log" OWNER TO "postgres";


ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."flota_members"
    ADD CONSTRAINT "flota_members_pkey" PRIMARY KEY ("jefe_id", "rider_id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."platform_config"
    ADD CONSTRAINT "platform_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."product_likes"
    ADD CONSTRAINT "product_likes_pkey" PRIMARY KEY ("product_id", "user_email");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rating_moderation_log"
    ADD CONSTRAINT "rating_moderation_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ratings"
    ADD CONSTRAINT "ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."restaurant_banners"
    ADD CONSTRAINT "restaurant_banners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."restaurant_likes"
    ADD CONSTRAINT "restaurant_likes_pkey" PRIMARY KEY ("restaurant_id", "user_email");



ALTER TABLE ONLY "public"."restaurants"
    ADD CONSTRAINT "restaurants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rider_locations"
    ADD CONSTRAINT "rider_locations_pkey" PRIMARY KEY ("rider_id");



ALTER TABLE ONLY "public"."rider_payout_accounts"
    ADD CONSTRAINT "rider_payout_accounts_pkey" PRIMARY KEY ("rider_id");



ALTER TABLE ONLY "public"."rider_stats"
    ADD CONSTRAINT "rider_stats_pkey" PRIMARY KEY ("rider_id");



ALTER TABLE ONLY "public"."rider_store_items"
    ADD CONSTRAINT "rider_store_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rider_withdrawals"
    ADD CONSTRAINT "rider_withdrawals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."withdrawal_status_log"
    ADD CONSTRAINT "withdrawal_status_log_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_rider_withdrawals_created" ON "public"."rider_withdrawals" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_rider_withdrawals_rider" ON "public"."rider_withdrawals" USING "btree" ("rider_id");



CREATE INDEX "idx_rider_withdrawals_status" ON "public"."rider_withdrawals" USING "btree" ("status");



CREATE INDEX "idx_withdrawal_status_log_withdrawal" ON "public"."withdrawal_status_log" USING "btree" ("withdrawal_id");



CREATE UNIQUE INDEX "one_open_withdrawal_per_rider" ON "public"."rider_withdrawals" USING "btree" ("rider_id") WHERE ("status" = ANY (ARRAY['pendiente'::"text", 'en_proceso'::"text"]));



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id");



ALTER TABLE ONLY "public"."flota_members"
    ADD CONSTRAINT "flota_members_jefe_id_fkey" FOREIGN KEY ("jefe_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."flota_members"
    ADD CONSTRAINT "flota_members_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id");



ALTER TABLE ONLY "public"."rating_moderation_log"
    ADD CONSTRAINT "rating_moderation_log_rating_id_fkey" FOREIGN KEY ("rating_id") REFERENCES "public"."ratings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ratings"
    ADD CONSTRAINT "ratings_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."restaurant_banners"
    ADD CONSTRAINT "restaurant_banners_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."restaurant_banners"
    ADD CONSTRAINT "restaurant_banners_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "public"."restaurants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rider_locations"
    ADD CONSTRAINT "rider_locations_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rider_payout_accounts"
    ADD CONSTRAINT "rider_payout_accounts_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rider_stats"
    ADD CONSTRAINT "rider_stats_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rider_withdrawals"
    ADD CONSTRAINT "rider_withdrawals_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."withdrawal_status_log"
    ADD CONSTRAINT "withdrawal_status_log_withdrawal_id_fkey" FOREIGN KEY ("withdrawal_id") REFERENCES "public"."rider_withdrawals"("id") ON DELETE CASCADE;



CREATE POLICY "Allow all" ON "public"."product_likes" USING (true) WITH CHECK (true);



CREATE POLICY "Allow all" ON "public"."restaurant_likes" USING (true) WITH CHECK (true);



CREATE POLICY "Cualquiera puede actualizar pedidos" ON "public"."orders" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Cualquiera puede insertar order_items" ON "public"."order_items" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Cualquiera puede insertar pedidos" ON "public"."orders" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Cualquiera puede leer order_items" ON "public"."order_items" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Cualquiera puede leer pedidos" ON "public"."orders" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "admin_all_moderation_log" ON "public"."rating_moderation_log" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "admin_delete_ratings" ON "public"."ratings" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "admin_update_ratings" ON "public"."ratings" FOR UPDATE USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "delete_orders" ON "public"."orders" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "delete_product_likes" ON "public"."product_likes" FOR DELETE USING (("user_email" = ("auth"."jwt"() ->> 'email'::"text")));



CREATE POLICY "delete_restaurant_likes" ON "public"."restaurant_likes" FOR DELETE USING (("user_email" = ("auth"."jwt"() ->> 'email'::"text")));



CREATE POLICY "delete_restaurants" ON "public"."restaurants" FOR DELETE USING ("public"."is_admin"());



ALTER TABLE "public"."flota_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "insert_order_items" ON "public"."order_items" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "insert_orders" ON "public"."orders" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "insert_own_payout_account" ON "public"."rider_payout_accounts" FOR INSERT WITH CHECK (("rider_id" = "auth"."uid"()));



CREATE POLICY "insert_product_likes" ON "public"."product_likes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("user_email" = ("auth"."jwt"() ->> 'email'::"text"))));



CREATE POLICY "insert_ratings" ON "public"."ratings" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "insert_restaurant_likes" ON "public"."restaurant_likes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("user_email" = ("auth"."jwt"() ->> 'email'::"text"))));



CREATE POLICY "insert_restaurants" ON "public"."restaurants" FOR INSERT WITH CHECK ("public"."is_dueno"());



CREATE POLICY "insert_rider_locations" ON "public"."rider_locations" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("rider_id" = "auth"."uid"())));



ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "order_items_auth" ON "public"."order_items" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "order_items_select_anon" ON "public"."order_items" FOR SELECT TO "anon" USING (true);



ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_auth" ON "public"."orders" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "orders_select_anon" ON "public"."orders" FOR SELECT TO "anon" USING (true);



ALTER TABLE "public"."platform_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rating_moderation_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ratings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_categories" ON "public"."categories" FOR SELECT USING (true);



CREATE POLICY "read_flota_members" ON "public"."flota_members" FOR SELECT USING (("public"."is_admin"() OR "public"."is_jefe_flota"()));



CREATE POLICY "read_order_items" ON "public"."order_items" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "read_orders" ON "public"."orders" FOR SELECT USING (("public"."is_admin"() OR "public"."is_repartidor"() OR ("public"."is_dueno"() AND ("restaurant_id" = (("auth"."jwt"() -> 'app_metadata'::"text") ->> 'restaurant_id'::"text"))) OR (("auth"."uid"() IS NOT NULL) AND ("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'delivering'::"text", 'delivered'::"text", 'cancelled'::"text"])))));



CREATE POLICY "read_own_payout_account" ON "public"."rider_payout_accounts" FOR SELECT USING ((("rider_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "read_platform_config" ON "public"."platform_config" FOR SELECT USING (true);



CREATE POLICY "read_product_likes" ON "public"."product_likes" FOR SELECT USING (true);



CREATE POLICY "read_products" ON "public"."products" FOR SELECT USING (true);



CREATE POLICY "read_ratings" ON "public"."ratings" FOR SELECT USING (("public"."is_admin"() OR ("auth"."uid"() IS NOT NULL)));



CREATE POLICY "read_restaurant_banners" ON "public"."restaurant_banners" FOR SELECT USING (true);



CREATE POLICY "read_restaurant_likes" ON "public"."restaurant_likes" FOR SELECT USING (true);



CREATE POLICY "read_restaurants" ON "public"."restaurants" FOR SELECT USING (true);



CREATE POLICY "read_rider_locations" ON "public"."rider_locations" FOR SELECT USING (("public"."is_admin"() OR "public"."is_jefe_flota"()));



CREATE POLICY "read_rider_store_items" ON "public"."rider_store_items" FOR SELECT USING (true);



CREATE POLICY "read_rider_withdrawals" ON "public"."rider_withdrawals" FOR SELECT USING ((("rider_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "read_withdrawal_status_log" ON "public"."withdrawal_status_log" FOR SELECT USING (("public"."is_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."rider_withdrawals" "w"
  WHERE (("w"."id" = "withdrawal_status_log"."withdrawal_id") AND ("w"."rider_id" = "auth"."uid"()))))));



ALTER TABLE "public"."restaurant_banners" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."restaurant_likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."restaurants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_payout_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_stats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rider_stats_own" ON "public"."rider_stats" USING (("rider_id" = "auth"."uid"())) WITH CHECK (("rider_id" = "auth"."uid"()));



ALTER TABLE "public"."rider_store_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rider_withdrawals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "update_orders" ON "public"."orders" FOR UPDATE USING (("public"."is_admin"() OR "public"."is_repartidor"() OR ("public"."is_dueno"() AND ("restaurant_id" = (("auth"."jwt"() -> 'app_metadata'::"text") ->> 'restaurant_id'::"text")))));



CREATE POLICY "update_own_payout_account" ON "public"."rider_payout_accounts" FOR UPDATE USING (("rider_id" = "auth"."uid"())) WITH CHECK (("rider_id" = "auth"."uid"()));



CREATE POLICY "update_restaurants" ON "public"."restaurants" FOR UPDATE USING ("public"."is_dueno"());



CREATE POLICY "update_rider_locations" ON "public"."rider_locations" FOR UPDATE USING (("rider_id" = "auth"."uid"()));



ALTER TABLE "public"."withdrawal_status_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "write_categories" ON "public"."categories" USING ("public"."is_dueno"()) WITH CHECK ("public"."is_dueno"());



CREATE POLICY "write_flota_members" ON "public"."flota_members" USING (("public"."is_admin"() OR "public"."is_jefe_flota"())) WITH CHECK (("public"."is_admin"() OR "public"."is_jefe_flota"()));



CREATE POLICY "write_order_items" ON "public"."order_items" FOR UPDATE USING ("public"."is_admin"());



CREATE POLICY "write_platform_config" ON "public"."platform_config" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "write_product_likes" ON "public"."product_likes" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "write_products" ON "public"."products" USING ("public"."is_dueno"()) WITH CHECK ("public"."is_dueno"());



CREATE POLICY "write_restaurant_banners" ON "public"."restaurant_banners" USING ("public"."is_dueno"()) WITH CHECK ("public"."is_dueno"());



CREATE POLICY "write_restaurant_likes" ON "public"."restaurant_likes" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "write_restaurants" ON "public"."restaurants" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "write_rider_store_items" ON "public"."rider_store_items" USING (((("auth"."jwt"() -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text")) WITH CHECK (((("auth"."jwt"() -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TABLE "public"."rider_withdrawals" TO "anon";
GRANT ALL ON TABLE "public"."rider_withdrawals" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_withdrawals" TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_transition_withdrawal"("p_withdrawal_id" "uuid", "p_new_status" "text", "p_rejection_reason" "text", "p_transaction_reference" "text", "p_admin_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_transition_withdrawal"("p_withdrawal_id" "uuid", "p_new_status" "text", "p_rejection_reason" "text", "p_transaction_reference" "text", "p_admin_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_transition_withdrawal"("p_withdrawal_id" "uuid", "p_new_status" "text", "p_rejection_reason" "text", "p_transaction_reference" "text", "p_admin_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_rider_balance"("p_rider_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_rider_balance"("p_rider_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_rider_balance"("p_rider_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_rider_stats"("p_rider_id" "uuid", "p_coins_add" integer, "p_repartos_add" integer, "p_dinero_add" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_rider_stats"("p_rider_id" "uuid", "p_coins_add" integer, "p_repartos_add" integer, "p_dinero_add" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_rider_stats"("p_rider_id" "uuid", "p_coins_add" integer, "p_repartos_add" integer, "p_dinero_add" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_dueno"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_dueno"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_dueno"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_jefe_flota"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_jefe_flota"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_jefe_flota"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_repartidor"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_repartidor"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_repartidor"() TO "service_role";



GRANT ALL ON FUNCTION "public"."request_withdrawal"("p_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."request_withdrawal"("p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_withdrawal"("p_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_role_to_app_metadata"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_role_to_app_metadata"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_role_to_app_metadata"() TO "service_role";



GRANT ALL ON TABLE "public"."alerts" TO "anon";
GRANT ALL ON TABLE "public"."alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."alerts" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."flota_members" TO "anon";
GRANT ALL ON TABLE "public"."flota_members" TO "authenticated";
GRANT ALL ON TABLE "public"."flota_members" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."platform_config" TO "anon";
GRANT ALL ON TABLE "public"."platform_config" TO "authenticated";
GRANT ALL ON TABLE "public"."platform_config" TO "service_role";



GRANT ALL ON TABLE "public"."product_likes" TO "anon";
GRANT ALL ON TABLE "public"."product_likes" TO "authenticated";
GRANT ALL ON TABLE "public"."product_likes" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."rating_moderation_log" TO "anon";
GRANT ALL ON TABLE "public"."rating_moderation_log" TO "authenticated";
GRANT ALL ON TABLE "public"."rating_moderation_log" TO "service_role";



GRANT ALL ON TABLE "public"."ratings" TO "anon";
GRANT ALL ON TABLE "public"."ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."ratings" TO "service_role";



GRANT ALL ON TABLE "public"."restaurant_banners" TO "anon";
GRANT ALL ON TABLE "public"."restaurant_banners" TO "authenticated";
GRANT ALL ON TABLE "public"."restaurant_banners" TO "service_role";



GRANT ALL ON TABLE "public"."restaurant_likes" TO "anon";
GRANT ALL ON TABLE "public"."restaurant_likes" TO "authenticated";
GRANT ALL ON TABLE "public"."restaurant_likes" TO "service_role";



GRANT ALL ON TABLE "public"."restaurants" TO "anon";
GRANT ALL ON TABLE "public"."restaurants" TO "authenticated";
GRANT ALL ON TABLE "public"."restaurants" TO "service_role";



GRANT ALL ON TABLE "public"."rider_locations" TO "anon";
GRANT ALL ON TABLE "public"."rider_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_locations" TO "service_role";



GRANT ALL ON TABLE "public"."rider_payout_accounts" TO "anon";
GRANT ALL ON TABLE "public"."rider_payout_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_payout_accounts" TO "service_role";



GRANT UPDATE("clabe") ON TABLE "public"."rider_payout_accounts" TO "authenticated";



GRANT UPDATE("updated_at") ON TABLE "public"."rider_payout_accounts" TO "authenticated";



GRANT ALL ON TABLE "public"."rider_stats" TO "anon";
GRANT ALL ON TABLE "public"."rider_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_stats" TO "service_role";



GRANT ALL ON TABLE "public"."rider_store_items" TO "anon";
GRANT ALL ON TABLE "public"."rider_store_items" TO "authenticated";
GRANT ALL ON TABLE "public"."rider_store_items" TO "service_role";



GRANT ALL ON TABLE "public"."withdrawal_status_log" TO "anon";
GRANT ALL ON TABLE "public"."withdrawal_status_log" TO "authenticated";
GRANT ALL ON TABLE "public"."withdrawal_status_log" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







