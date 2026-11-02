-- Storage, likes y calificaciones — nov 2026.
--
-- 1. Storage: los buckets product-images, profile-photos y rider-avatars
--    tenían políticas "acceso total" para el rol public — cualquiera, sin
--    sesión siquiera, podía subir, reemplazar o BORRAR cualquier imagen
--    (todas las fotos de platillos de todos los restaurantes, por ejemplo).
--    La lectura se queda pública (son buckets públicos a propósito); la
--    escritura queda solo para el dueño de cada archivo, según el nombre
--    que ya usa la app (SupabaseService.upload*):
--      profile-photos   profile_<uid>.*                    el propio usuario
--                       profile_<riderId>.*                su jefe de flota
--                       profile_restaurant_<rid>.*         dueño (logo)
--                       profile_banner_<rid>_*             dueño (banners)
--      rider-avatars    avatars/<uid>.*                    el propio rider
--      product-images   <rid con [^a-zA-Z0-9]→_>_*         dueño
--    Admin puede todo. (Antes se decía que esto solo se podía poner a mano
--    desde el dashboard — ya no: el rol postgres sí puede crear políticas
--    en storage.objects.)
-- 2. Likes: write_product_likes / write_restaurant_likes (FOR ALL a
--    cualquier autenticado) dejaban borrar o editar los likes de otros. Las
--    políticas por usuario (insert/delete con user_id = auth.uid(), de
--    20260901000000_likes_user_id_and_rls_fix.sql) ya cubren todo lo que
--    hace la app.
-- 3. Calificaciones: cualquier autenticado podía calificar cualquier
--    pedido (y poner cualquier "propina"). Ahora solo quien participó: el
--    cliente (is_driver = false) o el repartidor asignado (is_driver = true),
--    y la propina solo la registra el cliente.

create or replace function public.storage_can_write(p_bucket text, p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(is_admin(), false)
    or case p_bucket
      when 'rider-avatars' then
        starts_with(p_name, 'avatars/' || auth.uid()::text || '.')
      when 'profile-photos' then
        starts_with(p_name, 'profile_' || auth.uid()::text || '.')
        or exists (
          select 1 from flota_members fm
          where fm.jefe_id = auth.uid()
            and starts_with(p_name, 'profile_' || fm.rider_id::text || '.')
        )
        or exists (
          select 1 from restaurants r
          where owns_restaurant(r.id)
            and (starts_with(p_name, 'profile_restaurant_' || r.id || '.')
              or starts_with(p_name, 'profile_banner_' || r.id || '_'))
        )
      when 'product-images' then
        exists (
          select 1 from restaurants r
          where owns_restaurant(r.id)
            and starts_with(p_name, regexp_replace(r.id, '[^a-zA-Z0-9]', '_', 'g') || '_')
        )
      else false
    end;
$$;

revoke execute on function public.storage_can_write(text, text) from anon, public;
grant execute on function public.storage_can_write(text, text) to authenticated, service_role;

do $$
declare
  p record;
begin
  -- Solo las de escritura; las de lectura ("…_0", SELECT) se quedan.
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
      and coalesce(qual, with_check) ~ 'bucket_id = ''(product-images|profile-photos|rider-avatars)''::text'
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end;
$$;

drop policy if exists "gogo_images_insert" on storage.objects;
create policy "gogo_images_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id in ('product-images', 'profile-photos', 'rider-avatars')
    and public.storage_can_write(bucket_id, name)
  );

drop policy if exists "gogo_images_update" on storage.objects;
create policy "gogo_images_update" on storage.objects for update to authenticated
  using (
    bucket_id in ('product-images', 'profile-photos', 'rider-avatars')
    and public.storage_can_write(bucket_id, name)
  )
  with check (
    bucket_id in ('product-images', 'profile-photos', 'rider-avatars')
    and public.storage_can_write(bucket_id, name)
  );

drop policy if exists "gogo_images_delete" on storage.objects;
create policy "gogo_images_delete" on storage.objects for delete to authenticated
  using (
    bucket_id in ('product-images', 'profile-photos', 'rider-avatars')
    and public.storage_can_write(bucket_id, name)
  );

-- ── 2. Likes ────────────────────────────────────────────────────────────────
drop policy if exists "write_product_likes" on public.product_likes;
drop policy if exists "write_restaurant_likes" on public.restaurant_likes;

-- ── 3. Calificaciones ───────────────────────────────────────────────────────
drop policy if exists "insert_ratings" on public.ratings;
create policy "insert_ratings" on public.ratings for insert to authenticated
  with check (
    exists (
      select 1 from orders o
      where o.id = ratings.order_id
        and (
          (ratings.is_driver and o.repartidor_id = auth.uid())
          or (not ratings.is_driver and o.customer_id = auth.uid())
        )
    )
    and (ratings.tip is null or not ratings.is_driver)
  );
