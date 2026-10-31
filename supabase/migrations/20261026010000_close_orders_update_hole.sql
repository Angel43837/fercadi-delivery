-- Hueco de seguridad real en "orders": la política heredada del baseline
-- de agosto, "Cualquiera puede actualizar pedidos" (FOR UPDATE USING(true),
-- sin ninguna restricción), seguía viva junto a la política nueva y bien
-- acotada "update_orders" (solo admin/repartidor/dueño del restaurante). En
-- Postgres las políticas permisivas se combinan con OR, así que esta vieja
-- dejaba pasar lo que la nueva bloqueaba a propósito: CUALQUIER usuario
-- autenticado podía modificar CUALQUIER columna de CUALQUIER pedido ajeno
-- (precio, status, repartidor_id, etc.), no solo cancelar el suyo propio.
--
-- Mismo patrón de hueco ya documentado en CLAUDE.md para restaurants
-- (corregido sept 2026) — aquí nadie lo había revisado todavía para orders.
--
-- Lo único legítimo que de verdad dependía de este hueco: el cliente
-- cancelando su propio pedido desde tracking_screen.dart (antes de que el
-- restaurante lo confirme) — update_orders no incluye al cliente a
-- propósito, porque antes nunca necesitaba escribir en "orders" él mismo.
-- Se reemplaza por una función acotada en vez de abrir la política de
-- nuevo, para no regresar al mismo problema.

begin;

drop policy if exists "Cualquiera puede actualizar pedidos" on public.orders;

-- El cliente cancela SU propio pedido, y solo mientras siga 'pending' —
-- igual que promete el Aviso de Términos ("antes de que el restaurante
-- comience a prepararlo") y que ya hacía cumplir la UI de
-- tracking_screen.dart (el botón de cancelar solo se muestra en ese paso);
-- ahora también se hace cumplir del lado del servidor, no solo en la UI.
create or replace function public.cancel_my_order(p_order_id uuid)
returns void
language plpgsql
security definer
as $function$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_customer_id uuid;
begin
  if v_uid is null then
    raise exception 'no_autenticado';
  end if;

  select status, customer_id into v_status, v_customer_id
  from public.orders
  where id = p_order_id;

  if v_customer_id is null or v_customer_id <> v_uid then
    raise exception 'No puedes cancelar un pedido que no es tuyo.';
  end if;

  if v_status <> 'pending' then
    raise exception 'Tu pedido ya está siendo preparado, ya no se puede cancelar desde aquí.';
  end if;

  update public.orders set status = 'cancelled' where id = p_order_id;
end;
$function$;

alter function public.cancel_my_order(uuid) owner to postgres;

revoke all on function public.cancel_my_order(uuid) from public;
grant execute on function public.cancel_my_order(uuid) to authenticated;

commit;
