-- Eliminación de cuenta (App Store / Play Store exigen un flujo real de
-- "borrar mi cuenta" dentro de la app, no solo un formulario de contacto).
--
-- Decisión de diseño: la lógica de negocio (candados + anonimización) vive
-- AQUÍ, en una función SQL `security definer` (delete_my_account()), no en
-- la Edge Function — mismo patrón que ya usa todo el resto de la app
-- (request_withdrawal, admin_transition_withdrawal,
-- admin_transition_restaurant_status, etc.): los candados de "¿tiene un
-- retiro en proceso?"/"¿tiene pedidos activos?" + la anonimización del
-- restaurante quedan en UNA sola transacción atómica — si algo falla a
-- mitad de camino, Postgres revierte todo solo, sin dejar al restaurante
-- "medio anonimizado" o la CLABE borrada pero el retiro bloqueado sin
-- revisar. La Edge Function (`supabase/functions/delete-account`) solo
-- hace de wrapper: verifica el JWT del que llama, invoca este RPC
-- (usando el JWT del propio usuario, para que auth.uid() adentro de la
-- función resuelva a la persona correcta), y SOLO si el RPC no lanzó
-- excepción, borra la fila de auth.users.
--
-- El borrado final de auth.users se hace con la Admin API de Supabase
-- (auth.admin.deleteUser) desde la Edge Function, NO con un
-- `DELETE FROM auth.users` directo en SQL — aunque técnicamente sí se
-- podría (esta misma función ya es security definer con permisos de
-- sobra), la Admin API es la vía oficialmente soportada por GoTrue: limpia
-- también auth.identities, auth.sessions, auth.refresh_tokens y factores
-- MFA de forma consistente. Un DELETE crudo depende de que TODAS esas
-- tablas tengan ON DELETE CASCADE bien puesto — no se auditó eso a fondo
-- aquí, así que la Admin API es la opción más confiable.

begin;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. FKs de *_withdrawals: de CASCADE a SET NULL.
--
-- Antes, borrar la cuenta de un rider/dueño (o, en el caso del
-- restaurante, borrar la fila de restaurants) tumbaba en cascada TODO su
-- historial de retiros — incluidos los YA COMPLETADOS, que son registros
-- contables de dinero que de verdad ya se pagó. Con SET NULL, la fila de
-- retiro sobrevive (huérfana: rider_id/restaurant_id = NULL) en vez de
-- desaparecer. Las políticas de lectura existentes
-- ("read_rider_withdrawals": rider_id = auth.uid() OR is_admin();
-- "read_own_restaurant_withdrawals": restaurant_id = <restaurant del JWT>
-- OR is_admin()) ya dejan esas filas huérfanas visibles solo para Admin
-- una vez que el id se vuelve NULL — exactamente lo que se quiere: el
-- registro contable sigue existiendo, pero ya no es "de" nadie que pueda
-- iniciar sesión.
--
-- Revisado que esto NO rompe nada que asuma rider_id/restaurant_id
-- siempre no-nulo:
--   - get_rider_balance(p_rider_id): usa COALESCE(p_rider_id, auth.uid())
--     y siempre se llama con un uuid real (el propio usuario autenticado
--     o un admin consultando a alguien específico) — nunca con NULL. Las
--     filas huérfanas simplemente no matchean "WHERE rider_id = v_rider"
--     (v_rider nunca es NULL), así que no se cuentan en el saldo de
--     nadie — correcto, ya no son saldo de una cuenta viva.
--   - admin_transition_withdrawal(p_withdrawal_id, ...): busca por su
--     propio id (PK de la tabla), nunca filtra por rider_id — no le
--     afecta en absoluto que rider_id sea NULL.
--   - request_withdrawal() / get_restaurant_balance() /
--     admin_transition_restaurant_withdrawal() / request_restaurant_withdrawal():
--     mismo razonamiento, todas filtran por el id del usuario/restaurante
--     QUE ESTÁ LLAMANDO (vivo, nunca NULL) o por el PK propio del retiro.
--   - withdrawal_status_log / restaurant_withdrawal_status_log: referencian
--     withdrawal_id (PK de *_withdrawals, que nunca se borra ni se anula
--     aquí), no rider_id/restaurant_id — no les afecta.

alter table public.rider_withdrawals
  alter column rider_id drop not null;

alter table public.rider_withdrawals
  drop constraint if exists rider_withdrawals_rider_id_fkey;

alter table public.rider_withdrawals
  add constraint rider_withdrawals_rider_id_fkey
  foreign key (rider_id) references auth.users(id) on delete set null;

alter table public.restaurant_withdrawals
  alter column restaurant_id drop not null;

