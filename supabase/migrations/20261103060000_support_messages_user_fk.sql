-- Bloque 0 (auditoría del chat de soporte): support_messages.user_id
-- se creó con su FK a auth.users en NO ACTION (el default de Postgres
-- cuando no se pone nada) — la única tabla de todo el proyecto con ese
-- hueco (verificado contra pg_constraint: todas las demás que referencian
-- auth.users usan CASCADE o SET NULL a propósito). Mismo bug ya conocido
-- y corregido para otras tablas en 20261026000000_account_deletion.sql
-- ("Llaves a auth.users sin ON DELETE → SET NULL"), pero support_messages
-- se creó DESPUÉS (nov 2026) y no heredó esa corrección.
--
-- Efecto real, confirmado en vivo con dos usuarios de prueba: cualquier
-- cuenta que alguna vez haya escrito a soporte queda IMPOSIBLE de borrar
-- — delete_my_account() pasa bien (no tiene candado para esto), pero el
-- borrado real de auth.users con la Admin API de GoTrue (delete-account
-- Edge Function) truena con "Database error deleting user" porque la fila
-- sigue teniendo mensajes de soporte apuntándola con NO ACTION.
--
-- Se deja el mismo criterio que order_messages.sender_id (el chat de
-- pedido, el caso más parecido): el hilo de soporte sobrevive para que
-- Admin conserve el historial, solo se desvincula del usuario borrado.
alter table public.support_messages alter column user_id drop not null;

alter table public.support_messages
  drop constraint support_messages_user_id_fkey,
  add constraint support_messages_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete set null;

-- get_support_threads() agrupa con DISTINCT ON (user_id) — si varias
-- cuentas YA BORRADAS dejaran mensajes con user_id = null, Postgres las
-- trataría como un solo grupo (DISTINCT ON no distingue entre nulls) y
-- Admin vería un "hilo" mezclando mensajes de gente distinta bajo un
-- mismo renglón. No hay ninguna acción útil que Admin pueda tomar sobre
-- el hilo de una cuenta que ya no existe (no hay a quién contestarle), así
-- que mejor se excluyen de la lista en vez de arriesgar esa mezcla.
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
      where sm.user_id is not null
      order by sm.user_id, sm.created_at desc
    ) t
    order by t.created_at desc;
end;
$function$;
