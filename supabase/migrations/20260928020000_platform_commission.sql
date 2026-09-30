-- Comisión de la plataforma (GOGO): 10% sobre el envío que gana un
-- repartidor, y 10% sobre las ventas de cada restaurante. Antes no existía
-- ninguna comisión — el repartidor se quedaba el 100% del delivery_fee y el
-- restaurante veía sus ventas brutas sin ningún descuento.

insert into platform_config (key, value) values
  ('comision_repartidor_pct', '10'),
  ('comision_restaurante_pct', '10')
on conflict (key) do update set value = excluded.value;

-- El saldo del repartidor ya no es 100% del delivery_fee — se le descuenta
-- la comisión configurada. Sigue calculándose en vivo (nunca se guarda),
-- mismo patrón de antes.
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
      coalesce((select sum(delivery_fee) * (1 - v_comision_pct / 100) from orders
                 where repartidor_id = v_rider and status = 'delivered'), 0) as ganado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;
