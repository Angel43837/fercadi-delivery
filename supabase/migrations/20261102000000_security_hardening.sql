-- Auditoría de seguridad nov 2026 — cierra los huecos de RLS que dejaban a
-- cualquier usuario (o incluso anónimo) leer/editar pedidos ajenos,
-- apoderarse de un restaurante ajeno o inflarse estadísticas.
--
-- Resumen de lo que cambia:
--   1. orders / order_items: se borran las políticas viejas del baseline que
--      daban acceso total a cualquier autenticado (y lectura a anon). Cada
--      rol ve/edita solo lo suyo, y un trigger valida qué columnas y qué
--      transiciones de estado puede hacer cada quien (además arregla la
--      carrera de dos repartidores aceptando el mismo pedido).
--   2. sync_role_to_app_metadata: ya no copia cualquier role/restaurant_id
--      que el usuario se ponga en user_metadata — solo roles de
--      autoregistro, y restaurant_id solo si de verdad es el dueño
--      (restaurants.owner_id).
--   3. restaurants / products / categories / restaurant_banners: un dueño
--      solo escribe en SU restaurante (antes: en cualquiera).
--   4. flota_members: un jefe de flota solo maneja su propia flota.
--   5. rider_stats: se suman en el servidor al entregar el pedido; el RPC
--      increment_rider_stats queda solo para admin y la tabla en solo
--      lectura para el repartidor.
--   6. restaurant_withdrawals: un solo retiro abierto por restaurante
--      (mismo candado que ya tenían los riders).
--   7. rider_calls: ya no se lee restaurant_id de user_metadata.
--   8. Todas las funciones SECURITY DEFINER de public quedan con search_path
--      fijo.
--
-- Los bypass de admin (is_admin()) y del servidor (service_role: webhook de
-- Stripe, Edge Functions) se mantienen.

