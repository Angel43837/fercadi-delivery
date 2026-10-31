-- Reembolso real para un pedido normal (NO el de "Pedir un repartidor",
-- que ya tiene su propia lógica de reembolso aparte en rider_calls). Hoy
-- NO existe absolutamente ningún mecanismo real: legal_content.dart (y la
-- auditoría de cumplimiento de esta sesión) prometen "si hay un problema
-- con tu pedido, contáctanos para resolverlo caso por caso" sin que haya
-- nada real detrás de esa frase — ni tabla, ni RPC, ni forma de que el
-- cliente sepa si su reclamo se está atendiendo.
--
-- Mismo principio defensivo que 20261026010000 (cancel_my_order) y
-- 20261026020000 (compute_cart_subtotal/validate_promotion_for_order):
-- nunca se confía en nada que mande el cliente sobre montos/elegibilidad —
-- el RPC de abajo vuelve a leer el pedido real de la BD antes de aceptar
-- la solicitud, y la Edge Function que de verdad ejecuta el reembolso
-- (process-order-refund, archivo aparte) solo marca la solicitud como
-- "procesado" DESPUÉS de que Stripe confirma el reembolso — nunca antes
-- (mismo principio de "no completar en silencio" que ya usa
-- mark_rider_call_delivered).

begin;

create table public.order_refund_requests (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references public.orders(id),
  requested_by uuid references auth.users(id),
  reason text not null,
  status text not null default 'pendiente'
    check (status in ('pendiente', 'aprobado', 'rechazado', 'procesado')),
  admin_notes text,
  stripe_refund_id text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- NOTA sobre el estado 'aprobado': el flujo real implementado aquí es
-- síncrono (process-order-refund llama a Stripe en el mismo request que
-- Admin aprueba) — por eso pasa directo de 'pendiente' a 'procesado' en
-- cuanto Stripe confirma, sin detenerse en 'aprobado'. Se deja 'aprobado'
-- en el check constraint de todos modos (así lo pidió la auditoría) para
-- no cerrar la puerta a un futuro flujo asíncrono (ej. aprobar ahora,
-- procesar el reembolso después por lote) — hoy simplemente no se produce
-- ese estado desde ningún lado del código. request_order_refund() de
-- abajo SÍ lo trata como "solicitud todavía abierta" junto con 'pendiente'
-- para el candado de "no duplicar solicitud", por si algún día se usa.

alter table public.order_refund_requests enable row level security;

-- El cliente solo puede insertar/ver SUS propias solicitudes — y además,
-- solo sobre un pedido que de verdad sea suyo (no solo "requested_by soy
-- yo", que un cliente mal intencionado podría mandar junto con el
-- order_id de otra persona si llamara a la API REST directo en vez de
-- pasar por request_order_refund()). En la práctica la app siempre usa el
-- RPC (que ya hace esta y más validaciones: pago real confirmado, sin
-- solicitud abierta duplicada) — esta política es un respaldo, no el
-- único candado.
create policy "insert_own_refund_request" on public.order_refund_requests
  for insert with check (
    requested_by = auth.uid()
    and exists (
      select 1 from public.orders o
      where o.id = order_refund_requests.order_id and o.customer_id = auth.uid()
    )
  );

-- Lectura: el cliente ve las suyas, Admin ve todas, y el dueño del
-- restaurante del pedido las ve TAMBIÉN pero solo de lectura (no hay
-- política de UPDATE para dueño) — decisión de diseño: el dueño es quien
-- de verdad preparó/entregó el pedido y debería saber si un cliente está
-- reportando un problema con él (ej. para investigar por su lado si el
-- reclamo es legítimo), pero la decisión de aprobar/rechazar el reembolso
-- de dinero es exclusivamente de la plataforma (Admin) — el dinero del
-- pago lo cobra GOGO vía Stripe, no el restaurante directo.
create policy "select_own_refund_request" on public.order_refund_requests
  for select using (requested_by = auth.uid());

create policy "select_admin_refund_requests" on public.order_refund_requests
  for select using (is_admin());

create policy "select_restaurant_refund_requests" on public.order_refund_requests
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_refund_requests.order_id
        and o.restaurant_id = (auth.jwt() -> 'app_metadata' ->> 'restaurant_id')
    )
  );

-- Solo Admin puede actualizar (aprobar/rechazar) — en la práctica
-- process-order-refund usa la service_role key (bypassa RLS) para el
-- update real, pero se deja esta política por si algún día se necesita
-- actualizar directo desde SQL/dashboard como Admin.
create policy "update_admin_refund_requests" on public.order_refund_requests
  for update using (is_admin());

-- Solicita un reembolso para UN PEDIDO PROPIO. Vuelve a leer el pedido
-- real de la BD (nunca confía en nada que no sea el propio order_id) para
-- verificar dos cosas que SÍ importan de verdad:
--   1. Que el pedido es del que llama (customer_id = auth.uid()).
--   2. Que de verdad hay un pago con tarjeta YA CONFIRMADO que reembolsar
--      (payment_status = 'paid' Y existe un stripe_payment_intent_id) —
--      sin esto, process-order-refund no tendría ningún PaymentIntent
--      real contra el cual pedirle a Stripe que reembolse.
-- También bloquea duplicar una solicitud mientras ya haya una abierta
-- ('pendiente' o 'aprobado') para el mismo pedido.
create or replace function public.request_order_refund(p_order_id text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_payment_status text;
  v_stripe_intent text;
  v_new_id uuid;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Escribe el motivo de tu reembolso.';
  end if;

  select customer_id, payment_status, stripe_payment_intent_id
    into v_customer_id, v_payment_status, v_stripe_intent
  from public.orders
  where id = p_order_id;

  if v_customer_id is null or v_customer_id is distinct from v_uid then
    raise exception 'No puedes pedir un reembolso de un pedido que no es tuyo.';
  end if;

  if v_payment_status is distinct from 'paid' or v_stripe_intent is null then
    raise exception 'Este pedido no tiene un pago con tarjeta confirmado que se pueda reembolsar.';
  end if;

  if exists (
    select 1 from public.order_refund_requests
    where order_id = p_order_id and status in ('pendiente', 'aprobado')
  ) then
    raise exception 'Ya tienes una solicitud de reembolso abierta para este pedido.';
  end if;

  insert into public.order_refund_requests (order_id, requested_by, reason)
  values (p_order_id, v_uid, trim(p_reason))
  returning id into v_new_id;

  return v_new_id;
end;
$function$;

alter function public.request_order_refund(text, text) owner to postgres;

revoke all on function public.request_order_refund(text, text) from public;
grant execute on function public.request_order_refund(text, text) to authenticated;

commit;
