-- Flujo de aceptación en 2 pasos: restaurante confirma primero, y SOLO
-- hasta entonces el pedido se vuelve visible/tomable para los repartidores.
-- Antes, "pending" ya era visible y tomable directo por cualquier
-- repartidor sin que el restaurante hubiera confirmado nada.
--
-- Nuevo estado intermedio: 'restaurant_accepted' (entre 'pending' y
-- 'accepted'). 'accepted' sigue significando "un repartidor lo reclamó"
-- (repartidor_id asignado) — no se toca ese significado, solo se le exige
-- que venga de 'restaurant_accepted', nunca directo de 'pending'.

-- 1. El restaurante ya puede leer/ver este estado nuevo igual que los demás.
drop policy if exists "read_orders" on orders;
create policy "read_orders" on orders for select using (
  is_admin()
  or is_repartidor()
  or (is_dueno() and restaurant_id = ((auth.jwt() -> 'app_metadata') ->> 'restaurant_id'))
  or (auth.uid() is not null and status = ANY (ARRAY['pending', 'restaurant_accepted', 'accepted', 'delivering', 'delivered', 'cancelled']))
);

-- 2. Bloqueo real (no solo en la UI): un repartidor no puede reclamar un
-- pedido que el restaurante todavía no confirmó. Un trigger no depende de
-- cuál política de RLS dejó pasar el UPDATE (hay políticas viejas muy
-- permisivas en esta tabla) — siempre se ejecuta.
create or replace function enforce_restaurant_accepted_before_rider_claim()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Reclamar = pasar de sin repartidor asignado a con uno asignado.
  if old.repartidor_id is null and new.repartidor_id is not null then
    if old.status is distinct from 'restaurant_accepted' then
      raise exception 'Este pedido todavía no ha sido confirmado por el restaurante.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_restaurant_accepted_before_claim on orders;
create trigger trg_enforce_restaurant_accepted_before_claim
  before update on orders
  for each row execute function enforce_restaurant_accepted_before_rider_claim();
