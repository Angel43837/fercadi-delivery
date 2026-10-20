-- "Llamar repartidor" originalmente solo avisaba a flota (decisión explícita
-- al construir la función) — el dueño pidió que también les llegue a los
-- repartidores independientes (repartidor_plus).

drop policy if exists "rider_calls_select" on public.rider_calls;
create policy "rider_calls_select" on public.rider_calls
  for select
  to authenticated
  using (
    is_admin()
    or (auth.jwt() -> 'app_metadata' ->> 'role') in ('repartidor', 'repartidor_plus')
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
