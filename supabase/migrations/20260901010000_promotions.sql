-- Sistema real de promociones/cupones — separado por completo de los
-- banners (app_promos, restaurant_banners), que se quedan como contenido
-- visual/publicitario. Antes de esto no existía ningún concepto de
-- "reclamar" una promoción, ni un registro de quién la usó, ni validación
-- del lado del servidor de ningún descuento — todo lo de este archivo es
-- nuevo.
--
-- Dos tablas (no tres): promotions (la definición) y promotion_claims (una
-- fila = una promoción reclamada por un usuario — la misma fila sirve para
-- "Mis promociones" Y como historial de uso, evita una tercera tabla
-- redundante). Los 4 estados que ve el cliente (Disponible/Próximamente/
-- Expirada/Utilizada) se calculan al leer, nunca se guardan — así no hace
-- falta ningún proceso en segundo plano que "expire" cosas.
--
-- Mismo patrón de RLS que app_promos (lectura pública, escritura solo
-- is_admin()). Reclamar y usar una promoción nunca es un INSERT/UPDATE
-- directo desde la app — solo a través de las funciones de abajo, mismo
-- candado que ya usan los retiros de repartidores (request_withdrawal).
--
-- Aplicado a GOGO-Pruebas el 2026-09-01. Pendiente de aplicar a producción.

-- ── Tabla: promotions ────────────────────────────────────────────────────

create table if not exists promotions (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('2x1', 'percent', 'fixed_amount', 'free_shipping', 'free_product')),
  title text not null,
  description text default '',
  image_url text,
  benefit_label text default '',
  code text,
  terms text default '',

  restaurant_id text references restaurants(id) on delete cascade,  -- null = de toda la plataforma
  applicable_product_ids text[],
  applicable_category_ids text[],
  free_product_id text references products(id) on delete set null,  -- solo type = 'free_product'

  min_purchase_amount numeric not null default 0,
  max_discount_amount numeric,  -- tope, null = sin tope

  starts_at timestamptz,
  expires_at timestamptz,
  time_window_start time,
  time_window_end time,
  days_of_week int[],  -- 1=lunes .. 7=domingo, null/vacío = todos los días

  max_total_uses int,       -- null = sin límite
  max_uses_per_user int not null default 1,
  max_claims int,           -- null = sin límite de gente que puede reclamarla
  combinable boolean not null default false,
  applies_to_shipping boolean not null default false,

  rules jsonb not null default '{}'::jsonb,  -- parámetro específico del tipo: {"percent":20} / {"amount":50} / {"min_qty":2}

  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_promotions_restaurant_active on promotions(restaurant_id, is_active);
create index if not exists idx_promotions_active_dates on promotions(is_active, starts_at, expires_at);

alter table promotions enable row level security;

drop policy if exists "read_promotions" on promotions;
create policy "read_promotions" on promotions
  for select using (is_active or is_admin());

drop policy if exists "write_promotions" on promotions;
create policy "write_promotions" on promotions
  using (is_admin()) with check (is_admin());

-- ── Tabla: promotion_claims ──────────────────────────────────────────────

create table if not exists promotion_claims (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references promotions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  restaurant_id text,  -- copia de promotions.restaurant_id al reclamar (blindaje, evita un join extra en el historial)

  status text not null default 'available' check (status in ('available', 'used', 'revoked')),
  claimed_at timestamptz not null default now(),
  used_at timestamptz,
  order_id text references orders(id) on delete set null,
  restaurant_id_at_use text,  -- a cuál restaurante se le aplicó de verdad (importa solo para promos de toda la plataforma)
  discount_amount numeric,

  created_at timestamptz not null default now()
);

create index if not exists idx_promotion_claims_user_status on promotion_claims(user_id, status);
create index if not exists idx_promotion_claims_promotion on promotion_claims(promotion_id);
create index if not exists idx_promotion_claims_order on promotion_claims(order_id);

