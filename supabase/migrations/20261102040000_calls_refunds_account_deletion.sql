-- Llamadas a repartidor, reembolsos, términos y borrado de cuenta — nov 2026.
-- Huecos de las funciones agregadas en oct 2026 (rider_calls_payment,
-- order_refund_requests, legal_acceptances, account_deletion).

-- ── 1. rider_calls: solo las crea la Edge Function restaurant-call-rider ──
-- La política de INSERT dejaba a un dueño crear por API directa una
-- llamada ya "cobrado" con amount_envio = 50000 sin pagar nada; al
-- marcarla entregada, get_rider_balance la sumaba y el rider la retiraba.
-- La app nunca inserta directo (siempre por la Edge Function, que usa
-- service_role y cobra de verdad).
drop policy if exists "rider_calls_insert_dueno" on public.rider_calls;

-- ── 2. order_refund_requests: solo por request_order_refund() ──────────────
-- La política de INSERT no fijaba status/stripe_refund_id: el cliente podía
-- insertar directo una solicitud ya 'aprobado'/'procesado' y saltarse el
-- candado de "una solicitud abierta por pedido". El RPC es SECURITY
-- DEFINER, no necesita esta política; la app solo lee esta tabla.
drop policy if exists "insert_own_refund_request" on public.order_refund_requests;

-- ── 3. legal_acceptances: la fecha la pone el servidor ─────────────────────
-- Se aceptaba el accepted_at que mandara el celular — el registro no
-- servía como prueba de cuándo se aceptaron los términos.
create or replace function public.force_legal_acceptance_now()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.accepted_at := now();
  return new;
end;
$$;

drop trigger if exists trg_force_legal_acceptance_now on public.legal_acceptances;
create trigger trg_force_legal_acceptance_now
  before insert or update on public.legal_acceptances
  for each row execute function public.force_legal_acceptance_now();

-- ── 4. Llaves a auth.users sin ON DELETE ───────────────────────────────────
-- Borrar una cuenta (delete-account → auth.admin.deleteUser) tronaba para
-- cualquiera que hubiera chateado en un pedido, aceptado los términos,
-- pedido un reembolso o aceptado una llamada — y para un rider ya se
-- había borrado su CLABE antes de tronar. Se conserva el historial con el
-- usuario en NULL, igual que orders.customer_id.
alter table public.order_messages alter column sender_id drop not null;

do $$
declare
  fk record;
begin
  for fk in
    select c.conrelid::regclass as tbl, c.conname, a.attname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.confrelid = 'auth.users'::regclass
      and c.contype = 'f'
      and c.connamespace = 'public'::regnamespace
      and c.confdeltype = 'a'   -- NO ACTION
  loop
    execute format('alter table %s drop constraint %I', fk.tbl, fk.conname);
    execute format(
      'alter table %s add constraint %I foreign key (%I) references auth.users(id) on delete set null',
      fk.tbl, fk.conname, fk.attname
    );
  end loop;
end;
$$;

-- ── 5. delete_my_account: no dejar pedidos ni llamadas a medias ────────────
-- Antes un rider con un pedido en camino (o una llamada aceptada) podía
-- borrarse y el pedido pagado quedaba atorado para siempre; un cliente con
-- un pedido pagado en curso también. Y a un dueño cuyo JWT todavía no
-- traía restaurant_id no se le anonimizaba nada.
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
