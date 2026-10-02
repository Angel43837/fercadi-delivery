-- Mensajes directos de Admin a un usuario específico (cliente o repartidor).
-- Antes no había ninguna forma de que Admin le avisara algo puntual a una
-- cuenta concreta (ej. "tu identificación salió borrosa, vuelve a
-- subirla") — lo único que existía era el chat por pedido (cliente↔rider)
-- y las alertas internas de operación (servidor/pagos/etc.), ninguno de
-- los dos sirve para esto.

create table if not exists public.admin_messages (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users (id) on delete cascade,
  sent_by      uuid references auth.users (id),
  title        text not null,
  body         text not null,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists admin_messages_recipient_idx
  on public.admin_messages (recipient_id, created_at desc);

alter table public.admin_messages enable row level security;

drop policy if exists "admin_messages_select" on public.admin_messages;
create policy "admin_messages_select" on public.admin_messages
  for select
  using (recipient_id = auth.uid() or is_admin());

drop policy if exists "admin_messages_insert" on public.admin_messages;
create policy "admin_messages_insert" on public.admin_messages
  for insert
  with check (is_admin());

-- El destinatario solo puede marcar su propio mensaje como leído — no
-- puede editar título/cuerpo ni mandarse mensajes a sí mismo.
drop policy if exists "admin_messages_mark_read" on public.admin_messages;
create policy "admin_messages_mark_read" on public.admin_messages
  for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
