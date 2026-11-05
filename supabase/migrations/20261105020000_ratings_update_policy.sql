-- Bloque 2, punto 5 (continuación): submitRating ahora hace upsert (ver
-- commit de supabase_service.dart) para que "Reintentar propina" pueda
-- actualizar la MISMA fila (ya con la restricción única de
-- 20261105010000) en vez de intentar insertar un duplicado. Pero
-- ratings solo tenía política de INSERT para el usuario normal
-- (insert_ratings) — la única de UPDATE era admin_update_ratings, exclusiva
-- de Admin. Sin esto, el upsert fallaría en RLS cada vez que la fila ya
-- existiera (es decir, en cualquier reintento real).
create policy "update_own_ratings" on public.ratings
  for update using (
    exists (
      select 1 from orders o
      where o.id = ratings.order_id
        and ((ratings.is_driver and o.repartidor_id = auth.uid())
          or (not ratings.is_driver and o.customer_id = auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from orders o
      where o.id = ratings.order_id
        and ((ratings.is_driver and o.repartidor_id = auth.uid())
          or (not ratings.is_driver and o.customer_id = auth.uid()))
    )
    and (tip is null or not is_driver)
  );
