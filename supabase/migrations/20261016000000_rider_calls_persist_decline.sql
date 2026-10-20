-- Bug real encontrado oct 2026: "No puedo" (rechazar una llamada a rider)
-- nunca se guardaba en el servidor a propósito — la idea original era que
-- rechazar fuera "solo local para ese repartidor" sin afectar a los demás,
-- pero el único lugar que recordaba el rechazo era _dismissedCallIds, un
-- Set en memoria dentro de repartidor_screen.dart/repartidor_plus_screen.dart.
-- Eso se perdía al cerrar la app o cerrar sesión — un repartidor que decía
-- "no puedo" y luego reabría la app (o volvía a entrar) veía la MISMA
-- llamada otra vez, como si fuera nueva.
--
-- declined_by guarda quién ya dijo que no, de forma persistente — la
-- llamada sigue "pendiente" para que otros repartidores SÍ la vean (mismo
-- comportamiento de antes), pero ya no vuelve a aparecerle a quien ya la
-- rechazó, ni siquiera en una sesión nueva.
alter table public.rider_calls add column if not exists declined_by uuid[] not null default '{}';

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
    or restaurant_id = coalesce(
      (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'),
      (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
    )
  );

create or replace function respond_rider_call(p_call_id uuid, p_accept boolean)
returns boolean
language plpgsql
security definer
as $$
declare
  v_updated int;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') not in ('repartidor', 'repartidor_plus') then
    raise exception 'No autorizado';
  end if;

  if not p_accept then
    update rider_calls
    set declined_by = array_append(declined_by, auth.uid())
    where id = p_call_id and not (auth.uid() = any(declined_by));
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
