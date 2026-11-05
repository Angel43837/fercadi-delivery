// Supabase Edge Function — cobro de la propina con tarjeta para el
// repartidor de un pedido ya entregado (lib/rating_dialog.dart).
//
// Antes esta función no existía: cualquier intento de dar propina con
// tarjeta fallaba en silencio y de paso se perdía la calificación completa
// (rating_dialog.dart no guardaba la calificación si la propina fallaba).
//
// El monto SIEMPRE se valida contra las 4 opciones fijas que ofrece la UI
// (nunca se confía en lo que mande el celular más allá de esas 4). La
// propina va completa al repartidor (sin el 10% de comisión de la
// plataforma) — se acredita a su saldo retirable normal (order_tips +
// get_rider_balance), no como una transferencia aparte de Stripe Connect,
// para no pagar una comisión de transferencia extra por cada propina chica.
//
// El estado real (pagada o no) lo confirma SIEMPRE el webhook de Stripe
// (ver stripe-webhook/index.ts) cuando el PaymentIntent se resuelve — esta
// función solo crea el cobro y regresa el clientSecret.
//
// Deploy: supabase functions deploy create-tip-payment-intent --use-api
// (SIN --no-verify-jwt: requiere la sesión real del cliente)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// Mismas 4 opciones fijas que rating_dialog.dart ofrece ($10/$20/$50/$100) —
// cualquier otro monto se rechaza, no solo se recorta.
const ALLOWED_CENTS = [1000, 2000, 5000, 10000]

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    const callerId = callerData?.user?.id
    if (!callerId) return json({ error: 'No autenticado' }, 401)

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) return json({ error: 'Stripe no configurado' }, 500)

    const { order_id: orderId, amount } = await req.json()
    if (typeof orderId !== 'string' || !orderId) {
      return json({ error: 'Falta order_id' }, 400)
    }
    const amountCents = Math.round(Number(amount))
    if (!ALLOWED_CENTS.includes(amountCents)) {
      return json({ error: 'Monto de propina no válido' }, 400)
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: order, error: orderError } = await admin
      .from('orders')
      .select('id, status, customer_id, repartidor_id')
      .eq('id', orderId)
      .maybeSingle()
    if (orderError || !order) return json({ error: 'Pedido no encontrado' }, 404)
    if (order.customer_id !== callerId) return json({ error: 'No autorizado' }, 403)
    if (order.status !== 'delivered') {
      return json({ error: 'Este pedido todavía no se ha entregado' }, 409)
    }
    if (!order.repartidor_id) {
      return json({ error: 'Este pedido no tiene repartidor asignado' }, 409)
    }

    const { data: existing } = await admin
      .from('order_tips')
      .select('id, amount, status')
      .eq('order_id', orderId)
      .maybeSingle()
    if (existing?.status === 'paid') {
      return json({ error: 'Ya le diste propina a este pedido' }, 409)
    }

    // Un intento ANTERIOR todavía 'pending_payment' (la petición de verdad
    // podría seguir en curso, ej. la app se cerró a medio pago) sí reusa la
    // MISMA llave de idempotencia y el mismo monto — así un reintento no
    // cobra dos veces. Pero uno que el webhook ya marcó 'failed' (la tarjeta
    // se rechazó de verdad, ese intento ya está muerto) usa una llave nueva:
    // reusar la fija haría que Stripe regresara ese mismo PaymentIntent ya
    // en estado terminal, y el cliente nunca podría pagar con otra tarjeta.
    const isDeadRetry = existing?.status === 'failed'
    const finalAmountCents = existing && !isDeadRetry ? Math.round(Number(existing.amount) * 100) : amountCents
    const idempotencyKey = isDeadRetry
      ? `gogo-tip-${orderId}-retry-${crypto.randomUUID()}`
      : `gogo-tip-${orderId}`

    const body = new URLSearchParams({
      amount: String(finalAmountCents),
      currency: 'mxn',
      'payment_method_types[]': 'card',
      'metadata[orderId]': orderId,
      'metadata[repartidorId]': order.repartidor_id,
      'metadata[kind]': 'tip',
    })
    const stripeRes = await fetch('https://api.stripe.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': idempotencyKey,
      },
      body,
    })
    const intent = await stripeRes.json()
    if (!stripeRes.ok) return json({ error: intent.error?.message ?? 'Error de Stripe' }, 400)

    // Si esto falla, NO se regresa el client_secret: el cliente pagaría una
    // propina que la BD nunca sabría a qué pedido ligar (el webhook busca
    // por stripe_payment_intent_id en order_tips; sin esta fila, el cobro se
    // queda huérfano y el repartidor nunca ve ese dinero en su saldo).
    const { error: dbError } = existing
      ? await admin.from('order_tips')
          .update({ stripe_payment_intent_id: intent.id, status: 'pending_payment', amount: finalAmountCents / 100 })
          .eq('id', existing.id)
      : await admin.from('order_tips').insert({
          order_id: orderId,
          customer_id: callerId,
          repartidor_id: order.repartidor_id,
          amount: finalAmountCents / 100,
          stripe_payment_intent_id: intent.id,
          status: 'pending_payment',
        })
    if (dbError) {
      // El PaymentIntent ya se creó en Stripe pero no se pudo registrar —
      // se cancela para no dejarlo cobrable sin que nada en la BD lo rastree.
      await fetch(`https://api.stripe.com/v1/payment_intents/${intent.id}/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${stripeSecretKey}` },
      }).catch(() => {})
      return json({ error: 'No se pudo registrar la propina, intenta de nuevo.' }, 500)
    }

    // Se regresa el monto real que se va a cobrar (puede no ser el mismo que
    // pidió el celular esta vez: ver finalAmountCents) — así la UI guarda en
    // ratings.tip lo que de verdad se cobró, no lo que el usuario alcanzó a
    // seleccionar antes de que se reusara un monto distinto.
    return json({ client_secret: intent.client_secret, amount: finalAmountCents / 100 })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
