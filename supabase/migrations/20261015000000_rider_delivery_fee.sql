-- Bug real encontrado oct 2026: un promo de "envío gratis" (o cualquier
-- promo con applies_to_shipping=true) descuenta el delivery_fee del pedido
-- hasta dejarlo en 0 — eso está bien para lo que le cobra al CLIENTE (sí
-- debe ver "envío gratis"), pero get_rider_balance() y todas las pantallas
-- de ganancias (repartidor_screen.dart, repartidor_plus_screen.dart,
-- flota_screen.dart, flota_rider_detail_screen.dart) suman ese MISMO
-- delivery_fee para calcular cuánto le toca al repartidor — así que un
-- repartidor que entrega un pedido con envío gratis termina trabajando
-- gratis, aunque hizo exactamente el mismo recorrido. El costo de la promo
-- lo debe absorber la plataforma/restaurante, nunca el repartidor.
--
-- rider_delivery_fee guarda el envío NOMINAL (antes de cualquier descuento
-- de promoción) — es lo que de verdad se le paga al repartidor.
-- delivery_fee se queda igual, sigue siendo lo que se le cobró al cliente.
alter table orders add column if not exists rider_delivery_fee numeric;

-- Backfill: para pedidos ya existentes no se puede recuperar el monto
-- nominal real si tuvieron descuento, pero la gran mayoría no tuvo ninguna
-- promo de envío — usar delivery_fee como mejor aproximación disponible.
update orders set rider_delivery_fee = delivery_fee where rider_delivery_fee is null;

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
                 where repartidor_id = v_rider and status = 'delivered'), 0) as ganado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;
