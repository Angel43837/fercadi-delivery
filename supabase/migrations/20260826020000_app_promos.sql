-- Promos de la propia app GOGO (no de un restaurante) — imágenes tipo cupón
-- que se muestran en la pestaña "Promos" de restaurants_screen.dart.
-- Mismo patrón de RLS que restaurant_banners/platform_config: lectura pública,
-- escritura solo Admin (esto es contenido de GOGO, no de los dueños).
-- Aplicado a GOGO-Pruebas el 2026-08-26. Pendiente de aplicar a producción.
-- Nota: hoy no hay UI de administración para esta tabla — se llena a mano
-- por SQL directo (igual que las categorías de menú). Las filas de prueba
-- insertadas en Pruebas (cupones de ejemplo) NO deben replicarse a producción,
-- solo la estructura de la tabla.

create table if not exists app_promos (
  id uuid primary key default gen_random_uuid(),
  image_url text not null,
  title text default '',
  subtitle text default '',
  badge text default '',
  badge_color_hex text default '#E53935',
  sort_order integer default 0,
  is_active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table app_promos enable row level security;

drop policy if exists "read_app_promos" on app_promos;
create policy "read_app_promos" on app_promos for select using (true);

drop policy if exists "write_app_promos" on app_promos;
create policy "write_app_promos" on app_promos using (is_admin()) with check (is_admin());
