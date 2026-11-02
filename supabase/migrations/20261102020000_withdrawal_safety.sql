-- Retiros (repartidores y restaurantes) — candados contra doble pago, nov 2026.
--
-- 1. Un retiro cuya transferencia de Stripe YA salió (stripe_payout_id
--    lleno) no se puede rechazar ni cancelar. Antes, si la transferencia
--    se hacía pero fallaba marcarlo 'completado', el retiro se quedaba en
--    'en_proceso'; si Admin luego lo rechazaba, el saldo se liberaba y se
--    podía volver a retirar — doble pago con dinero real.
-- 2. Los campos stripe_* de las cuentas de cobro solo los escribe el
--    servidor (Edge Functions *-stripe-connect, con service_role). Antes el
--    propio dueño/repartidor podía poner cualquier stripe_connect_account_id
--    y marcarse stripe_onboarding_status='completed' por API directa.

create or replace function public.block_cancel_after_transfer()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.stripe_payout_id is not null
     and new.status in ('rechazado', 'cancelado')
     and old.status is distinct from new.status then
    raise exception 'ya_transferido: este retiro ya se pagó por Stripe (%), no se puede rechazar ni cancelar', old.stripe_payout_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_cancel_after_transfer on public.rider_withdrawals;
create trigger trg_block_cancel_after_transfer
  before update on public.rider_withdrawals
  for each row execute function public.block_cancel_after_transfer();

drop trigger if exists trg_block_cancel_after_transfer on public.restaurant_withdrawals;
create trigger trg_block_cancel_after_transfer
  before update on public.restaurant_withdrawals
  for each row execute function public.block_cancel_after_transfer();

create or replace function public.protect_payout_stripe_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if coalesce(auth.role(), 'service_role') = 'service_role' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.stripe_connect_account_id := null;
    new.stripe_onboarding_status := 'not_started';
  else
    new.stripe_connect_account_id := old.stripe_connect_account_id;
    new.stripe_onboarding_status := old.stripe_onboarding_status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_payout_stripe_fields on public.rider_payout_accounts;
create trigger trg_protect_payout_stripe_fields
  before insert or update on public.rider_payout_accounts
  for each row execute function public.protect_payout_stripe_fields();

drop trigger if exists trg_protect_payout_stripe_fields on public.restaurant_payout_accounts;
create trigger trg_protect_payout_stripe_fields
  before insert or update on public.restaurant_payout_accounts
  for each row execute function public.protect_payout_stripe_fields();
