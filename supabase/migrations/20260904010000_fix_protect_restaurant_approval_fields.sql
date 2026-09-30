-- fix_protect_restaurant_approval_fields.sql
-- Corrige un bug real en el trigger `trg_protect_restaurant_approval`
-- (BEFORE INSERT OR UPDATE ON restaurants): la función referenciaba una
-- columna `correction_notes` que nunca existió en `restaurants` (quedó de
-- un diseño anterior). Como este trigger corre en TODO insert/update a
-- restaurants para quien no es admin (is_admin() = false — o sea, todo
-- dueño), cualquier intento de un dueño de guardar cambios en su
-- restaurante, o de registrar uno nuevo, tronaba con:
--   ERROR: record "new" has no field "correction_notes"
-- Solo Admin se salvaba porque su rama del if nunca toca esos campos.
-- Encontrado el 2026-09-04 al intentar reasignar la zona de un restaurante
-- por SQL directo — mismo camino que toma un dueño real.
--
-- Mismo patrón is_admin()/is_dueno() usado en el resto de las migraciones.
-- Aplicado a GOGO-Pruebas el 2026-09-04. Pendiente de aplicar a producción.

create or replace function public.protect_restaurant_approval_fields()
returns trigger
language plpgsql
security definer
as $function$
begin
  if tg_op = 'INSERT' then
    if not is_admin() then
      new.approval_status := 'pendiente';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.rejection_reason := null;
      new.submitted_at := now();
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if not is_admin() then
      new.approval_status := old.approval_status;
      new.reviewed_by := old.reviewed_by;
      new.reviewed_at := old.reviewed_at;
      new.rejection_reason := old.rejection_reason;
      new.submitted_at := old.submitted_at;
    end if;
    return new;
  end if;

  return new;
end;
$function$;
