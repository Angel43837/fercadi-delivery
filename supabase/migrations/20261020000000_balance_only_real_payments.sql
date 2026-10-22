-- Bug real encontrado oct 2026 (reportado directo por el negocio): tanto
-- get_rider_balance() como get_restaurant_balance() sumaban TODOS los
-- pedidos 'delivered' sin importar cómo se pagaron — incluyendo los
-- pagados en EFECTIVO, donde GOGO nunca recibió nada de ese dinero en su
-- cuenta de Stripe. Con los retiros ahora pagándose de verdad por Stripe
-- Connect, esto significaba transferir dinero real de la plataforma por
-- pedidos que nunca generaron ningún ingreso real — y para el repartidor,
-- encima, un doble pago: ya se quedó con el efectivo del cliente en la
-- entrega, y el saldo lo volvía a contar como "ganado" para retirar aparte.
--
-- checkout_screen.dart ya distingue esto con claridad: payment_status
-- queda en 'paid' solo cuando se pagó con tarjeta (Stripe); en efectivo se
-- queda null. Ambas funciones ahora exigen payment_status = 'paid' para
-- contar un pedido como "ganado" retirable.

create or replace function get_rider_balance(p_rider_id uuid default null)
returns table(total_ganado numeric, total_retirado numeric, total_reservado numeric, saldo_disponible numeric)
language plpgsql
stable security definer
as $function$
declare
  v_rider uuid := coalesce(p_rider_id, auth.uid());
  v_comision_pct numeric;
begin
  if v_rider is null then
    raise exception 'no_autenticado';
  end if;
  if v_rider is distinct from auth.uid() and not coalesce(is_admin(), false) then
    raise exception 'no_autorizado';
  end if;

  select coalesce(value::numeric, 10) into v_comision_pct
  from platform_config where key = 'comision_repartidor_pct';
  v_comision_pct := coalesce(v_comision_pct, 10);

  return query
  select ganado, retirado, reservado, ganado - retirado - reservado
  from (
    select
      coalesce((select sum(coalesce(rider_delivery_fee, delivery_fee)) * (1 - v_comision_pct / 100) from orders
                 where repartidor_id = v_rider and status = 'delivered' and payment_status = 'paid'), 0) as ganado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;

create or replace function get_restaurant_balance(p_restaurant_id text default null)
returns table(total_ganado numeric, total_retirado numeric, total_reservado numeric, saldo_disponible numeric)
language plpgsql
stable security definer
as $function$
declare
  v_restaurant text := coalesce(p_restaurant_id, (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'));
  v_comision_pct numeric;
begin
  if v_restaurant is null then
    raise exception 'no_autenticado';
  end if;
  if v_restaurant is distinct from (auth.jwt() -> 'app_metadata' ->> 'restaurant_id')
     and not coalesce(is_admin(), false) then
    raise exception 'no_autorizado';
  end if;

  select coalesce(value::numeric, 10) into v_comision_pct
  from platform_config where key = 'comision_restaurante_pct';
  v_comision_pct := coalesce(v_comision_pct, 10);

  return query
  select ganado, retirado, reservado, ganado - retirado - reservado
  from (
    select
      coalesce((select sum(total - coalesce(delivery_fee, 0)) * (1 - v_comision_pct / 100) from orders
                 where restaurant_id = v_restaurant and status = 'delivered' and payment_status = 'paid'), 0) as ganado,
      coalesce((select sum(amount) from restaurant_withdrawals
                 where restaurant_id = v_restaurant and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from restaurant_withdrawals
                 where restaurant_id = v_restaurant and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;
