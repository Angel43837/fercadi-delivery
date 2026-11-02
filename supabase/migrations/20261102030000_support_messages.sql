-- Chat de soporte real, bidireccional, entre cualquier usuario (cliente,
-- dueño o repartidor — los 3 roles ya tienen el ícono de audífonos en su
-- barra superior apuntando a /soporte) y Admin. Reemplaza el placeholder
-- "muy pronto" de soporte_screen.dart.
--
-- Mismo patrón que order_messages (chat interno cliente↔repartidor por
-- pedido), pero el hilo se identifica por usuario en vez de por pedido: un
-- usuario tiene UN SOLO hilo con soporte, de por vida, sin importar cuántas
-- veces escriba. No confundir con admin_messages (20260907-ish, ver
-- CLAUDE.md "Mensajes directos de Admin a un usuario") — esa tabla es a
-- propósito de una sola vía (título+cuerpo, como un aviso), aquí se
-- necesita ida y vuelta real, así que es una tabla nueva.

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  sender text not null check (sender in ('user', 'admin')),
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

-- Un usuario normal siempre consulta/pagina su propio hilo completo
-- ordenado por fecha — este es el acceso principal.
create index idx_support_messages_user_created on public.support_messages(user_id, created_at);

alter table public.support_messages enable row level security;

-- Lectura: el usuario ve solo su propio hilo; Admin ve todos (para armar
-- la lista de hilos y abrir cualquiera).
create policy "select_own_support_messages" on public.support_messages
  for select using (user_id = auth.uid() or is_admin());

-- Enviar como usuario: solo tu propio hilo, y nunca autoasignándote
-- sender='admin' (no se confía en lo que mande el cliente sobre quién es
-- — mismo principio que insert_own_refund_request en
-- order_refund_requests.sql). Las políticas de INSERT en Postgres se unen
-- con OR, así que esta y la de abajo conviven sin pisarse.
create policy "insert_own_support_messages" on public.support_messages
  for insert with check (
    sender = 'user' and user_id = auth.uid()
  );

-- Enviar como Admin: para cualquier usuario, pero solo si de verdad es
-- Admin y solo puede firmar como 'admin' (tampoco se confía en que un
-- admin malicioso... pero sobre todo, en que nadie intente colarse como
-- admin sin serlo).
create policy "insert_admin_support_messages" on public.support_messages
  for insert with check (
    is_admin() and sender = 'admin'
  );

-- Sin políticas de UPDATE/DELETE para usuario ni Admin directo — marcar
-- como leído pasa exclusivamente por mark_support_messages_read() abajo
-- (SECURITY DEFINER, dueño postgres, igual que request_order_refund en
-- order_refund_requests.sql) para no abrir la puerta a que cualquiera
-- edite el contenido de un mensaje ya mandado.

-- Lista de hilos para el panel de Admin: un renglón por usuario, con el
-- cuerpo/fecha de su mensaje más reciente y cuántos mensajes DEL USUARIO
-- siguen sin leer por Admin (el badge de "Más → Soporte" en Admin se arma
-- sumando este conteo de todos los hilos). SECURITY DEFINER porque
-- agrupar así no es expresable con una política de RLS por fila; la
-- función misma valida que quien llama sea Admin.
create or replace function public.get_support_threads()
returns table (
  user_id uuid,
  last_body text,
  last_sender text,
  last_created_at timestamptz,
  unread_count bigint
)
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not is_admin() then
    raise exception 'No autorizado';
  end if;

  -- DISTINCT ON exige que el ORDER BY empiece por la(s) columna(s) del
  -- DISTINCT ON (user_id) — eso deja el resultado ordenado por user_id, NO
  -- por fecha. Se resuelve en dos pasos: primero se saca un renglón por
  -- usuario (el más reciente), y HASTA AFUERA se reordena por fecha real.
  return query
    select t.user_id, t.body, t.sender, t.created_at, t.unread_count
    from (
      select distinct on (sm.user_id)
        sm.user_id,
        sm.body,
        sm.sender,
        sm.created_at,
        (
          select count(*) from public.support_messages u
          where u.user_id = sm.user_id and u.sender = 'user' and u.read_at is null
        ) as unread_count
      from public.support_messages sm
      order by sm.user_id, sm.created_at desc
    ) t
    order by t.created_at desc;
end;
$function$;

alter function public.get_support_threads() owner to postgres;

revoke all on function public.get_support_threads() from public;
grant execute on function public.get_support_threads() to authenticated;

-- Marca mensajes como leídos. Sirve a los dos lados del chat con una sola
-- función (así se evita duplicar la lógica de "quién puede marcar qué
-- como leído"):
--   - Si quien llama es Admin: marca como leídos los mensajes que ESE
--     usuario (p_user_id) mandó y Admin no había visto — se llama al
--     abrir su hilo desde admin_soporte_screen.dart, y es lo que hace
--     bajar el badge de "Más → Soporte".
--   - Si quien llama es el propio usuario (p_user_id = auth.uid()): marca
--     como leídas las respuestas de Admin que no había visto — se llama
--     al abrir soporte_screen.dart. Esto no afecta ningún badge hoy (no
--     hay contador de "respuestas sin leer" en la UI del usuario todavía),
--     pero deja el campo read_at consistente para los dos lados por si se
--     necesita más adelante.
create or replace function public.mark_support_messages_read(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if is_admin() then
    update public.support_messages
      set read_at = now()
      where user_id = p_user_id and sender = 'user' and read_at is null;
  elsif auth.uid() = p_user_id then
    update public.support_messages
      set read_at = now()
      where user_id = p_user_id and sender = 'admin' and read_at is null;
  else
    raise exception 'No autorizado';
  end if;
end;
$function$;

alter function public.mark_support_messages_read(uuid) owner to postgres;

revoke all on function public.mark_support_messages_read(uuid) from public;
grant execute on function public.mark_support_messages_read(uuid) to authenticated;

-- Realtime: igual que order_messages, se agrega explícitamente a la
-- publicación (supabase_realtime viene vacía en este proyecto — confirmado
-- al construir el chat de pedido — así que sin esta línea el canal de
-- Postgres Changes no recibe nada).
alter publication supabase_realtime add table support_messages;

-- Futuro gancho para un auto-respondedor con IA (NO implementado en esta
-- migración, solo se documenta dónde engancharía): se podría crear un
-- Database Webhook en Supabase sobre "INSERT on support_messages where
-- sender = 'user'" que llame a una Edge Function nueva, la cual consulte
-- una API de LLM (Gemini, GPT, etc.) con el historial del hilo y luego
-- inserte la respuesta de vuelta en esta misma tabla — como sender='admin'
-- si se quiere que se vea igual que una respuesta humana, o agregando un
-- valor nuevo 'ai' al check de sender (y su propia política de insert,
-- ej. solo vía service_role) si se quiere distinguir en la UI que contestó
-- el bot y no una persona. Ninguna de las dos cosas existe todavía.
