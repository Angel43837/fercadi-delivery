-- Validación real de montos contra manipulación — hallazgo de la auditoría
-- de tiendas: create-payment-intent SÍ tenía código para verificar el monto
-- contra la BD, pero dependía de un orderId que checkout_screen.dart nunca
-- manda (el pago ocurre ANTES de crear el pedido, así que ese orderId no
-- existe todavía) — en la práctica, esa verificación nunca se activaba.
--
-- Más grave: incluso el camino que SÍ corre siempre que hay una promoción
-- (validate_promotion_for_order) calculaba el subtotal elegible usando
-- v_item->>'unit_price', un precio que MANDA EL CELULAR — nunca se
-- comparaba contra products.price de verdad. Un cliente modificado podía
-- mandar unit_price=0.01 para cada producto: la promoción "validaba" bien
-- (la aritmética del descuento era correcta), pero aplicada sobre precios
-- inventados. Y cuando NO había promoción (el caso más común), no se
-- verificaba el carrito en absoluto.
--
-- Corrección: SIEMPRE se recalcula el subtotal desde products.price (nunca
-- desde lo que manda el cliente), tanto con promoción como sin ella. De
-- paso se corrige que el precio con descuento POR PRODUCTO
-- (promo_discount_percent, el mismo que ya calcula Product.promoPrice en
-- Dart) nunca se aplicaba en ningún lado del cobro real — ver
-- cart_item.dart, corregido en el mismo cambio de sesión.
--
-- NOTA sobre promo_is_2x1 (producto): sigue sin tener ninguna fórmula de
-- precio definida en ningún lado del código (ni aquí ni en Dart) — es solo
-- una insignia visual hoy. No se inventa una regla de negocio nueva aquí;
-- queda documentado como gap aparte, pendiente de que el dueño del negocio
-- defina cómo debe calcularse antes de tocarlo.

begin;

-- Subtotal real de un carrito, SIEMPRE desde products.price (con el
-- descuento por producto activo aplicado) — nunca desde lo que manda el
-- cliente. p_cart_items solo necesita product_id/quantity; cualquier
-- unit_price que venga del cliente se ignora por completo.
create or replace function public.compute_cart_subtotal(p_cart_items jsonb)
returns numeric
language plpgsql
stable
set search_path = public
as $function$
declare
  v_item jsonb;
  v_product products;
  v_unit_price numeric;
  v_subtotal numeric := 0;
begin
  for v_item in select * from jsonb_array_elements(p_cart_items) loop
    select * into v_product from products where id = (v_item->>'product_id');
    if not found then
      raise exception 'Producto no encontrado: %', (v_item->>'product_id');
    end if;

    v_unit_price := v_product.price;
    if v_product.promo_discount_percent is not null
       and v_product.promo_expires_at is not null and v_product.promo_expires_at > now() then
      v_unit_price := v_product.price * (1 - v_product.promo_discount_percent::numeric / 100);
    end if;

    v_subtotal := v_subtotal + (v_unit_price * (v_item->>'quantity')::int);
  end loop;

  return round(v_subtotal, 2);
end;
$function$;

grant execute on function public.compute_cart_subtotal(jsonb) to authenticated;

-- validate_promotion_for_order, parchada: el bucle de abajo usaba
-- v_item->>'unit_price' (lo que manda el cliente) para calcular el
-- subtotal elegible y el precio del "producto gratis" — ahora busca el
-- precio real en products (ya con el descuento por producto activo
-- aplicado, igual que Product.promoPrice en Dart). p_subtotal (el
-- parámetro, también controlado por el cliente) ya NO se usa para el
-- candado de compra mínima — se reemplaza por el subtotal real calculado
-- aquí mismo. El resto de la función (reglas de cada tipo de promoción,
-- límites, horarios, etc.) se deja exactamente igual.
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
  v_product products;
  v_real_unit_price numeric;
  v_real_subtotal numeric;
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

  v_real_subtotal := compute_cart_subtotal(p_cart_items);
  if v_real_subtotal < v_promo.min_purchase_amount then
    return jsonb_build_object('valid', false, 'reason', 'compra_minima_no_alcanzada',
      'min_purchase_amount', v_promo.min_purchase_amount);
  end if;

  -- Subtotal/cantidad elegible: si no hay restricción de producto/categoría, todo el carrito cuenta.
  -- El precio de cada producto SIEMPRE sale de la tabla products (con su
  -- descuento por producto activo, si tiene) — nunca del unit_price que
  -- venga en p_cart_items.
  for v_item in select * from jsonb_array_elements(p_cart_items) loop
    select * into v_product from products where id = (v_item->>'product_id');
    if not found then
      return jsonb_build_object('valid', false, 'reason', 'producto_no_encontrado');
    end if;
    v_real_unit_price := v_product.price;
    if v_product.promo_discount_percent is not null
       and v_product.promo_expires_at is not null and v_product.promo_expires_at > v_now then
      v_real_unit_price := v_product.price * (1 - v_product.promo_discount_percent::numeric / 100);
    end if;

    if (v_promo.applicable_product_ids is null or array_length(v_promo.applicable_product_ids, 1) is null
          or (v_item->>'product_id') = any(v_promo.applicable_product_ids))
       and (v_promo.applicable_category_ids is null or array_length(v_promo.applicable_category_ids, 1) is null
          or (v_item->>'category_id') = any(v_promo.applicable_category_ids)) then
      v_eligible_subtotal := v_eligible_subtotal + (v_real_unit_price * (v_item->>'quantity')::int);
      v_eligible_qty := v_eligible_qty + (v_item->>'quantity')::int;
    end if;

    if v_promo.type = 'free_product' and v_promo.free_product_id is not null
       and (v_item->>'product_id') = v_promo.free_product_id then
      v_free_product_in_cart := true;
      v_free_product_price := v_real_unit_price;
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
    'real_subtotal', v_real_subtotal,
    'applies_to_shipping', v_promo.type = 'free_shipping' or v_promo.applies_to_shipping,
    'type', v_promo.type
  );
end;
$$;

grant execute on function validate_promotion_for_order(uuid, text, jsonb, numeric, numeric) to authenticated;

commit;
