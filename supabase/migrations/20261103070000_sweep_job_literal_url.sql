-- El paso manual que dejó pendiente 20261103000000_sweep_awaiting_payments.sql
-- (alter database postgres set app.settings.supabase_url = '...') lo bloquea
-- Supabase con "permiso denegado" — el SQL Editor del dashboard no corre con
-- privilegios para tocar parámetros a nivel de base de datos, aunque sea el
-- dueño del proyecto. Se usa la alternativa que ya se había dejado
-- documentada ahí mismo: la URL del proyecto no es secreta (a diferencia del
-- service_role_key, que sigue yendo solo por Vault), así que se escribe
-- literal en el cron job en vez de depender de ese ajuste.
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
    url := 'https://ymztoayxzewghbethahv.supabase.co/functions/v1/sweep-awaiting-payments',
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
