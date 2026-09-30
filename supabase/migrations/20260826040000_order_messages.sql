-- Chat interno cliente↔repartidor por pedido — reemplaza la necesidad de
-- intercambiar números telefónicos. Mismo patrón de seguridad que ya usa la
-- Edge Function order-user-lookup: solo el customer_id y el repartidor_id
-- de ESE pedido exacto pueden ver/mandar mensajes ahí.

create table if not exists order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references orders(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_messages_order_id on order_messages(order_id, created_at);

alter table order_messages enable row level security;

-- Leer historial: sin restricción de estado del pedido — un chat ya cerrado
-- se debe poder seguir consultando, solo no se pueden mandar mensajes nuevos.
drop policy if exists "read_order_messages" on order_messages;
create policy "read_order_messages" on order_messages
  for select using (
    exists (
      select 1 from orders o
      where o.id = order_messages.order_id
        and (o.customer_id = auth.uid() or o.repartidor_id = auth.uid())
    )
  );

-- Enviar: solo el propio remitente, solo si de verdad participa en el
-- pedido, solo una vez que ya hay repartidor asignado (antes de eso no hay
-- con quién chatear), y nunca si el pedido ya terminó/se canceló.
drop policy if exists "insert_order_messages" on order_messages;
create policy "insert_order_messages" on order_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from orders o
      where o.id = order_messages.order_id
        and o.repartidor_id is not null
        and o.status not in ('delivered', 'cancelled')
        and (o.customer_id = auth.uid() or o.repartidor_id = auth.uid())
    )
  );

-- Mensajes inmutables — sin políticas de UPDATE/DELETE, nadie los edita o borra.

-- Habilitar Postgres Changes (Realtime) para esta tabla — la publicación
-- supabase_realtime está vacía hoy en este proyecto (confirmado: 0 tablas),
-- así que aunque el código ya usa onPostgresChanges() en otros lados
-- (subscribeToOrders, etc.), esos canales no estaban recibiendo cambios
-- reales — el "tiempo real" de esta app hoy es polling (Timer.periodic).
-- Para el chat sí queremos Realtime de verdad, así que se agrega aquí.
alter publication supabase_realtime add table order_messages;