-- ── 0. Helper: ¿el usuario actual es dueño de este restaurante? ──────────────
-- SECURITY DEFINER para poder consultar restaurants sin pasar por su RLS
-- (y sin recursión cuando se usa dentro de las políticas de restaurants).
-- owner_id cubre el hueco de recién registrado: el JWT todavía no trae
-- restaurant_id hasta refrescar la sesión.
create or replace function public.owns_restaurant(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select is_admin()
      or (
        is_dueno()
        and p_restaurant_id is not null
        and (
          p_restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id')
          or exists (
            select 1 from restaurants r
            where r.id = p_restaurant_id and r.owner_id = auth.uid()
          )
        )
      );
$$;

revoke execute on function public.owns_restaurant(text) from anon, public;
grant execute on function public.owns_restaurant(text) to authenticated, service_role;

-- ── 1. orders ────────────────────────────────────────────────────────────────
drop policy if exists "Cualquiera puede actualizar pedidos" on public.orders;
drop policy if exists "Cualquiera puede insertar pedidos" on public.orders;
drop policy if exists "Cualquiera puede leer pedidos" on public.orders;
drop policy if exists "orders_auth" on public.orders;
drop policy if exists "orders_select_anon" on public.orders;

-- Repartidores: solo los disponibles (restaurante ya confirmó, sin rider) y
-- los suyos. Jefe de flota: los de sus riders. Cliente: los suyos.
drop policy if exists "read_orders" on public.orders;
create policy "read_orders" on public.orders for select to authenticated using (
  is_admin()
  or customer_id = auth.uid()
  or owns_restaurant(restaurant_id)
  or (
    is_repartidor()
    and (
      repartidor_id = auth.uid()
      or (repartidor_id is null and status = 'restaurant_accepted')
    )
  )
  or (
    is_jefe_flota()
    and repartidor_id in (
      select fm.rider_id from flota_members fm where fm.jefe_id = auth.uid()
    )
  )
);

-- Los clientes crean pedidos solo con place_order() (siguiente migración),
-- que calcula precios y totales en el servidor.
drop policy if exists "insert_orders" on public.orders;
create policy "insert_orders" on public.orders for insert to authenticated
  with check (is_admin());

-- Sin WITH CHECK explícito: Postgres aplica este mismo USING a la fila nueva,
-- así que un repartidor solo puede dejar el pedido asignado a sí mismo o
-- liberado (sin repartidor) — nunca a otro.
drop policy if exists "update_orders" on public.orders;
create policy "update_orders" on public.orders for update to authenticated using (
  is_admin()
  or customer_id = auth.uid()
  or owns_restaurant(restaurant_id)
  or (
    is_repartidor()
    and (
      repartidor_id = auth.uid()
      or (repartidor_id is null and status = 'restaurant_accepted')
    )
  )
);

-- RLS decide QUÉ filas; este trigger decide QUÉ cambios. Fuera de admin y
-- servidor, en un pedido ya creado solo se puede mover status,
-- repartidor_id y la ubicación del rider — total, envío, payment_status,
-- etc. quedan congelados desde el insert.
create or replace function public.guard_order_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_free text[] := array['status', 'repartidor_id', 'current_lat', 'current_lng'];
begin
  -- Servidor (service_role / SQL directo, sin JWT), admin, y place_order()
  -- (marca la transacción con gogo.trusted_order_write): sin restricciones.
  if coalesce(auth.role(), 'service_role') = 'service_role'
     or is_admin()
     or current_setting('gogo.trusted_order_write', true) = 'on' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    raise exception 'Los pedidos se crean con place_order().';
  end if;

  if (to_jsonb(old) - v_free) is distinct from (to_jsonb(new) - v_free) then
    raise exception 'Solo se puede cambiar el estado del pedido.';
  end if;

  if (new.current_lat is distinct from old.current_lat
      or new.current_lng is distinct from old.current_lng)
     and new.repartidor_id is distinct from v_uid then
    raise exception 'Solo el repartidor asignado puede actualizar la ubicación.';
  end if;

  if new.status is not distinct from old.status
     and new.repartidor_id is not distinct from old.repartidor_id then
    return new;
  end if;

  if is_repartidor() then
    -- Tomar: solo si nadie lo tiene todavía (evita que un segundo rider le
    -- quite el pedido al primero con una lista desactualizada).
    if old.status = 'restaurant_accepted' and old.repartidor_id is null
       and new.status = 'accepted' and new.repartidor_id = v_uid then
      return new;
    end if;
    -- Avanzar su propio pedido, un paso a la vez.
    if old.repartidor_id = v_uid and new.repartidor_id = v_uid
       and ((old.status = 'accepted' and new.status = 'delivering')
         or (old.status = 'delivering' and new.status = 'delivered')) then
      return new;
    end if;
    -- Soltar su pedido (vuelve a quedar disponible). 'pending' se acepta
    -- solo por compatibilidad con builds viejos de la app.
    if old.repartidor_id = v_uid and old.status in ('accepted', 'delivering')
       and new.repartidor_id is null
       and new.status in ('restaurant_accepted', 'pending') then
      return new;
    end if;
  end if;

  -- Un pedido ya pagado con tarjeta solo se cancela por la Edge Function
  -- create-payment-intent (action 'cancel'), que además hace el reembolso.
  if new.status = 'cancelled' and old.payment_status = 'paid' then
    raise exception 'Este pedido ya está pagado: cancélalo desde la app para reembolsar.';
  end if;

  if owns_restaurant(old.restaurant_id)
     and new.repartidor_id is not distinct from old.repartidor_id then
    if old.status = 'pending' and new.status = 'restaurant_accepted' then
      return new;
    end if;
    if old.status not in ('delivered', 'cancelled', 'awaiting_payment') and new.status = 'cancelled' then
      return new;
    end if;
  end if;

  -- Cliente: cancelar mientras el restaurante no lo haya confirmado.
  if old.customer_id = v_uid and old.status = 'pending'
     and new.status = 'cancelled'
     and new.repartidor_id is not distinct from old.repartidor_id then
    return new;
  end if;

  raise exception 'Cambio de estado no permitido (% → %).', old.status, new.status;
end;
$$;

drop trigger if exists trg_guard_order_changes on public.orders;
create trigger trg_guard_order_changes
  before insert or update on public.orders
  for each row execute function public.guard_order_changes();

-- ── 2. order_items ───────────────────────────────────────────────────────────
drop policy if exists "Cualquiera puede insertar order_items" on public.order_items;
drop policy if exists "Cualquiera puede leer order_items" on public.order_items;
drop policy if exists "order_items_auth" on public.order_items;
drop policy if exists "order_items_select_anon" on public.order_items;

-- Visible si el pedido es visible (la subconsulta pasa por el RLS de orders).
drop policy if exists "read_order_items" on public.order_items;
create policy "read_order_items" on public.order_items for select to authenticated using (
  exists (select 1 from orders o where o.id = order_items.order_id)
);

-- Igual que orders: los platillos los inserta place_order() con el precio
-- de products, nunca el celular.
drop policy if exists "insert_order_items" on public.order_items;
create policy "insert_order_items" on public.order_items for insert to authenticated
  with check (is_admin());
-- "write_order_items" (UPDATE solo admin) se queda igual.

-- ── 3. Sincronización user_metadata → app_metadata ──────────────────────────
-- Antes copiaba cualquier role (incluido jefe_flota) y cualquier
-- restaurant_id — un cliente podía ponerse el restaurant_id de otro y
-- quedarse con sus pedidos y su saldo. El trigger sobre auth.users sigue
-- apuntando a esta función; solo cambia el cuerpo.
create or replace function public.sync_role_to_app_metadata()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := new.raw_user_meta_data ->> 'role';
  v_restaurant_id text := new.raw_user_meta_data ->> 'restaurant_id';
begin
  -- Solo roles de autoregistro. admin/jefe_flota se asignan desde el
  -- servidor directo en app_metadata.
  if v_role in ('cliente', 'dueno', 'repartidor', 'repartidor_plus')
     and coalesce(new.raw_app_meta_data ->> 'role', '') = '' then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('role', v_role);
  end if;

  if v_restaurant_id is not null
     and new.raw_app_meta_data ->> 'restaurant_id' is null
     and exists (
       select 1 from restaurants r
       where r.id = v_restaurant_id and r.owner_id = new.id
     ) then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('restaurant_id', v_restaurant_id);
  end if;

  return new;
end;
$$;

revoke execute on function public.sync_role_to_app_metadata() from anon, authenticated, public;

-- Para revisar a mano si alguien ya se aprovechó del hueco (no cambia nada):
--   select u.id, u.email, u.raw_app_meta_data ->> 'restaurant_id' as rid
--   from auth.users u
--   join restaurants r on r.id = u.raw_app_meta_data ->> 'restaurant_id'
--   where r.owner_id is distinct from u.id;

-- ── 4. Restaurantes y su catálogo: solo el dueño de ESE restaurante ────────
drop policy if exists "update_restaurants" on public.restaurants;
create policy "update_restaurants" on public.restaurants for update
  using (owns_restaurant(id)) with check (owns_restaurant(id));

drop policy if exists "write_products" on public.products;
create policy "write_products" on public.products
  using (owns_restaurant(restaurant_id)) with check (owns_restaurant(restaurant_id));

drop policy if exists "write_categories" on public.categories;
create policy "write_categories" on public.categories
  using (owns_restaurant(restaurant_id)) with check (owns_restaurant(restaurant_id));

drop policy if exists "write_restaurant_banners" on public.restaurant_banners;
create policy "write_restaurant_banners" on public.restaurant_banners
  using (owns_restaurant(restaurant_id)) with check (owns_restaurant(restaurant_id));

-- ── 5. flota_members: cada jefe solo su flota ───────────────────────────────
drop policy if exists "write_flota_members" on public.flota_members;
create policy "write_flota_members" on public.flota_members
  using (is_admin() or (is_jefe_flota() and jefe_id = auth.uid()))
  with check (is_admin() or (is_jefe_flota() and jefe_id = auth.uid()));

-- ── 6. rider_stats: se calculan en el servidor ──────────────────────────────
-- Antes la app llamaba increment_rider_stats con los montos que quisiera
-- (y anon también podía). Ahora se suman una sola vez, cuando el pedido
-- pasa a 'delivered' — mismos valores que mandaba la app (100 coins, 1
-- reparto, total del pedido). Un pedido de 2 restaurantes es un solo
-- viaje: coins y reparto solo con la primera pierna entregada; el dinero
-- sí suma las dos (= total combinado, como hacía la app).
create or replace function public.add_rider_stats_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_first_leg boolean;
begin
  if new.status = 'delivered'
     and old.status is distinct from 'delivered'
     and new.repartidor_id is not null then
    v_first_leg := new.group_id is null or not exists (
      select 1 from orders
      where group_id = new.group_id and id <> new.id and status = 'delivered'
    );
    insert into rider_stats (rider_id, coins, repartos, dinero, updated_at)
    values (
      new.repartidor_id,
      case when v_first_leg then 100 else 0 end,
      case when v_first_leg then 1 else 0 end,
      coalesce(new.total, 0),
      now()
    )
    on conflict (rider_id) do update set
      coins      = rider_stats.coins    + excluded.coins,
      repartos   = rider_stats.repartos + excluded.repartos,
      dinero     = rider_stats.dinero   + excluded.dinero,
      updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_add_rider_stats_on_delivery on public.orders;
create trigger trg_add_rider_stats_on_delivery
  after update of status on public.orders
  for each row execute function public.add_rider_stats_on_delivery();

create or replace function public.increment_rider_stats(
  p_rider_id uuid,
  p_coins_add integer default 0,
  p_repartos_add integer default 0,
  p_dinero_add numeric default 0
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not is_admin() then
    raise exception 'No autorizado';
  end if;
  insert into rider_stats (rider_id, coins, repartos, dinero, updated_at)
  values (p_rider_id, p_coins_add, p_repartos_add, p_dinero_add, now())
  on conflict (rider_id) do update set
    coins      = rider_stats.coins    + excluded.coins,
    repartos   = rider_stats.repartos + excluded.repartos,
    dinero     = rider_stats.dinero   + excluded.dinero,
    updated_at = now();
end;
$$;

revoke execute on function public.increment_rider_stats(uuid, integer, integer, numeric) from anon, public;

drop policy if exists "rider_stats_own" on public.rider_stats;
create policy "rider_stats_own" on public.rider_stats for select
  using (rider_id = auth.uid() or is_admin());

-- ── 7. Un solo retiro abierto por restaurante ───────────────────────────────
-- request_restaurant_withdrawal revisa "no hay otro abierto" y luego
-- inserta, sin candado — dos solicitudes simultáneas pasaban las dos.
-- Si esto falla al aplicar, ya existen duplicados abiertos: hay que
-- resolverlos (rechazar uno) antes de reintentar.
create unique index if not exists restaurant_withdrawals_one_open
  on public.restaurant_withdrawals (restaurant_id)
  where status in ('pendiente', 'en_proceso');

-- ── 8. rider_calls sin user_metadata ────────────────────────────────────────
drop policy if exists "rider_calls_insert_dueno" on public.rider_calls;
create policy "rider_calls_insert_dueno" on public.rider_calls
  for insert
  to authenticated
  with check (is_dueno() and owns_restaurant(restaurant_id));

drop policy if exists "rider_calls_select" on public.rider_calls;
create policy "rider_calls_select" on public.rider_calls
  for select
  to authenticated
  using (
    is_admin()
    or (
      (auth.jwt() -> 'app_metadata' ->> 'role') in ('repartidor', 'repartidor_plus')
      and not (auth.uid() = any(declined_by))
    )
    or accepted_by = auth.uid()
    or owns_restaurant(restaurant_id)
  );

create or replace function public.cancel_rider_call(p_call_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_restaurant_id text;
  v_updated int;
begin
  select restaurant_id into v_restaurant_id from rider_calls where id = p_call_id;

  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'dueno'
     or not owns_restaurant(v_restaurant_id) then
    raise exception 'No autorizado';
  end if;

  update rider_calls set
    status = 'cancelado',
    responded_at = now()
  where id = p_call_id and status = 'pendiente';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- Mismo hueco en mark_rider_call_delivered (20261024000000_rider_calls_payment.sql).
create or replace function public.mark_rider_call_delivered(p_call_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
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

  if auth.uid() is distinct from v_accepted_by and not owns_restaurant(v_restaurant_id) then
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

-- cancel_my_order(uuid) nunca funcionó (los ids de pedido son texto, no
-- uuid) y no reembolsaba. El cliente ahora cancela por la Edge Function
-- reject-order, que sí reembolsa.
drop function if exists public.cancel_my_order(uuid);

-- ── 9. search_path fijo en todas las SECURITY DEFINER de public ─────────────
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'
      )
  loop
    execute format('alter function %s set search_path = public, extensions, pg_temp', f.sig);
  end loop;
end;
$$;
