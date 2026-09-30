-- Investigación (septiembre 2026): Riders y Restaurantes no podían iniciar
-- sesión con correo+contraseña ni siquiera con credenciales 100% correctas.
--
-- Causa encontrada: este proyecto de Supabase (GOGO-Pruebas) tiene activada
-- la confirmación de correo obligatoria ("Confirm email" en Auth), pero la
-- app nunca implementó nada para completar ese paso (no hay pantalla de
-- "revisa tu correo", no hay manejo del enlace de confirmación, no hay
-- deep link de regreso a la app). Resultado: toda cuenta creada por
-- signUp() se queda con email_confirmed_at = NULL para siempre, y
-- signInWithPassword() la rechaza con "Email not confirmed" — que la app
-- mostraba, incorrectamente, como "Correo o contraseña incorrectos" (los
-- login screens de dueño/repartidor atrapan cualquier excepción con el
-- mismo mensaje genérico, sin distinguir el motivo real).
--
-- Se confirmó reproduciendo el flujo completo por la API REST de Supabase:
-- signup con un correo de prueba -> login inmediato -> "email_not_confirmed".
-- 3 cuentas reales del proyecto ya estaban atascadas así (dos de prueba de
-- dueño, y anjelom227pruebas@gmail.com).
--
-- Esta app es interna (Riders/Restaurantes/Clientes se dan de alta y usan
-- la cuenta de inmediato, sin buzón de correo de por medio) — no tiene
-- sentido exigir un clic de confirmación que la app no sabe completar.
-- Como no hay acceso al dashboard de Supabase (Authentication > Settings)
-- desde aquí para apagar "Confirm email" directamente, se logra el mismo
-- efecto a nivel de base de datos: cualquier cuenta nueva queda confirmada
-- automáticamente en el instante en que se crea.

-- 1) Backfill: las 3 cuentas que ya estaban atascadas.
UPDATE auth.users
SET email_confirmed_at = now()
WHERE email_confirmed_at IS NULL;

-- 2) De aquí en adelante: cualquier auth.users nuevo se confirma solo.
-- La función vive en public (no se puede CREATE en el schema auth con este
-- usuario), pero el trigger sí se puede enganchar a auth.users desde aquí
-- — mismo patrón ya usado por sync_role_to_app_metadata().
CREATE OR REPLACE FUNCTION public.gogo_auto_confirm_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.email_confirmed_at IS NULL THEN
    NEW.email_confirmed_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gogo_auto_confirm_email ON auth.users;
CREATE TRIGGER trg_gogo_auto_confirm_email
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.gogo_auto_confirm_email();

-- Aplicado a GOGO-Pruebas el 2026-09-07 vía psql -f. Pendiente de aplicar a
-- producción si esa base de datos llega a usarse (ver conversación: por
-- ahora Pruebas es la base "real").
