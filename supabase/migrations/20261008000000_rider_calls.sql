-- Botón "llamar repartidor" en la app de escritorio (gogo-pedidos-escritorio)
-- — el dueño necesita poder avisar a los repartidores de flota en línea que
-- hay un pedido para recoger (normalmente de WhatsApp, fuera del flujo
-- normal de la app), sin tener que asignarlo a uno en específico. El
-- primero en aceptar se lo queda; a los demás ya no les aparece.

create table if not exists public.rider_calls (
  id              uuid primary key default gen_random_uuid(),
  restaurant_id   text references public.restaurants (id),
  restaurant_name text,
  status          text not null default 'pendiente'
                  check (status in ('pendiente', 'aceptado', 'rechazado', 'cancelado')),
  accepted_by     uuid references auth.users (id),
  created_at      timestamptz not null default now(),
  responded_at    timestamptz
);

create index if not exists rider_calls_status_idx on public.rider_calls (status, created_at desc);

alter table public.rider_calls enable row level security;

-- El dueño solo puede crear llamadas para su propio restaurante.
drop policy if exists "rider_calls_insert_dueno" on public.rider_calls;
create policy "rider_calls_insert_dueno" on public.rider_calls
  for insert
  to authenticated
  with check (
    is_dueno()
    and restaurant_id = coalesce(
      (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'),
      (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
    )
  );

-- Repartidores de FLOTA ven las llamadas pendientes (para poder aceptarlas)
-- y, una vez respondida, siguen viendo la suya propia o cualquiera ya
-- resuelta (para que no desaparezca de golpe de su pantalla). El dueño ve
-- las de su propio restaurante para saber si ya se la tomaron. Admin ve todo.
drop policy if exists "rider_calls_select" on public.rider_calls;
create policy "rider_calls_select" on public.rider_calls
  for select
  to authenticated
  using (
    is_admin()
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'repartidor'
    or accepted_by = auth.uid()
    or restaurant_id = coalesce(
      (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'),
      (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
    )
  );

-- Nadie actualiza la fila directo — solo por el RPC de abajo (evita que dos
-- repartidores se peleen la misma llamada con un UPDATE normal desde el
-- cliente, sin validación atómica del estado).
drop policy if exists "rider_calls_no_direct_update" on public.rider_calls;

-- Aceptar/rechazar una llamada — security definer para que la condición
-- "solo si sigue pendiente" se valide del lado del servidor: si dos
-- repartidores le pican a Aceptar casi al mismo tiempo, el UPDATE con
-- "where status = 'pendiente'" solo afecta una fila la primera vez: el
-- segundo RPC llega y ya no encuentra nada que actualizar.
create or replace function respond_rider_call(p_call_id uuid, p_accept boolean)
returns boolean
language plpgsql
security definer
as $$
declare
  v_updated int;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'repartidor' then
    raise exception 'No autorizado';
  end if;

  if not p_accept then
    -- Rechazar es solo local para ese repartidor (no afecta a los demás,
    -- que siguen viendo la llamada pendiente) — no se escribe nada aquí.
    return true;
  end if;

  update rider_calls set
    status = 'aceptado',
    accepted_by = auth.uid(),
    responded_at = now()
  where id = p_call_id and status = 'pendiente';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;
