-- Bloque 3, punto 17: delete_my_account() bloqueaba la eliminación de la
-- cuenta si el cliente tenía un pedido 'awaiting_payment' viejo y abandonado
-- (pago que nunca se confirmó ni se canceló) — un pedido así puede quedarse
-- en ese estado indefinidamente (antes del job de sweep_awaiting_payments,
-- ver 20261103000000), y no tiene sentido obligar a esperar a que se
-- resuelva solo para poder borrar la cuenta. Ahora esos pedidos propios se
-- cancelan primero, automáticamente, y solo entonces se revisa si sigue
-- habiendo algo de verdad en curso.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
  v_restaurant_id text;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  -- Pedidos propios 'awaiting_payment' abandonados: se cancelan solos, no
  -- cuentan como "pedido en curso" para el candado de abajo.
  update orders set status = 'cancelled'
  where customer_id = v_uid and status = 'awaiting_payment';

  -- Cualquier rol: no se puede borrar con un pedido propio todavía en curso.
  if exists (
    select 1 from orders
    where customer_id = v_uid
      and status not in ('delivered', 'cancelled')
  ) then
    raise exception 'Tienes un pedido en curso, espera a que se entregue o se cancele antes de eliminar tu cuenta.';
  end if;

  -- ── Repartidor (flota o independiente/"plus") ──────────────────────────
  if v_role in ('repartidor', 'repartidor_plus') then
    if exists (
      select 1 from rider_withdrawals
      where rider_id = v_uid and status in ('pendiente', 'en_proceso')
    ) then
      raise exception 'Tienes un retiro en proceso, espera a que se complete antes de eliminar tu cuenta.';
    end if;

    if exists (
      select 1 from orders
      where repartidor_id = v_uid and status in ('accepted', 'delivering')
    ) or exists (
      select 1 from rider_calls
      where accepted_by = v_uid and status = 'aceptado'
    ) then
      raise exception 'Tienes una entrega en curso, termínala antes de eliminar tu cuenta.';
    end if;

    delete from rider_payout_accounts where rider_id = v_uid;

  -- ── Dueño de restaurante ────────────────────────────────────────────────
  elsif v_role = 'dueno' then
    -- JWT o owner_id: un dueño recién registrado todavía puede no tener
    -- restaurant_id en el JWT.
    select r.id into v_restaurant_id
    from restaurants r
    where r.id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id')
       or r.owner_id = v_uid
    limit 1;

    if v_restaurant_id is not null then
      if exists (
        select 1 from restaurant_withdrawals
        where restaurant_id = v_restaurant_id and status in ('pendiente', 'en_proceso')
      ) then
        raise exception 'Tu restaurante tiene un retiro en proceso, espera a que se complete antes de eliminar tu cuenta.';
      end if;

      if exists (
        select 1 from orders
        where restaurant_id = v_restaurant_id and status not in ('delivered', 'cancelled')
      ) then
        raise exception 'Tu restaurante tiene pedidos activos sin terminar, espera a que se entreguen o se cancelen antes de eliminar tu cuenta.';
      end if;

      -- Anonimiza, NO borra: el restaurante, su menú y sus pedidos son
      -- también el historial de clientes y repartidores ajenos.
      update restaurants set
        phone = null,
        owner_id = null,
        approval_status = 'rechazado',
        is_open = false
      where id = v_restaurant_id;

      delete from restaurant_payout_accounts where restaurant_id = v_restaurant_id;
    end if;
  end if;
end;
$function$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated, service_role;
