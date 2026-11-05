-- Bloque 2, punto 8: get_rider_balance() es la ÚNICA función SECURITY
-- DEFINER de todo el proyecto sin NINGÚN search_path fijo (ni siquiera
-- 'public' a secas) — se le olvidó ponerlo al agregarla en
-- 20261103010000_order_tips.sql. Sin un search_path fijo, una función
-- SECURITY DEFINER corre con el search_path de quien la llama: un usuario
-- cualquiera podría crear un esquema con prioridad más alta y una función
-- "platform_config"/"is_admin" propia que esta función terminaría llamando
-- por accidente, con los privilegios del dueño (postgres).
--
-- Mismo barrido (loop del hardening de nov 2026) sobre las demás funciones
-- SECURITY DEFINER agregadas en esta misma ronda que solo tenían
-- 'search_path TO public' (sin 'extensions, pg_temp', el estándar que ya
-- usan is_admin/is_dueno/etc. desde la auditoría de seguridad): se
-- actualizan al mismo estándar por consistencia, aunque ninguna de ellas
-- llama hoy a algo de la extensión pgcrypto/pg_net — es más barato
-- igualarlas ahora que auditar cada una por separado cada vez que se toquen.
create or replace function public.get_rider_balance(p_rider_id uuid default null)
returns table(total_ganado numeric, total_retirado numeric, total_reservado numeric, saldo_disponible numeric)
language plpgsql
stable security definer
set search_path = public, extensions, pg_temp
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

create or replace function public.claim_group_order(p_order_id text)
returns text[]
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_group_id uuid;
  v_claimed text[];
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  select group_id into v_group_id from public.orders where id = p_order_id;
  if not found then
    raise exception 'Este pedido ya no existe.';
  end if;

  if v_group_id is null then
    update public.orders
      set status = 'accepted', repartidor_id = v_uid
      where id = p_order_id and status = 'restaurant_accepted' and repartidor_id is null;
    if not found then
      raise exception 'Ya se lo llevó otro repartidor.';
    end if;
    return array[p_order_id];
  end if;

  with updated as (
    update public.orders
      set status = 'accepted', repartidor_id = v_uid
      where group_id = v_group_id and status = 'restaurant_accepted' and repartidor_id is null
      returning id
  )
  select array_agg(id) into v_claimed from updated;

  if v_claimed is null or array_length(v_claimed, 1) is null then
    raise exception 'Ya se lo llevó otro repartidor.';
  end if;

  return v_claimed;
end;
$function$;

create or replace function public.get_support_threads()
returns table (
  user_id uuid,
  last_body text,
  last_sender text,
  last_created_at timestamptz,
  unread_count bigint
)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
begin
  if not is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
    select t.user_id, t.body, t.sender, t.created_at, t.unread_count
    from (
      select distinct on (sm.user_id)
        sm.user_id,
        sm.body,
        sm.sender,
        sm.created_at,
        (
          select count(*) from public.support_messages u
          where u.user_id = sm.user_id and u.sender = 'user' and u.read_at is null
        ) as unread_count
      from public.support_messages sm
      where sm.user_id is not null
      order by sm.user_id, sm.created_at desc
    ) t
    order by t.created_at desc;
end;
$function$;

create or replace function public.mark_support_messages_read(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
begin
  if is_admin() then
    update public.support_messages
      set read_at = now()
      where user_id = p_user_id and sender = 'user' and read_at is null;
  elsif auth.uid() = p_user_id then
    update public.support_messages
      set read_at = now()
      where user_id = p_user_id and sender = 'admin' and read_at is null;
  else
    raise exception 'No autorizado';
  end if;
end;
$function$;

create or replace function public.request_order_refund(p_order_id text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_payment_status text;
  v_stripe_intent text;
  v_new_id uuid;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Escribe el motivo de tu reembolso.';
  end if;

  select customer_id, payment_status, stripe_payment_intent_id
    into v_customer_id, v_payment_status, v_stripe_intent
  from public.orders
  where id = p_order_id;

  if v_customer_id is null or v_customer_id is distinct from v_uid then
    raise exception 'No puedes pedir un reembolso de un pedido que no es tuyo.';
  end if;

  if v_payment_status is distinct from 'paid' or v_stripe_intent is null then
    raise exception 'Este pedido no tiene un pago con tarjeta confirmado que se pueda reembolsar.';
  end if;

  if exists (
    select 1 from public.order_refund_requests
    where order_id = p_order_id and status in ('pendiente', 'aprobado')
  ) then
    raise exception 'Ya tienes una solicitud de reembolso abierta para este pedido.';
  end if;

  insert into public.order_refund_requests (order_id, requested_by, reason)
  values (p_order_id, v_uid, trim(p_reason))
  returning id into v_new_id;

  return v_new_id;
end;
$function$;
