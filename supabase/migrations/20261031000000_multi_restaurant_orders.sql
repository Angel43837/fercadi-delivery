-- Pedidos de hasta 2 restaurantes en un solo checkout (aprobado por el
-- dueño del negocio tras una plática de 3 preguntas, oct 2026).
--
-- Decisión de arquitectura (deliberada, para tocar lo mínimo posible del
-- resto del código): 2 restaurantes en un checkout = DOS filas normales en
-- "orders", ligadas solo por un group_id compartido. Cada fila sigue su
-- propio ciclo de vida exactamente como hoy (el dueño de cada restaurante
-- sigue viendo/aceptando/rechazando SOLO su propia fila, sin enterarse de
-- que es parte de un grupo) — no se modela como un pedido con 2
-- restaurantes adentro, eso hubiera requerido reescribir mucho más.
--
-- El costo de envío de cada pierna se calcula de forma INDEPENDIENTE (la
-- misma fórmula tarifaBase + tarifaPorKm*distancia de siempre, restaurante
-- a cliente) más un recargo fijo (multi_restaurant_surcharge) que se le
-- suma a UNA sola de las dos piernas — así cada fila de "orders" queda
-- económicamente completa y correcta por sí sola, sin depender de que la
-- otra pierna del par siga existiendo (si la rechazan después, la que ya se
-- aceptó no necesita ningún recálculo).

begin;

-- 1. group_id: nulo para un pedido normal de un solo restaurante.
alter table public.orders add column if not exists group_id uuid;
create index if not exists idx_orders_group_id on public.orders(group_id) where group_id is not null;

-- 2. Motivo de rechazo — hoy reject-order (Edge Function nueva, ver archivo
-- aparte) recibe un "reason" opcional del dueño/admin y antes no había
-- ninguna columna donde guardarlo; se descartaba en silencio.
alter table public.orders add column if not exists cancel_reason text;

-- 3. Recargo de un pedido de 2 restaurantes — mismo patrón mecánico que
-- tarifa_base/tarifa_por_km/radio_metros, leído por
-- LocationService.loadTarifas() en el celular.
insert into public.platform_config (key, value) values
  ('multi_restaurant_surcharge', '15')
on conflict (key) do nothing;

-- 4. claim_group_order: un repartidor reclama un pedido. Si no es de grupo,
-- hace exactamente lo mismo que ya hacía updateOrderStatus(id, 'accepted')
-- para un pedido solo (mismo UPDATE, mismo trigger
-- enforce_restaurant_accepted_before_rider_claim de
-- 20260928010000_two_step_order_acceptance.sql, que sigue corriendo igual
-- porque esto no es más que un UPDATE normal sobre "orders" — no se duplica
-- su lógica aquí).
--
-- Si es de grupo, reclama en una sola transacción TODAS las piernas del
-- grupo que en ese momento sigan "restaurant_accepted" y sin repartidor —
-- una pierna todavía "pending" (su restaurante no ha confirmado) o ya
-- "cancelled"/tomada por otro repartidor simplemente se excluye, no es un
-- error. Solo lanza excepción si terminó sin reclamar NINGUNA (p. ej. otro
-- repartidor se adelantó con las dos) — mismo mensaje que ya usa el flujo
-- de "Pedir un repartidor" (rider_calls) para ese caso.
create or replace function public.claim_group_order(p_order_id text)
returns text[]
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_group_id uuid;
  v_claimed text[];
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  select group_id into v_group_id from public.orders where id = p_order_id;
  if not found then
    raise exception 'Este pedido ya no existe.';
  end if;

  if v_group_id is null then
    update public.orders
      set status = 'accepted', repartidor_id = v_uid
      where id = p_order_id and status = 'restaurant_accepted' and repartidor_id is null;
    if not found then
      raise exception 'Ya se lo llevó otro repartidor.';
    end if;
    return array[p_order_id];
  end if;

  with updated as (
    update public.orders
      set status = 'accepted', repartidor_id = v_uid
      where group_id = v_group_id and status = 'restaurant_accepted' and repartidor_id is null
      returning id
  )
  select array_agg(id) into v_claimed from updated;

  if v_claimed is null or array_length(v_claimed, 1) is null then
    raise exception 'Ya se lo llevó otro repartidor.';
  end if;

  return v_claimed;
end;
$function$;

alter function public.claim_group_order(text) owner to postgres;

revoke all on function public.claim_group_order(text) from public;
grant execute on function public.claim_group_order(text) to authenticated;

commit;
