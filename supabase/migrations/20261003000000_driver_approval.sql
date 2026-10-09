-- Aprobar/rechazar a un repartidor registrado por la web (tabla drivers) —
-- hasta ahora no existía NINGUNA forma de hacer esto desde ninguna app:
-- drivers.status quedaba en 'aprobado' por default sin que nadie revisara
-- los documentos, y no había ninguna policy de UPDATE para nadie (ni
-- siquiera Admin) — solo se podía cambiar a mano por SQL/service_role.
--
-- Mismo patrón que admin_transition_restaurant_status: función
-- security definer que valida is_admin() del lado del servidor, para que
-- la transición de estado no pueda falsificarse desde el cliente.

-- Campos que faltaban para guardar el motivo (admin_transition_restaurant_status
-- ya los tenía del lado de restaurants desde la migración original).
alter table drivers
  add column if not exists rejection_reason text,
  add column if not exists correction_notes text;

create or replace function admin_transition_driver_status(
  p_driver_id uuid,
  p_new_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_new_status not in ('en_revision', 'aprobado', 'requiere_correccion', 'rechazado', 'suspendido', 'desactivado') then
    raise exception 'Estado inválido: %', p_new_status;
  end if;

  if p_new_status in ('rechazado', 'requiere_correccion') and coalesce(trim(p_note), '') = '' then
    raise exception 'Se requiere un motivo';
  end if;

  if not exists (select 1 from drivers where id = p_driver_id) then
    raise exception 'Repartidor no encontrado';
  end if;

  update drivers set
    status = p_new_status,
    rejection_reason = case when p_new_status = 'rechazado' then p_note else rejection_reason end,
    correction_notes = case when p_new_status = 'requiere_correccion' then p_note else correction_notes end
  where id = p_driver_id;
end;
$$;
