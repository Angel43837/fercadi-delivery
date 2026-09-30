-- Encontrado al probar de punta a punta el registro de un restaurante nuevo
-- (parte de la investigación del login de Riders/Restaurantes, sept 2026):
--
-- La política read_restaurants dejaba a un dueño SIN PODER VER su propio
-- restaurante recién creado:
--   (approval_status = 'aprobado') OR is_admin()
--   OR (is_dueno() AND id = auth.jwt()->app_metadata->>'restaurant_id')
--
-- Un restaurante nuevo nace con approval_status='pendiente' (no aprobado
-- todavía), y restaurant_id solo se guarda en app_metadata DESPUÉS de que
-- el INSERT ya devolvió el id del restaurante — un huevo y la gallina: para
-- ver la fila hace falta el restaurant_id en el JWT, pero para conseguir
-- ese id hay que poder ver la fila primero (el INSERT normalmente se hace
-- con .select() para recuperar el id recién creado).
--
-- Se confirmó explotando el flujo real por la API REST: insertar un
-- restaurante con Prefer: return=representation (lo que hace justo
-- Supabase.from('restaurants').insert({...}).select().single() en Dart)
-- fallaba con "new row violates row-level security policy" — no porque
-- is_dueno() fuera falso (se confirmó aparte que sí evaluaba true), sino
-- porque Postgres aplica también la política de SELECT para decidir qué
-- fila puede devolver un RETURNING, y read_restaurants no dejaba ver esa
-- fila todavía.
--
-- Arreglo: agregar "el dueño siempre puede ver los restaurantes que le
-- pertenecen (owner_id = su propio uid)", sin importar approval_status ni
-- si ya se sincronizó restaurant_id en su app_metadata. owner_id ya existe
-- en la fila desde el instante del INSERT, así que cierra el hueco sin
-- rodeos y sin abrir nada que antes estuviera cerrado (solo agrega acceso
-- a SUS PROPIAS filas, nunca a las de otro dueño).

DROP POLICY IF EXISTS "read_restaurants" ON "public"."restaurants";

CREATE POLICY "read_restaurants" ON "public"."restaurants"
FOR SELECT
USING (
  approval_status = 'aprobado'
  OR is_admin()
  OR owner_id = auth.uid()
  OR (is_dueno() AND (id = ((auth.jwt() -> 'app_metadata'::text) ->> 'restaurant_id'::text)))
);

-- Aplicado a GOGO-Pruebas el 2026-09-07 vía psql -f.
