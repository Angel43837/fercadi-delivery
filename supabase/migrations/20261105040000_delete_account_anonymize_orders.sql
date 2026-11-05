-- Bloque 3, punto 10 (auditoría nov 2026): borrar la cuenta nunca
-- anonimizaba orders.customer_name — ese campo guarda un JSON de texto con
-- nombre, teléfono, dirección y coordenadas de entrega (ver
-- SupabaseService.placeOrder en el celular: {name, phone, address, payment,
-- lat, lng}), completamente aparte de orders.customer_id (que sí se pone en
-- null solo con el FK ON DELETE SET NULL al borrar auth.users). El aviso de
-- privacidad promete que al borrar la cuenta "no conservamos tu nombre,
-- correo, teléfono" en el historial — pero eso nunca pasaba de verdad para
-- este campo. Ahora, al borrar, se reemplaza por un JSON anonimizado con
-- las MISMAS llaves (para no romper nada que ya lea este campo en pantallas
-- de historial/Admin), conservando solo el método de pago (no es dato
-- personal) para que el historial contable siga teniendo sentido.
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

  -- Un awaiting_payment reciente (todavía puede confirmarse en cualquier
  -- momento) sí bloquea el borrado, con un mensaje específico — distinto del
  -- genérico de abajo, para que el usuario sepa que es cosa de esperar unos
  -- minutos, no de terminar una entrega o un pedido de verdad en curso.
  if exists (
    select 1 from orders
    where customer_id = v_uid
      and status = 'awaiting_payment'
      and created_at >= now() - interval '30 minutes'
  ) then
    raise exception 'Tienes un pago en proceso, intenta en unos minutos.';
  end if;

  -- Cualquier rol: no se puede borrar con un pedido propio todavía en curso
  -- — un awaiting_payment ya viejo (>30 min, abandonado) NO cuenta aquí, se
  -- deja para que lo resuelva sweep-awaiting-payments.
  if exists (
    select 1 from orders
    where customer_id = v_uid
      and status not in ('delivered', 'cancelled')
      and not (status = 'awaiting_payment' and created_at < now() - interval '30 minutes')
  ) then
    raise exception 'Tienes un pedido en curso, espera a que se entregue o se cancele antes de eliminar tu cuenta.';
  end if;

  -- Anonimiza el historial de pedidos propios (ya todos delivered/cancelled
  -- a esta altura, por los candados de arriba) — mismas llaves que arma
  -- SupabaseService.placeOrder, solo vacías, para que nada que ya parsea
  -- este JSON (historial de Admin, order_history_screen, etc.) se rompa.
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
