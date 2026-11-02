-- Pedidos creados y cobrados con montos del SERVIDOR — nov 2026.
--
-- Antes el celular calculaba total, envío, descuento y precio de cada
-- platillo, los insertaba tal cual en orders/order_items, y luego le pedía a
-- create-payment-intent cobrar el "amount" que él mismo mandaba — cualquiera
-- podía pagar $1 por un pedido de $800, o insertar un pedido ya marcado
-- payment_status='paid'. Además se cobraba ANTES de crear el pedido: si el
-- insert fallaba, el cliente quedaba cobrado sin pedido.
--
-- Flujo nuevo:
--   1. La app llama place_order() por cada restaurante del carrito. El
--      servidor toma precios de products (con la promo por platillo vigente),
--      calcula el envío con platform_config + coordenadas del restaurante,
--      valida la promoción con validate_promotion_for_order() y guarda todo
--      junto (pedido + platillos + promoción usada) en una sola transacción.
--   2. Efectivo: el pedido nace 'pending' (visible al restaurante, igual que
--      antes). Tarjeta: nace 'awaiting_payment' — ni el restaurante ni los
--      repartidores lo ven todavía.
--   3. create-payment-intent cobra la suma de orders.total (de la BD, nunca
--      del celular). Al confirmar Stripe (la propia app vía
--      action='confirm', o el webhook), el servidor pasa los pedidos a
--      payment_status='paid' + status='pending'. Si el cliente abandona el
--      pago, action='abandon' los cancela (y el trigger de promociones
--      devuelve el cupón).
--
-- Insertar directo en orders/order_items queda solo para admin (ver
-- 20261102000000_security_hardening.sql) — los builds viejos de la app que
-- todavía insertan directo dejan de poder crear pedidos hasta actualizarse.

