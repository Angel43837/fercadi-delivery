-- Dos cosas en una migración, relacionadas — encontradas al revisar estas
-- tablas para que el login por teléfono funcione bien con los likes:
--
-- 1) Bug de seguridad REAL: existe una política "Allow all" USING(true)
--    WITH CHECK(true), sin FOR ni TO, en product_likes y restaurant_likes
--    (ver 20260820000000_baseline_schema.sql:741,745), más GRANT ALL a la
--    anon key (líneas 1131,1161 del mismo archivo). Al ser una política
--    permisiva sin restricción, Postgres la combina con OR junto a
--    insert_/delete_product_likes/restaurant_likes — y como "Allow all"
--    siempre es true, esas políticas más estrictas nunca se llegaban a
--    evaluar de verdad: CUALQUIERA con la anon key, sin sesión siquiera,
--    podía insertar o borrar likes de cualquier usuario. Se elimina esa
--    política.
--
-- 2) Cuentas de solo-teléfono no tienen email → auth.jwt()->>'email' es NULL
--    y nunca coincide con nada, así que el chequeo de user_email por sí
--    solo no les serviría una vez quitada "Allow all". Se agrega una
--    columna user_id (nullable, no se toca la llave primaria compuesta
--    existente) y las políticas de escritura ahora exigen
--    auth.uid() = user_id. El lado Dart sigue mandando un user_email de
--    relleno único ('phone:+52...' o 'uid:...' si no hay email) para
--    satisfacer la columna NOT NULL/PK existente sin tocarla, pero ya no se
--    lee para nada — user_id es la fuente de verdad desde ahora.

alter table public.product_likes
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.restaurant_likes
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

update public.product_likes p set user_id = u.id
  from auth.users u where u.email = p.user_email and p.user_id is null;
update public.restaurant_likes r set user_id = u.id
  from auth.users u where u.email = r.user_email and r.user_id is null;

create index if not exists idx_product_likes_user_id on public.product_likes(user_id);
create index if not exists idx_restaurant_likes_user_id on public.restaurant_likes(user_id);

drop policy if exists "Allow all" on public.product_likes;
drop policy if exists "Allow all" on public.restaurant_likes;

drop policy if exists "insert_product_likes" on public.product_likes;
create policy "insert_product_likes" on public.product_likes
  for insert with check (auth.uid() is not null and user_id = auth.uid());

drop policy if exists "delete_product_likes" on public.product_likes;
create policy "delete_product_likes" on public.product_likes
  for delete using (user_id = auth.uid());

drop policy if exists "insert_restaurant_likes" on public.restaurant_likes;
create policy "insert_restaurant_likes" on public.restaurant_likes
  for insert with check (auth.uid() is not null and user_id = auth.uid());

drop policy if exists "delete_restaurant_likes" on public.restaurant_likes;
create policy "delete_restaurant_likes" on public.restaurant_likes
  for delete using (user_id = auth.uid());

-- read_product_likes/read_restaurant_likes (USING(true), lectura pública de
-- conteos) y write_product_likes/write_restaurant_likes (solo UPDATE, que
-- la app nunca usa en estas tablas) se dejan igual — no hacía falta tocarlas.
