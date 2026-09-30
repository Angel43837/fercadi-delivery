-- Fase 1: aprobación de restaurantes — columnas + bloqueo real de operación.
-- No incluye la UI de Admin (fase futura).
-- Aplicado a GOGO-Pruebas el 2026-08-26. Pendiente de aplicar a producción.

begin;

-- 1. Columnas de estado de aprobación en restaurants
alter table restaurants
  add column if not exists approval_status text not null default 'pendiente',
  add column if not exists submitted_at timestamptz not null default now(),
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists correction_notes text;

alter table restaurants
  drop constraint if exists restaurants_approval_status_check;
alter table restaurants
  add constraint restaurants_approval_status_check
  check (approval_status in ('pendiente', 'en_revision', 'correcciones_solicitadas', 'aprobado', 'rechazado'));

-- Los restaurantes ya operando quedan aprobados de entrada — solo lo NUEVO
-- entra pendiente. Sin esto, la fase 1 tumbaría a todos los restaurantes reales.
update restaurants
  set approval_status = 'aprobado', reviewed_at = now()
  where approval_status = 'pendiente';

-- 2. Bitácora de cambios de estado (mismo patrón que withdrawal_status_log)
create table if not exists restaurant_approval_log (
  id uuid primary key default gen_random_uuid(),
  restaurant_id text not null references restaurants(id) on delete cascade,
  previous_status text,
  new_status text not null,
  note text,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now()
);

alter table restaurant_approval_log enable row level security;

drop policy if exists "read_restaurant_approval_log" on restaurant_approval_log;
create policy "read_restaurant_approval_log" on restaurant_approval_log
  for select using (
    is_admin()
    or (is_dueno() and restaurant_id = ((auth.jwt() -> 'app_metadata') ->> 'restaurant_id'))
  );

-- 3. Protege las columnas de aprobación: solo Admin las puede tocar.
-- Un dueño puede seguir editando nombre/horario/etc. de su restaurante sin
-- que la fila entera se rechace — solo se revierten los campos de aprobación
-- si alguien que no es Admin intenta tocarlos.
create or replace function protect_restaurant_approval_fields()
returns trigger
language plpgsql
security definer
as $$
begin
  if tg_op = 'INSERT' then
    if not is_admin() then
      new.approval_status := 'pendiente';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.rejection_reason := null;
      new.correction_notes := null;
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
      new.correction_notes := old.correction_notes;
      new.submitted_at := old.submitted_at;
    end if;
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_restaurant_approval on restaurants;
create trigger trg_protect_restaurant_approval
  before insert or update on restaurants
  for each row execute function protect_restaurant_approval_fields();

-- 4. RPC admin-only para transicionar estado (mismo patrón que admin_transition_withdrawal)
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
    correction_notes = case when p_new_status = 'correcciones_solicitadas' then p_note else correction_notes end
  where id = p_restaurant_id;

  insert into restaurant_approval_log (restaurant_id, previous_status, new_status, note, changed_by)
  values (p_restaurant_id, v_old_status, p_new_status, p_note, auth.uid());
end;
$$;

-- 5. Lectura pública de restaurants: solo aprobados, salvo el propio dueño y Admin.
-- (antes era USING (true) — visibilidad total incluso de pendientes/rechazados)
drop policy if exists "read_restaurants" on restaurants;
create policy "read_restaurants" on restaurants
  for select using (
    approval_status = 'aprobado'
    or is_admin()
    or (is_dueno() and id = ((auth.jwt() -> 'app_metadata') ->> 'restaurant_id'))
  );

-- 6. Bloqueo real de operación: un restaurante no aprobado no puede recibir pedidos,
-- sin importar qué política de orders lo deje pasar (hay políticas viejas
-- permisivas ahí — un trigger no depende de cuál política ganó).
create or replace function enforce_restaurant_approved_for_orders()
returns trigger
language plpgsql
security definer
as $$
declare
  v_status text;
begin
  select approval_status into v_status from restaurants where id = new.restaurant_id;
  if v_status is distinct from 'aprobado' then
    raise exception 'Este restaurante no está aprobado para operar todavía.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_restaurant_approved on orders;
create trigger trg_enforce_restaurant_approved
  before insert on orders
  for each row execute function enforce_restaurant_approved_for_orders();

commit;
