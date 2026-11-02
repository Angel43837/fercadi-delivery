// Supabase Edge Function — cobro con tarjeta de pedidos YA creados.
//
// El monto SIEMPRE sale de orders.total en la BD (calculado por place_order,
// ver migración 20261102010000_server_side_orders.sql) — nunca de lo que
// mande el celular. Antes el checkout mandaba "amount" y se cobraba tal cual.
//
// Deploy: supabase functions deploy create-payment-intent
// (SIN --no-verify-jwt: requiere la sesión real del cliente)
//
// body:
//   { action: 'create',  orderIds: string[], paymentMethodType?: 'card' | 'oxxo' }
//     → { clientSecret, id, amount }
//   { action: 'confirm', orderIds: string[] }
//     → revisa con Stripe que el pago de esos pedidos se completó y por el
//       monto correcto; si sí, los pasa a payment_status='paid' +
//       status='pending' (ya visibles al restaurante). Mismo efecto que el
//       webhook — lo que llegue primero gana, el otro no hace nada.
//   { action: 'abandon', orderIds: string[] }
//     → el cliente canceló/cerró el pago: cancela el PaymentIntent y los
//       pedidos (si Stripe dice que sí se cobró, los confirma en vez de
//       cancelarlos).

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

async function stripe(path: string, secretKey: string, init: { method?: string; body?: URLSearchParams; idempotencyKey?: string } = {}) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secretKey}`,
    'Content-Type': 'application/x-www-form-urlencoded',
  }
  if (init.idempotencyKey) headers['Idempotency-Key'] = init.idempotencyKey
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: init.method ?? 'GET',
    headers,
    body: init.body?.toString(),
  })
  return { ok: res.ok, data: await res.json() }
}

const toCents = (orders: { total: number }[]) =>
  orders.reduce((sum, o) => sum + Math.round(Number(o.total) * 100), 0)

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

    const { action = 'create', orderIds, paymentMethodType } = await req.json()
    if (!Array.isArray(orderIds) || orderIds.length === 0 || orderIds.length > 10) {
      return json({ error: 'Faltan los pedidos a cobrar' }, 400)
    }
    const ids = [...new Set(orderIds.map(String))].sort()

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )
    const { data: orders, error: ordersError } = await admin
      .from('orders')
      .select('id, total, status, payment_status, customer_id, stripe_payment_intent_id')
      .in('id', ids)
    if (ordersError || !orders || orders.length !== ids.length) {
      return json({ error: 'Pedido no encontrado' }, 404)
    }

    if (orders.some((o) => o.customer_id !== callerId)) {
      return json({ error: 'No autorizado' }, 403)
    }

    const amountCents = toCents(orders)

    // Marca pagados SOLO si Stripe confirma el cobro completo de estos
    // pedidos exactos. Idempotente: solo toca los que siguen esperando pago.
    const confirmFromIntent = async (intentId: string) => {
      const { ok, data: intent } = await stripe(`payment_intents/${intentId}`, stripeSecretKey)
      if (!ok) return { paid: false, intent: null }
      const metaIds = String(intent.metadata?.orderIds ?? '').split(',').filter(Boolean).sort()
      const paid =
        intent.status === 'succeeded' &&
        intent.amount_received === amountCents &&
        metaIds.join(',') === ids.join(',')
      if (paid) {
        await admin
          .from('orders')
          .update({ payment_status: 'paid', status: 'pending' })
          .in('id', ids)
          .eq('status', 'awaiting_payment')
      }
      return { paid, intent }
    }

    if (action === 'create') {
      if (orders.some((o) => o.status !== 'awaiting_payment')) {
        return json({ error: 'Este pedido ya no está esperando pago' }, 409)
      }
      if (amountCents <= 0 || amountCents > 50000 * 100) {
        return json({ error: 'Monto fuera de rango permitido' }, 400)
      }

      // OXXO no es compatible con "automatic_payment_methods" en modo
      // automático sin datos de envío — se pide explícitamente. Para tarjeta
      // se pide "card" explícito: con automático, Stripe intentaba ofrecer
      // TODO lo activo en el dashboard y el PaymentSheet se quedaba
      // cargando sin llegar a mostrar la tarjeta.
      const body = new URLSearchParams({
        amount: String(amountCents),
        currency: 'mxn',
        'metadata[orderIds]': ids.join(','),
        'metadata[customerId]': callerId,
        'payment_method_types[]': paymentMethodType === 'oxxo' ? 'oxxo' : 'card',
      })
      // Mismos pedidos + mismo monto = mismo PaymentIntent (un doble toque
      // en "Confirmar" no crea dos cobros).
      const { ok, data: intent } = await stripe('payment_intents', stripeSecretKey, {
        method: 'POST',
        body,
        idempotencyKey: `gogo-pi-${ids.join('_')}-${amountCents}`,
      })
      if (!ok) return json({ error: intent.error?.message ?? 'Error de Stripe' }, 400)

      await admin.from('orders').update({ stripe_payment_intent_id: intent.id }).in('id', ids)

      return json({ clientSecret: intent.client_secret, id: intent.id, amount: amountCents / 100 })
    }

    const intentId = orders[0].stripe_payment_intent_id as string | null
    if (orders.some((o) => o.stripe_payment_intent_id !== intentId)) {
      return json({ error: 'Los pedidos no pertenecen al mismo pago' }, 400)
    }

    if (action === 'confirm') {
      if (orders.every((o) => o.payment_status === 'paid')) return json({ paid: true })
      if (!intentId) return json({ paid: false })
      const { paid } = await confirmFromIntent(intentId)
      return json({ paid })
    }

    if (action === 'abandon') {
      if (intentId) {
        const { paid, intent } = await confirmFromIntent(intentId)
        if (paid) return json({ paid: true })
        if (intent && !['canceled', 'succeeded', 'processing'].includes(intent.status)) {
          await stripe(`payment_intents/${intentId}/cancel`, stripeSecretKey, { method: 'POST' })
        }
        // 'processing' (pago en curso): no se cancela nada, el webhook decide.
        if (intent?.status === 'processing') return json({ paid: false, processing: true })
      }
      await admin
        .from('orders')
        .update({ status: 'cancelled' })
        .in('id', ids)
        .eq('status', 'awaiting_payment')
      return json({ paid: false, cancelled: true })
    }

    return json({ error: 'Acción desconocida' }, 400)
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