alter table public.restaurant_withdrawals
  drop constraint if exists restaurant_withdrawals_restaurant_id_fkey;

alter table public.restaurant_withdrawals
  add constraint restaurant_withdrawals_restaurant_id_fkey
  foreign key (restaurant_id) references public.restaurants(id) on delete set null;

-- ──────────────────────────────────────────────────────────────────────────
-- NOTA deliberada: rider_payout_accounts.rider_id y
-- restaurant_payout_accounts.restaurant_id se QUEDAN en ON DELETE CASCADE,
-- sin cambiar — a diferencia de *_withdrawals, no se tocan por dos razones:
--   1. Son la PRIMARY KEY de su tabla (rider_payout_accounts_pkey /
--      restaurant_payout_accounts_pkey) — una PK no puede volverse NULL,
--      así que ON DELETE SET NULL ni siquiera es una opción válida ahí.
--   2. No hay nada que preservar: esa tabla solo guarda la CLABE y datos
--      de Stripe Connect para hacer el depósito, no un historial de dinero
--      ya movido (eso vive en *_withdrawals). delete_my_account() más abajo
--      borra la fila de rider_payout_accounts explícitamente como parte
--      normal del flujo — perderla a propósito está bien.
--   Para el caso de restaurant_payout_accounts: delete_my_account() NUNCA
--   borra la fila de restaurants (solo la anonimiza), así que ese CASCADE
--   ni siquiera se activa en este flujo — solo importaría si en el futuro
--   alguien usa SupabaseService.deleteRestaurant (borrado duro desde
--   Admin), que queda fuera de alcance de esta migración.

-- ──────────────────────────────────────────────────────────────────────────
-- 2. delete_my_account(): candados + anonimización, por rol.
--
-- El rol se lee de auth.jwt() -> 'app_metadata' ->> 'role' (NO de
-- is_dueno()/is_repartidor(), que a propósito también regresan true para
-- admin@fercadi.com — usarlas aquí haría que, si alguna vez Admin llamara
-- esta función sobre sí mismo, caiga en la rama de dueño/rider por error).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
  v_restaurant_id text := auth.jwt() -> 'app_metadata' ->> 'restaurant_id';
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  -- ── Repartidor (flota o independiente/"plus") ──────────────────────────
  if v_role in ('repartidor', 'repartidor_plus') then
    if exists (
      select 1 from public.rider_withdrawals
      where rider_id = v_uid and status in ('pendiente', 'en_proceso')
    ) then
      raise exception 'Tienes un retiro en proceso, espera a que se complete antes de eliminar tu cuenta.';
    end if;

    -- Sin historial que perder aquí (solo CLABE/Stripe Connect) — se borra
    -- directo. rider_withdrawals se queda intacto; su rider_id se vuelve
    -- NULL solo (ON DELETE SET NULL, de arriba) cuando el Edge Function
    -- borre la fila de auth.users al final.
    delete from public.rider_payout_accounts where rider_id = v_uid;

  -- ── Dueño de restaurante ────────────────────────────────────────────────
  elsif v_role = 'dueno' then
    if v_restaurant_id is not null then
      if exists (
        select 1 from public.restaurant_withdrawals
        where restaurant_id = v_restaurant_id and status in ('pendiente', 'en_proceso')
      ) then
        raise exception 'Tu restaurante tiene un retiro en proceso, espera a que se complete antes de eliminar tu cuenta.';
      end if;

      if exists (
        select 1 from public.orders
        where restaurant_id = v_restaurant_id and status not in ('delivered', 'cancelled')
      ) then
        raise exception 'Tu restaurante tiene pedidos activos sin terminar, espera a que se entreguen o se cancelen antes de eliminar tu cuenta.';
      end if;

      -- Anonimiza, NO borra: el restaurante, sus categorías/productos y
      -- sus pedidos no son "datos de esta cuenta" nada más — son el
      -- historial de compra de CLIENTES y repartidores ajenos, que no les
      -- corresponde perder porque el dueño decidió borrar SU cuenta.
      -- approval_status = 'rechazado' + is_open = false lo saca de
      -- read_restaurants (RLS) y de la lista del cliente sin tocar la fila.
      update public.restaurants set
        phone = null,
        owner_id = null,
        approval_status = 'rechazado',
        is_open = false
      where id = v_restaurant_id;
    end if;

  end if;

  -- ── Cliente (sin rol) ───────────────────────────────────────────────────
  -- Nada especial: orders.customer_id ya hace ON DELETE SET NULL contra
  -- auth.users, así que el historial de pedidos del restaurante/repartidor
  -- sobrevive igual, solo sin nombre de cliente asociado.
end;
$function$;

alter function public.delete_my_account() owner to postgres;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.delete_my_account() to service_role;

commit;
