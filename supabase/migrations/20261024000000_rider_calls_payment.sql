-- Cobro real por "Pedir un repartidor" desde la app de escritorio — antes
-- esta llamada no costaba nada y no había ninguna fuente de dinero real
-- para pagarle al rider que acepta (fuera del flujo normal de pedidos, que
-- sí trae su propio delivery_fee). Ahora: $3 MXN de cuota de servicio
-- (para GOGO) + $35 MXN de envío (para el rider), cobrados de una vez al
-- restaurante al pedir, reembolsados solos si nadie acepta en 3 horas.

alter table public.rider_calls
  add column if not exists payment_intent_id text,
  add column if not exists payment_status text not null default 'pendiente'
    check (payment_status in ('pendiente', 'cobrado', 'reembolsado', 'fallido')),
  add column if not exists amount_envio numeric not null default 35,
  add column if not exists amount_fee numeric not null default 3,
  add column if not exists delivered_at timestamptz;

alter table public.rider_calls drop constraint if exists rider_calls_status_check;
alter table public.rider_calls add constraint rider_calls_status_check
  check (status in ('pendiente', 'aceptado', 'rechazado', 'cancelado', 'entregado'));

-- Cuenta de Stripe (Customer, NO Connect) que guarda la tarjeta del
-- restaurante para que SE LE pueda cobrar — totalmente aparte de su cuenta
-- de Connect, que es para que a ÉL le paguen sus ventas.
alter table public.restaurants
  add column if not exists stripe_customer_id text;

-- "Aceptado" solo significa que un rider dijo que va — sin esto, el
-- dinero se contaría como ganado del rider aunque nunca se haya
-- presentado. Lo marca el dueño (desde escritorio) o el mismo rider (desde
-- la app) una vez que de verdad entregó.
create or replace function mark_rider_call_delivered(p_call_id uuid)
returns boolean
language plpgsql
security definer
as $$
declare
  v_updated int;
  v_restaurant_id text;
  v_accepted_by uuid;
begin
  select restaurant_id, accepted_by into v_restaurant_id, v_accepted_by
  from rider_calls where id = p_call_id;

  if v_restaurant_id is null then
    raise exception 'llamada_no_encontrada';
  end if;

  if auth.uid() is distinct from v_accepted_by
     and v_restaurant_id is distinct from coalesce(
       (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'),
       (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
     ) then
    raise exception 'no_autorizado';
  end if;

  update rider_calls set
    status = 'entregado',
    delivered_at = now()
  where id = p_call_id and status = 'aceptado';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- get_rider_balance() ahora también suma los $35 de envío de cada
-- rider_call que ese rider de verdad entregó (status = 'entregado') Y que
-- el restaurante sí pagó (payment_status = 'cobrado') — mismo principio
-- que con pedidos normales: solo cuenta lo que de verdad generó dinero
-- real cobrado por Stripe.
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
                 where repartidor_id = v_rider and status = 'delivered' and payment_status = 'paid'), 0)
      +
      coalesce((select sum(amount_envio) from rider_calls
                 where accepted_by = v_rider and status = 'entregado' and payment_status = 'cobrado'), 0)
      as ganado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;
