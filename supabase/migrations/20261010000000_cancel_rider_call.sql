-- El dueño no tenía ninguna forma de cancelar una llamada a repartidor ya
-- hecha — si nadie de flota la aceptaba, se quedaba "pendiente" para
-- siempre y la única acción posible (`respond_rider_call`) es exclusiva de
-- repartidores. Se agrega el lado simétrico: el propio restaurante que la
-- creó puede cancelarla mientras siga pendiente.

create or replace function cancel_rider_call(p_call_id uuid)
returns boolean
language plpgsql
security definer
as $$
declare
  v_restaurant_id text;
  v_updated int;
begin
  v_restaurant_id := coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'),
    (auth.jwt() -> 'user_metadata' ->> 'restaurant_id')
  );

  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'dueno' or v_restaurant_id is null then
    raise exception 'No autorizado';
  end if;

  update rider_calls set
    status = 'cancelado',
    responded_at = now()
  where id = p_call_id and restaurant_id = v_restaurant_id and status = 'pendiente';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;