create or replace function public.place_order(
  p_restaurant_id text,
  p_items jsonb,                       -- [{"product_id": "...", "quantity": n, "notes": "..."}]
  p_customer_name text,                -- JSON de entrega (nombre, teléfono, dirección, pago, lat, lng), igual que antes
  p_lat double precision default null,
  p_lng double precision default null,
  p_payment_method text default 'cash',
  p_group_id uuid default null,        -- mismo id en las 2 piernas de un pedido de 2 restaurantes
  p_promotion_claim_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_rest restaurants;
  v_prod products;
  v_item jsonb;
  v_qty int;
  v_paid_qty int;
  v_unit numeric;
  v_subtotal numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_promo_items jsonb := '[]'::jsonb;
  v_base numeric;
  v_per_km numeric;
  v_km numeric;
  v_fee numeric;
  v_promo jsonb;
  v_discount numeric := 0;
  v_ship_discount numeric := 0;
  v_total numeric;
  v_order_id text;
  v_group_count int := 0;
  v_surcharge numeric := 0;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;
  if p_payment_method not in ('cash', 'card') then
    raise exception 'metodo_pago_invalido';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'carrito_vacio';
  end if;

  select * into v_rest from restaurants where id = p_restaurant_id;
  if not found then
    raise exception 'restaurante_no_encontrado';
  end if;

  -- Precios siempre de products. La promo por platillo (% o 2x1, solo
  -- mientras promo_expires_at siga vigente) es la misma que muestra la
  -- lista de restaurantes — Product.promoPrice / CartItem.total en Dart.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty < 1 or v_qty > 50 then
      raise exception 'cantidad_invalida';
    end if;

    select * into v_prod from products
      where id = v_item ->> 'product_id' and restaurant_id = p_restaurant_id;
    if not found then
      raise exception 'producto_no_encontrado';
    end if;
    if v_prod.is_available is false then
      raise exception 'producto_no_disponible: %', v_prod.name;
    end if;

    v_unit := v_prod.price;
    v_paid_qty := v_qty;
    if v_prod.promo_expires_at is not null and v_prod.promo_expires_at > now() then
      if v_prod.promo_discount_percent is not null then
        v_unit := round(v_prod.price * (1 - v_prod.promo_discount_percent / 100.0), 2);
      end if;
      if v_prod.promo_is_2x1 then
        v_paid_qty := v_qty - (v_qty / 2);
      end if;
    end if;

    v_subtotal := v_subtotal + v_unit * v_paid_qty;
    v_lines := v_lines || jsonb_build_object(
      'product_id', v_prod.id,
      'name', v_prod.name,
      'quantity', v_qty,
      -- Precio unitario efectivo: quantity × price = lo que de verdad se cobra (2x1 incluido).
      'price', round(v_unit * v_paid_qty / v_qty, 2),
      'notes', nullif(v_item ->> 'notes', '')
    );
    v_promo_items := v_promo_items || jsonb_build_object(
      'product_id', v_prod.id,
      'category_id', v_prod.category_id,
      'quantity', v_qty,
      'unit_price', v_unit
    );
  end loop;

  -- Pedido de 2 restaurantes (20261031000000_multi_restaurant_orders.sql):
  -- máximo 2 piernas, todas del mismo cliente; la PRIMERA pierna que se
  -- crea lleva el recargo fijo de pedido combinado — igual que
  -- _deliveryFeesByRestaurant en checkout_screen.dart, pero decidido aquí
  -- para que nadie se lo pueda saltar.
  if p_group_id is not null then
    perform pg_advisory_xact_lock(hashtext(p_group_id::text));
    if exists (select 1 from orders where group_id = p_group_id and customer_id is distinct from v_uid) then
      raise exception 'grupo_invalido';
    end if;
    select count(*) into v_group_count from orders where group_id = p_group_id;
    if v_group_count >= 2 then
      raise exception 'Un pedido solo puede tener hasta 2 restaurantes.';
    end if;
  end if;

  -- Envío: mismo cálculo que LocationService.calcularCostoEnvio (tarifa base
  -- + tarifa por km en línea recta restaurante→cliente). Sin coordenadas,
  -- solo la tarifa base — igual que en la app.
  select
    coalesce(max(value::numeric) filter (where key = 'tarifa_base'), 15),
    coalesce(max(value::numeric) filter (where key = 'tarifa_por_km'), 5),
    coalesce(max(value::numeric) filter (where key = 'multi_restaurant_surcharge'), 15)
  into v_base, v_per_km, v_surcharge
  from platform_config
  where key in ('tarifa_base', 'tarifa_por_km', 'multi_restaurant_surcharge');

  if p_lat is not null and p_lng is not null and v_rest.lat is not null and v_rest.lng is not null then
    v_km := 2 * 6371 * asin(sqrt(
      power(sin(radians(p_lat - v_rest.lat) / 2), 2)
      + cos(radians(v_rest.lat)) * cos(radians(p_lat))
        * power(sin(radians(p_lng - v_rest.lng) / 2), 2)
    ));
    v_fee := v_base + v_per_km * v_km;
  else
    v_fee := v_base;
  end if;
  if p_group_id is not null and v_group_count = 0 then
    v_fee := v_fee + v_surcharge;
  end if;
  v_fee := round(v_fee, 2);

  if p_promotion_claim_id is not null then
    v_promo := validate_promotion_for_order(
      p_promotion_claim_id, p_restaurant_id, v_promo_items, v_subtotal, v_fee
    );
    if not coalesce((v_promo ->> 'valid')::boolean, false) then
      raise exception 'promocion_invalida: %', v_promo ->> 'reason';
    end if;
    v_discount := (v_promo ->> 'discount_amount')::numeric;
    if coalesce((v_promo ->> 'applies_to_shipping')::boolean, false) then
      -- Nunca deja el envío negativo (antes podía, si la promo se validó
      -- con una dirección más lejana que la final).
      v_ship_discount := least(v_fee, v_discount);
      v_discount := v_ship_discount;
    else
      v_discount := least(v_discount, v_subtotal);
    end if;
  end if;

  v_total := round(v_subtotal + v_fee - v_discount, 2);
  v_order_id := 'ord_' || (extract(epoch from clock_timestamp()) * 1000)::bigint
    || '_' || substr(md5(random()::text), 1, 6);

  -- Le avisa a guard_order_changes que este insert viene de aquí.
  perform set_config('gogo.trusted_order_write', 'on', true);

  insert into orders (
    id, restaurant_id, total, delivery_fee, rider_delivery_fee,
    status, customer_name, customer_id, group_id
  ) values (
    v_order_id, p_restaurant_id, v_total, v_fee - v_ship_discount, v_fee,
    case when p_payment_method = 'card' then 'awaiting_payment' else 'pending' end,
    p_customer_name, v_uid, p_group_id
  );

  insert into order_items (order_id, product_id, name, quantity, price, notes)
  select v_order_id, l ->> 'product_id', l ->> 'name', (l ->> 'quantity')::int,
         (l ->> 'price')::numeric, l ->> 'notes'
  from jsonb_array_elements(v_lines) l;

  -- Mismo efecto que apply_promotion_to_order, pero con el descuento que
  -- calculó el servidor. Si el pedido se cancela (incluido un pago con
  -- tarjeta abandonado), trg_revert_promo_claim_on_cancel lo devuelve.
  if p_promotion_claim_id is not null then
    update promotion_claims set
      status = 'used',
      used_at = now(),
      order_id = v_order_id,
      restaurant_id_at_use = p_restaurant_id,
      discount_amount = v_discount
    where id = p_promotion_claim_id and user_id = v_uid and status = 'available';
    if not found then
      raise exception 'promocion_ya_utilizada';
    end if;
  end if;

  perform set_config('gogo.trusted_order_write', 'off', true);

  return jsonb_build_object(
    'id', v_order_id,
    'total', v_total,
    'delivery_fee', v_fee - v_ship_discount,
    'discount', v_discount,
    'status', case when p_payment_method = 'card' then 'awaiting_payment' else 'pending' end
  );
end;
$$;

revoke execute on function public.place_order(text, jsonb, text, double precision, double precision, text, uuid, uuid) from anon, public;
grant execute on function public.place_order(text, jsonb, text, double precision, double precision, text, uuid, uuid) to authenticated, service_role;

-- apply_promotion_to_order aceptaba el descuento que mandara el celular.
-- place_order ya hace ese paso con el descuento del servidor.
revoke execute on function public.apply_promotion_to_order(uuid, text, numeric) from anon, authenticated, public;
