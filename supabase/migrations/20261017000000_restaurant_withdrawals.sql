-- Retiros de restaurante — hasta ahora NO existía ninguna forma de que un
-- restaurante pidiera su dinero desde la app (ni CLABE, ni Stripe, nada).
-- Mismo patrón ya probado con repartidor_plus (rider_withdrawals /
-- rider_payout_accounts / get_rider_balance): balance siempre calculado en
-- vivo, nunca guardado, con un solo retiro abierto a la vez.
--
-- Nota real encontrada al construir esto: el "Ventas hoy" de
-- dueno_screen.dart usa 'total' completo (incluye delivery_fee) para
-- calcular la comisión — sobreestima lo que de verdad le toca al
-- restaurante, porque el envío es dinero del repartidor, no suyo. Aquí SÍ
-- se descuenta delivery_fee antes de aplicar la comisión, porque esta
-- función mueve dinero real — no se replica ese bug a propósito.

create table if not exists restaurant_payout_accounts (
  restaurant_id text primary key references restaurants(id) on delete cascade,
  clabe text,
  stripe_connect_account_id text,
  stripe_onboarding_status text not null default 'not_started',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists restaurant_withdrawals (
  id uuid primary key default gen_random_uuid(),
  restaurant_id text not null references restaurants(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  status text not null default 'pendiente',
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  completed_at timestamptz,
  rejection_reason text,
  transaction_reference text,
  stripe_payout_id text,
  stripe_payout_status text,
  admin_notes text,
  updated_at timestamptz not null default now()
);

create table if not exists restaurant_withdrawal_status_log (
  id uuid primary key default gen_random_uuid(),
  withdrawal_id uuid not null references restaurant_withdrawals(id) on delete cascade,
  admin_email text not null,
  action text not null,
  from_status text,
  to_status text,
  note text,
  created_at timestamptz not null default now()
);

alter table restaurant_payout_accounts enable row level security;
alter table restaurant_withdrawals enable row level security;
alter table restaurant_withdrawal_status_log enable row level security;

-- Mismo criterio que is_dueno()/read_restaurants: el restaurante del dueño
-- vive en su JWT (app_metadata.restaurant_id, sincronizado por el trigger
-- ya existente), nunca en texto que mande el cliente.
create policy "read_own_restaurant_payout_account" on restaurant_payout_accounts
  for select using (
    restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id') or is_admin()
  );
create policy "insert_own_restaurant_payout_account" on restaurant_payout_accounts
  for insert with check (restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'));
create policy "update_own_restaurant_payout_account" on restaurant_payout_accounts
  for update using (restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'))
  with check (restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'));

create policy "read_own_restaurant_withdrawals" on restaurant_withdrawals
  for select using (
    restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id') or is_admin()
  );

create policy "read_restaurant_withdrawal_status_log" on restaurant_withdrawal_status_log
  for select using (is_admin());

create or replace function get_restaurant_balance(p_restaurant_id text default null)
returns table(total_ganado numeric, total_retirado numeric, total_reservado numeric, saldo_disponible numeric)
language plpgsql
stable security definer
as $function$
declare
  v_restaurant text := coalesce(p_restaurant_id, (auth.jwt() -> 'app_metadata' ->> 'restaurant_id'));
  v_comision_pct numeric;
begin
  if v_restaurant is null then
    raise exception 'no_autenticado';
  end if;
  if v_restaurant is distinct from (auth.jwt() -> 'app_metadata' ->> 'restaurant_id')
     and not coalesce(is_admin(), false) then
    raise exception 'no_autorizado';
  end if;

  select coalesce(value::numeric, 10) into v_comision_pct
  from platform_config where key = 'comision_restaurante_pct';
  v_comision_pct := coalesce(v_comision_pct, 10);

  return query
  select ganado, retirado, reservado, ganado - retirado - reservado
  from (
    select
      coalesce((select sum(total - coalesce(delivery_fee, 0)) * (1 - v_comision_pct / 100) from orders
                 where restaurant_id = v_restaurant and status = 'delivered'), 0) as ganado,
      coalesce((select sum(amount) from restaurant_withdrawals
                 where restaurant_id = v_restaurant and status = 'completado'), 0) as retirado,
      coalesce((select sum(amount) from restaurant_withdrawals
                 where restaurant_id = v_restaurant and status in ('pendiente','en_proceso')), 0) as reservado
  ) s;
end;
$function$;

create or replace function request_restaurant_withdrawal(p_amount numeric)
returns restaurant_withdrawals
language plpgsql security definer
as $function$
declare
  v_restaurant text := (auth.jwt() -> 'app_metadata' ->> 'restaurant_id');
  v_saldo numeric;
  v_row restaurant_withdrawals;
begin
  if v_restaurant is null then
    raise exception 'no_autenticado';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'monto_invalido';
  end if;
  if p_amount < 200 then
    raise exception 'monto_minimo';
  end if;

  if exists (select 1 from restaurant_withdrawals
             where restaurant_id = v_restaurant and status in ('pendiente','en_proceso')) then
    raise exception 'retiro_en_curso';
  end if;

  select saldo_disponible into v_saldo from get_restaurant_balance(v_restaurant);
  if p_amount > v_saldo then
    raise exception 'saldo_insuficiente';
  end if;

  insert into restaurant_withdrawals (restaurant_id, amount, status)
  values (v_restaurant, p_amount, 'pendiente')
  returning * into v_row;

  return v_row;
end;
$function$;

create or replace function admin_transition_restaurant_withdrawal(
  p_withdrawal_id uuid,
  p_new_status text,
  p_rejection_reason text default null,
  p_transaction_reference text default null,
  p_admin_notes text default null
) returns restaurant_withdrawals
language plpgsql security definer
as $function$
declare
  v_row restaurant_withdrawals;
  v_prev_status text;
  v_email text := auth.jwt() ->> 'email';
begin
  if not coalesce(is_admin(), false) then
    raise exception 'no_autorizado';
  end if;

  select * into v_row from restaurant_withdrawals where id = p_withdrawal_id;
  if v_row is null then
    raise exception 'retiro_no_encontrado';
  end if;
  v_prev_status := v_row.status;

  if not (
    (v_row.status = 'pendiente' and p_new_status in ('en_proceso','rechazado','cancelado'))
    or (v_row.status = 'en_proceso' and p_new_status in ('completado','rechazado','cancelado'))
  ) then
    raise exception 'transicion_invalida';
  end if;

  update restaurant_withdrawals set
    status = p_new_status,
    processed_at = case when p_new_status = 'en_proceso' then now() else processed_at end,
    completed_at = case when p_new_status in ('completado','rechazado','cancelado') then now() else completed_at end,
    rejection_reason = coalesce(p_rejection_reason, rejection_reason),
    transaction_reference = coalesce(p_transaction_reference, transaction_reference),
    admin_notes = coalesce(p_admin_notes, admin_notes),
    updated_at = now()
  where id = p_withdrawal_id
  returning * into v_row;

  insert into restaurant_withdrawal_status_log (withdrawal_id, admin_email, action, from_status, to_status, note)
  values (
    p_withdrawal_id, v_email,
    case p_new_status when 'en_proceso' then 'approve' when 'completado' then 'complete'
                       when 'rechazado' then 'reject' else 'cancel' end,
    v_prev_status, p_new_status, p_admin_notes
  );

  return v_row;
end;
$function$;
