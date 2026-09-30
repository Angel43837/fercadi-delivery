-- Encontrado al probar de punta a punta la separación de roles (parte de la
-- investigación del login de Riders/Restaurantes, septiembre 2026):
--
-- La tabla restaurants tenía DOS políticas de escritura al mismo tiempo:
--   insert_restaurants (INSERT, WITH CHECK is_dueno())          <- correcta
--   write_restaurants  (ALL,    WITH CHECK auth.role()='authenticated') <- hueco
--
-- Las políticas RLS permisivas se combinan con OR, no con AND — así que
-- "write_restaurants" (heredada del dump baseline del 20 de agosto, nunca
-- limpiada al agregar las políticas finas is_dueno()/is_admin()) dejaba
-- pasar el INSERT/UPDATE/DELETE de CUALQUIER usuario autenticado sin
-- importar su rol, sin importar lo que dijera insert_restaurants.
--
-- Se confirmó explotándolo: con el token de una cuenta repartidor_plus
-- recién creada, un POST a /rest/v1/restaurants insertó un restaurante
-- nuevo sin problema (HTTP 201) — un rider podía crear/editar/borrar
-- restaurantes ajenos con una simple llamada a la API, sin pasar por
-- ninguna pantalla de la app.
--
-- El mismo patrón "write_<tabla> ... auth.role()='authenticated'" existe
-- también en categories, flota_members, order_items, platform_config,
-- product_likes, products, restaurant_banners, restaurant_likes — fuera
-- del alcance de esta corrección (no se tocan aquí), pero deben revisarse
-- aparte con el mismo criterio.

DROP POLICY IF EXISTS "write_restaurants" ON "public"."restaurants";

-- Aplicado a GOGO-Pruebas el 2026-09-07 vía psql -f.