alter table promotion_claims enable row level security;

drop policy if exists "read_own_promotion_claims" on promotion_claims;
create policy "read_own_promotion_claims" on promotion_claims
  for select using (
    user_id = auth.uid()
    or is_admin()
    or (is_dueno() and restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'))
  );

-- Sin políticas de insert/update para "authenticated": reclamar y usar una
-- promoción solo pasa a través de las funciones security definer de abajo.

-- ── app_promos: enlace opcional a una promoción real ────────────────────

alter table app_promos add column if not exists linked_promotion_id uuid references promotions(id) on delete set null;

-- ── Función: claim_promotion ─────────────────────────────────────────────
-- Único lugar donde se crea un reclamo nuevo. Valida que la promoción
-- exista, esté activa, en fechas, y que no se haya llegado al límite de
-- gente que puede reclamarla ni al límite por usuario.

create or replace function claim_promotion(p_promotion_id uuid)
returns promotion_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_promo promotions;
  v_uid uuid := auth.uid();
  v_claim_count int;
  v_user_claims int;
  v_new promotion_claims;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  select * into v_promo from promotions where id = p_promotion_id for update;
  if not found then
    raise exception 'promocion_no_encontrada';
  end if;
  if not v_promo.is_active then
    raise exception 'promocion_inactiva';
  end if;
  if v_promo.starts_at is not null and now() < v_promo.starts_at then
    raise exception 'promocion_no_iniciada';
  end if;
  if v_promo.expires_at is not null and now() > v_promo.expires_at then
    raise exception 'promocion_expirada';
  end if;

  if v_promo.max_claims is not null then
    select count(*) into v_claim_count from promotion_claims where promotion_id = p_promotion_id;
    if v_claim_count >= v_promo.max_claims then
      raise exception 'limite_de_reclamos_alcanzado';
    end if;
  end if;

  select count(*) into v_user_claims
    from promotion_claims
    where promotion_id = p_promotion_id and user_id = v_uid;
  if v_user_claims >= v_promo.max_uses_per_user then
    raise exception 'ya_reclamaste_el_maximo';
  end if;

  insert into promotion_claims (promotion_id, user_id, restaurant_id)
    values (p_promotion_id, v_uid, v_promo.restaurant_id)
    returning * into v_new;

  return v_new;
end;
$$;

grant execute on function claim_promotion(uuid) to authenticated;

-- ── Función: validate_promotion_for_order ────────────────────────────────
-- Solo lectura (STABLE, no security definer — corre con los permisos del
-- que llama, así que RLS ya protege que solo se pueda validar un reclamo
-- propio). Recibe el carrito y regresa el descuento YA calculado por el
-- servidor — Dart nunca inventa este número, siempre lo pide aquí.
--
-- p_cart_items: [{"product_id":"...", "category_id":"...", "quantity":n, "unit_price":x}, ...]

create or replace function validate_promotion_for_order(
  p_claim_id uuid,
  p_restaurant_id text,
  p_cart_items jsonb,
  p_subtotal numeric,
  p_delivery_fee numeric
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_claim promotion_claims;
  v_promo promotions;
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_local_time time := (v_now at time zone 'America/Mexico_City')::time;
  v_dow int := extract(isodow from (v_now at time zone 'America/Mexico_City'))::int;
  v_eligible_subtotal numeric := 0;
  v_eligible_qty int := 0;
  v_item jsonb;
  v_discount numeric := 0;
  v_used_count int;
  v_free_product_price numeric;
  v_free_product_in_cart boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('valid', false, 'reason', 'no_autenticado');
  end if;

  select * into v_claim from promotion_claims where id = p_claim_id;
  if not found or v_claim.user_id <> v_uid then
    return jsonb_build_object('valid', false, 'reason', 'claim_no_encontrado');
  end if;
  if v_claim.status <> 'available' then
    return jsonb_build_object('valid', false, 'reason', 'ya_utilizada');
  end if;

  select * into v_promo from promotions where id = v_claim.promotion_id;
  if not found or not v_promo.is_active then
    return jsonb_build_object('valid', false, 'reason', 'promocion_inactiva');
  end if;
  if v_promo.starts_at is not null and v_now < v_promo.starts_at then
    return jsonb_build_object('valid', false, 'reason', 'promocion_no_iniciada');
  end if;
  if v_promo.expires_at is not null and v_now > v_promo.expires_at then
    return jsonb_build_object('valid', false, 'reason', 'promocion_expirada');
  end if;
  if v_promo.restaurant_id is not null and v_promo.restaurant_id <> p_restaurant_id then
    return jsonb_build_object('valid', false, 'reason', 'restaurante_no_coincide');
  end if;
  if v_promo.time_window_start is not null and v_promo.time_window_end is not null
     and v_local_time not between v_promo.time_window_start and v_promo.time_window_end then
    return jsonb_build_object('valid', false, 'reason', 'fuera_de_horario');
  end if;
  if v_promo.days_of_week is not null and array_length(v_promo.days_of_week, 1) > 0
     and not (v_dow = any(v_promo.days_of_week)) then
    return jsonb_build_object('valid', false, 'reason', 'dia_no_valido');
  end if;
  if v_promo.max_total_uses is not null then
    select count(*) into v_used_count from promotion_claims
      where promotion_id = v_promo.id and status = 'used';
    if v_used_count >= v_promo.max_total_uses then
      return jsonb_build_object('valid', false, 'reason', 'usos_agotados');
    end if;
  end if;
  if p_subtotal < v_promo.min_purchase_amount then
    return jsonb_build_object('valid', false, 'reason', 'compra_minima_no_alcanzada',
      'min_purchase_amount', v_promo.min_purchase_amount);
  end if;

  -- Subtotal/cantidad elegible: si no hay restricción de producto/categoría, todo el carrito cuenta.
  for v_item in select * from jsonb_array_elements(p_cart_items) loop
    if (v_promo.applicable_product_ids is null or array_length(v_promo.applicable_product_ids, 1) is null
          or (v_item->>'product_id') = any(v_promo.applicable_product_ids))
       and (v_promo.applicable_category_ids is null or array_length(v_promo.applicable_category_ids, 1) is null
          or (v_item->>'category_id') = any(v_promo.applicable_category_ids)) then
      v_eligible_subtotal := v_eligible_subtotal + ((v_item->>'unit_price')::numeric * (v_item->>'quantity')::int);
      v_eligible_qty := v_eligible_qty + (v_item->>'quantity')::int;
    end if;

    if v_promo.type = 'free_product' and v_promo.free_product_id is not null
       and (v_item->>'product_id') = v_promo.free_product_id then
      v_free_product_in_cart := true;
      v_free_product_price := (v_item->>'unit_price')::numeric;
    end if;
  end loop;

  if v_eligible_qty = 0 and v_promo.type <> 'free_shipping' and v_promo.type <> 'free_product' then
    return jsonb_build_object('valid', false, 'reason', 'productos_no_elegibles');
  end if;

  case v_promo.type
    when '2x1' then
      declare
        v_min_qty int := coalesce((v_promo.rules->>'min_qty')::int, 2);
        v_avg_price numeric := case when v_eligible_qty > 0 then v_eligible_subtotal / v_eligible_qty else 0 end;
        v_pairs int := floor(v_eligible_qty::numeric / v_min_qty);
      begin
        v_discount := v_pairs * v_avg_price;
      end;
    when 'percent' then
      v_discount := v_eligible_subtotal * coalesce((v_promo.rules->>'percent')::numeric, 0) / 100;
    when 'fixed_amount' then
      v_discount := least(coalesce((v_promo.rules->>'amount')::numeric, 0), v_eligible_subtotal);
    when 'free_shipping' then
      v_discount := least(p_delivery_fee, coalesce(v_promo.max_discount_amount, p_delivery_fee));
    when 'free_product' then
      if not v_free_product_in_cart then
        return jsonb_build_object('valid', false, 'reason', 'requiere_producto_gratis_en_carrito',
          'free_product_id', v_promo.free_product_id);
      end if;
      v_discount := v_free_product_price;
    else
      return jsonb_build_object('valid', false, 'reason', 'tipo_no_soportado');
  end case;

  if v_promo.max_discount_amount is not null and v_promo.type <> 'free_shipping' then
    v_discount := least(v_discount, v_promo.max_discount_amount);
  end if;

  return jsonb_build_object(
    'valid', true,
    'discount_amount', round(v_discount, 2),
    'eligible_subtotal', v_eligible_subtotal,
    'applies_to_shipping', v_promo.type = 'free_shipping' or v_promo.applies_to_shipping,
    'type', v_promo.type
  );
end;
$$;

grant execute on function validate_promotion_for_order(uuid, text, jsonb, numeric, numeric) to authenticated;

-- ── Función: apply_promotion_to_order ────────────────────────────────────
-- Se llama justo después de que el pedido ya se creó de verdad (nunca
-- antes). Vuelve a validar dueño del reclamo y estado (último candado
-- contra condiciones de carrera) y marca como usado.

create or replace function apply_promotion_to_order(
  p_claim_id uuid,
  p_order_id text,
  p_discount_amount numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim promotion_claims;
  v_uid uuid := auth.uid();
  v_order_owner uuid;
  v_order_restaurant text;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  select * into v_claim from promotion_claims where id = p_claim_id for update;
  if not found or v_claim.user_id <> v_uid then
    raise exception 'claim_no_encontrado';
  end if;
  if v_claim.status <> 'available' then
    raise exception 'ya_utilizada';
  end if;

  select customer_id, restaurant_id into v_order_owner, v_order_restaurant
    from orders where id = p_order_id;
  if not found or v_order_owner <> v_uid then
    raise exception 'pedido_no_encontrado';
  end if;

  update promotion_claims set
    status = 'used',
    used_at = now(),
    order_id = p_order_id,
    restaurant_id_at_use = v_order_restaurant,
    discount_amount = p_discount_amount
  where id = p_claim_id;
end;
$$;

grant execute on function apply_promotion_to_order(uuid, text, numeric) to authenticated;

-- ── Trigger: revertir el reclamo si el pedido se cancela ────────────────
-- Cubre los dos caminos que existen para cancelar (updateOrderStatus y
-- adminUpdateOrderStatus, usados desde distintas pantallas) sin tener que
-- tocar el código de ninguno de los dos — y también cubre cualquier
-- cambio de estado hecho directo por SQL/dashboard.

create or replace function revert_promotion_claims_for_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    update promotion_claims set
      status = 'available',
      used_at = null,
      order_id = null,
      restaurant_id_at_use = null,
      discount_amount = null
    where order_id = new.id and status = 'used';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_revert_promo_claim_on_cancel on orders;
create trigger trg_revert_promo_claim_on_cancel
  after update of status on orders
  for each row
  execute function revert_promotion_claims_for_order();

-- Nota para el futuro: esto asume que "el pedido ya se creó" = "el pago ya
-- se confirmó" (cierto hoy para efectivo y tarjeta, que es como paga todo
-- el mundo ahora mismo). Si algún día se activa OXXO en la pantalla de
-- pago (el código para OXXO ya existe en el backend pero hoy no es
-- seleccionable en checkout_screen.dart), un pedido con OXXO se crea ANTES
-- de que el pago se confirme de verdad — en ese caso, apply_promotion_to_order
-- tendría que llamarse desde el webhook de Stripe (payment_intent.succeeded)
-- en vez de justo después de crear el pedido.
