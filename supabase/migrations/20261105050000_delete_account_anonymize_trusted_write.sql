-- Corrige 20261105040000: la anonimización de orders.customer_name al
-- borrar la cuenta chocaba con guard_order_changes — ese trigger solo dejar
-- pasar cambios fuera de status/repartidor_id/ubicación cuando viene de
-- place_order() (marca la transacción con gogo.trusted_order_write) o de
-- service_role/Admin. delete_my_account() corre con el JWT del propio
-- usuario (auth.role() = 'authenticated'), así que sin este mismo bypass el
-- UPDATE tronaba con "Solo se puede cambiar el estado del pedido." —
-- encontrado al probarlo en vivo, nunca llegó a producción.
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

  if exists (
    select 1 from orders
    where customer_id = v_uid
      and status = 'awaiting_payment'
      and created_at >= now() - interval '30 minutes'
  ) then
    raise exception 'Tienes un pago en proceso, intenta en unos minutos.';
  end if;

  if exists (
    select 1 from orders
    where customer_id = v_uid
      and status not in ('delivered', 'cancelled')
      and not (status = 'awaiting_payment' and created_at < now() - interval '30 minutes')
  ) then
    raise exception 'Tienes un pedido en curso, espera a que se entregue o se cancele antes de eliminar tu cuenta.';
  end if;

  perform set_config('gogo.trusted_order_write', 'on', true);
  update orders
    set customer_name = jsonb_build_object(
      'name', 'Cuenta eliminada',
      'phone', '',
      'address', '',
      'payment', (nullif(customer_name, '')::jsonb ->> 'payment'),
      'lat', null,
      'lng', null
    )::text
  where customer_id = v_uid;
  perform set_config('gogo.trusted_order_write', 'off', true);

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

  elsif v_role = 'dueno' then
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
