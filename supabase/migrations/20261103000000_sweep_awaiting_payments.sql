-- Bloque 1, punto 3: pedidos 'awaiting_payment' que nunca caducaban. Antes de
-- esto, un pedido con tarjeta que se quedó a medias (app cerrada, red
-- perdida, Stripe colgado) se quedaba invisible para siempre: ni el
-- restaurante lo veía (no está en 'pending') ni nadie lo cancelaba.
--
-- Cada 10 minutos, pg_cron llama a la Edge Function sweep-awaiting-payments
-- (ver supabase/functions/sweep-awaiting-payments/index.ts), que revisa con
-- Stripe cada pedido 'awaiting_payment' con más de 30 minutos: si el cobro sí
-- se completó, lo confirma (igual que confirmCardPayment); si no, cancela el
-- payment intent y el/los pedido(s).
--
-- *** PASO MANUAL, UNA SOLA VEZ, DESPUÉS DE APLICAR ESTA MIGRACIÓN ***
-- Por seguridad esto NO guarda ningún secreto en el repo. Hay que guardar el
-- service_role_key de este proyecto en Vault corriendo DIRECTO en el SQL
-- Editor del dashboard de Supabase (nunca en un archivo ni en un commit):
--
--   select vault.create_secret(
--     '<pegar aquí el service_role_key real de este proyecto>',
--     'gogo_service_role_key'
--   );
--
-- Sin ese paso, el cron job existe pero cada corrida falla en silencio
-- (la función responde 401 porque no recibe la llave) — no rompe nada, solo
-- no limpia nada todavía.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'gogo-sweep-awaiting-payment') then
    perform cron.unschedule('gogo-sweep-awaiting-payment');
  end if;
end $$;

select cron.schedule(
  'gogo-sweep-awaiting-payment',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url := current_setting('app.settings.supabase_url', true) || '/functions/v1/sweep-awaiting-payments',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'gogo_service_role_key'
        limit 1
      )
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- 'app.settings.supabase_url' no es una variable estándar: Supabase no
-- expone la URL del propio proyecto por defecto dentro de Postgres. Se deja
-- puesta aquí (en vez de hardcodear la URL del proyecto en el repo) y se
-- define con ALTER DATABASE, también a mano en el SQL Editor, junto con el
-- paso del secreto de arriba:
--
--   alter database postgres set app.settings.supabase_url = 'https://<project-ref>.supabase.co';
--
-- (Alternativa más simple si se prefiere: reemplazar la línea
-- "current_setting('app.settings.supabase_url', true) || ..." de arriba por
-- la URL del proyecto escrita literal antes de aplicar esta migración — la
-- URL del proyecto no es secreta, a diferencia de la llave.)
