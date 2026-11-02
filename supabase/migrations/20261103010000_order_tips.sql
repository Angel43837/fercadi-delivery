-- Bloque 1, punto 6: rating_dialog.dart llama a create-tip-payment-intent,
-- que no existía — cualquier intento de dar propina con tarjeta fallaba (y
-- de paso se perdía la calificación completa, ver el fix en rating_dialog.dart
-- y submitRating). Esta migración solo prepara la base; la Edge Function va
-- en supabase/functions/create-tip-payment-intent/.

create table if not exists public.order_tips (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references public.orders(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  repartidor_id uuid references auth.users(id) on delete set null,
  amount numeric not null check (amount > 0),
  stripe_payment_intent_id text,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'failed')),
  created_at timestamptz not null default now(),
  unique (order_id)
);

alter table public.order_tips enable row level security;

-- Solo lectura desde la app — insert/update los hace la Edge Function con
-- service_role (igual que order_refund_requests/rider_calls, ver auditoría
-- de seguridad nov 2026), nunca directo desde el cliente.
drop policy if exists "read_own_tips_customer" on public.order_tips;
create policy "read_own_tips_customer" on public.order_tips
  for select using (customer_id = auth.uid());

drop policy if exists "read_own_tips_rider" on public.order_tips;
create policy "read_own_tips_rider" on public.order_tips
  for select using (repartidor_id = auth.uid());

drop policy if exists "read_own_tips_admin" on public.order_tips;
create policy "read_own_tips_admin" on public.order_tips
  for select using (is_admin());

-- get_rider_balance() ahora también suma las propinas ya cobradas — van
-- completas al repartidor, sin el 10% de comisión (no son parte de la venta
-- del restaurante ni del envío, las paga el cliente aparte y a propósito).
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
      +
      coalesce((select sum(amount) from order_tips
                 where repartidor_id = v_rider and status = 'paid'), 0)
      as ganado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from rider_withdrawals
                 where rider_id = v_rider and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;
