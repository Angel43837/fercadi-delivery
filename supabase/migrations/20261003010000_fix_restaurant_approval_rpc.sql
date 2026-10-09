-- Arregla 2 bugs reales encontrados al probar "Aprobar" desde Admin por
-- primera vez (nadie lo había probado desde que se construyó):
--
-- 1. correction_notes nunca se había creado de verdad en esta base de
--    datos, aunque la migración 20260826010000 la define — el RPC tronaba
--    con "column correction_notes does not exist".
-- 2. Una vez agregada la columna, el RPC seguía fallando porque intentaba
--    meterle un texto plano (p_note) a una columna de tipo array
--    (text[]) — "CASE types text[] and text cannot be matched".

alter table restaurants add column if not exists correction_notes text[] default '{}';

create or replace function admin_transition_restaurant_status(
  p_restaurant_id text,
  p_new_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_old_status text;
begin
  if not is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_new_status not in ('pendiente', 'en_revision', 'correcciones_solicitadas', 'aprobado', 'rechazado') then
    raise exception 'Estado inválido: %', p_new_status;
  end if;

  if p_new_status = 'rechazado' and coalesce(trim(p_note), '') = '' then
    raise exception 'Se requiere un motivo de rechazo';
  end if;

  if p_new_status = 'correcciones_solicitadas' and coalesce(trim(p_note), '') = '' then
    raise exception 'Se requiere especificar qué corregir';
  end if;

  select approval_status into v_old_status from restaurants where id = p_restaurant_id;
  if not found then
    raise exception 'Restaurante no encontrado';
  end if;

  update restaurants set
    approval_status = p_new_status,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    rejection_reason = case when p_new_status = 'rechazado' then p_note else rejection_reason end,
    correction_notes = case when p_new_status = 'correcciones_solicitadas' then array[p_note] else correction_notes end
  where id = p_restaurant_id;

  insert into restaurant_approval_log (restaurant_id, previous_status, new_status, note, changed_by)
  values (p_restaurant_id, v_old_status, p_new_status, p_note, auth.uid());
end;
$$;
