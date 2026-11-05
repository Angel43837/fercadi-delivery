-- Bloque 1, punto 1 (auditoría nov 2026): delete_my_account() cancelaba
-- directo cualquier pedido propio 'awaiting_payment', sin importar su edad.
-- Dos problemas reales:
--   1. Ese UPDATE no pasa por el bypass de guard_order_changes
--      (set_config('gogo.trusted_order_write', ...), que solo usa
--      place_order) — guard_order_changes NO tiene listada la transición
--      'awaiting_payment' -> 'cancelled' para el rol cliente (solo
--      'pending' -> 'cancelled'), así que este UPDATE podía chocar con el
--      trigger y tronar la función completa.
--   2. Aunque pasara, cancelar a ciegas un 'awaiting_payment' recién creado
--      (el banco todavía resolviendo la tarjeta) podía cancelar un pedido
--      que en realidad SÍ se iba a cobrar en los próximos segundos — el
--      webhook, al llegar después, ya no encuentra el pedido en
--      'awaiting_payment' (su propio filtro .eq('status','awaiting_payment')
--      ya no aplica) y el cobro se queda sin pedido asociado.
--
-- Ahora: un 'awaiting_payment' de MENOS de 30 min bloquea el borrado con un
-- mensaje claro (espera a que se resuelva solo). Uno de MÁS de 30 min ya se
-- considera abandonado — no bloquea el borrado, y tampoco se toca aquí: se
-- deja tal cual para que sweep-awaiting-payments (que sí corre con
-- service_role y sí consulta a Stripe antes de decidir) lo resuelva solo,
-- igual que a cualquier otro pedido abandonado de cualquier cliente.
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
