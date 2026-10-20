-- GOGO Premium pasa de activarse a mano por SQL a un cobro real por Stripe
-- (suscripción mensual) — estas dos columnas guardan la liga entre un
-- restaurante y su cliente/suscripción en Stripe, para poder:
--   1. Reusar el mismo Customer si el dueño vuelve a intentar pagar.
--   2. Abrir el "Billing Portal" de Stripe (para que el dueño cancele por
--      su cuenta, sin que tengamos que construir esa pantalla a mano).
-- El webhook de Stripe (stripe-webhook) es quien prende/apaga is_premium
-- según el estado real de la suscripción — nunca el cliente directamente.

alter table public.restaurants
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text;
