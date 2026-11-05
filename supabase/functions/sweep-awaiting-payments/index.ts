// Supabase Edge Function — limpia pedidos 'awaiting_payment' que se quedaron
// atorados (la app se cerró a medio pago, perdió la red, etc.) y nunca se
// confirmaron ni cancelaron solos.
//
// La llama un cron job de Postgres (pg_cron + pg_net) cada 10 minutos — ver
// supabase/migrations/20261103000000_sweep_awaiting_payments.sql — nunca un
// usuario de la app. Por eso se despliega con --no-verify-jwt (no hay sesión
// de usuario real que verificar) PERO exige que el llamador mande el mismo
// SERVICE_ROLE_KEY del proyecto como Bearer token — así, aunque la URL sea
// pública, solo quien ya tiene esa llave (el propio proyecto, vía el cron
// job) puede ejecutarla.
//
// Deploy: supabase functions deploy sweep-awaiting-payments --no-verify-jwt

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

async function stripe(path: string, secretKey: string, init: { method?: string; body?: URLSearchParams } = {}) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secretKey}`,
    'Content-Type': 'application/x-www-form-urlencoded',
  }
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: init.method ?? 'GET',
    headers,
    body: init.body?.toString(),
  })
  return { ok: res.ok, data: await res.json() }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!serviceRoleKey || authHeader !== `Bearer ${serviceRoleKey}`) {
    return json({ error: 'No autorizado' }, 401)
  }

  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
  if (!stripeSecretKey) return json({ error: 'Stripe no configurado' }, 500)

  const admin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    serviceRoleKey,
  )

  const cutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString()
  const { data: stale, error } = await admin
    .from('orders')
    .select('id, stripe_payment_intent_id, total')
    .eq('status', 'awaiting_payment')
    .lt('created_at', cutoff)
    .limit(200)

  if (error) return json({ error: error.message }, 500)
  if (!stale || stale.length === 0) return json({ swept: 0 })

  // Agrupa por payment intent (un mismo cobro puede cubrir 2 pedidos, los de
  // un pedido de 2 restaurantes) para no revisarlo dos veces ni confirmar
  // uno a medias.
  const intentIds = new Set<string>()
  const noIntent: string[] = []
  for (const o of stale) {
    const intentId = o.stripe_payment_intent_id as string | null
    if (!intentId) {
      noIntent.push(o.id as string)
      continue
    }
    intentIds.add(intentId)
  }

  let confirmed = 0
  let cancelled = 0
  const results: Record<string, string> = {}

  // Sin payment intent todavía (falló antes de crearlo): directo a cancelado.
  if (noIntent.length > 0) {
    await admin.from('orders').update({ status: 'cancelled' }).in('id', noIntent).eq('status', 'awaiting_payment')
    cancelled += noIntent.length
    for (const id of noIntent) results[id] = 'cancelled (sin payment intent)'
  }

  for (const intentId of intentIds) {
    // TODOS los pedidos de este PaymentIntent, no solo los que ya llevan 30
    // min esperando — en un pedido de 2 restaurantes puede que una pierna ya
    // se haya confirmado (webhook normal) y la otra se quedara atorada; si
    // aquí solo se mira la pierna vieja, `ids` nunca va a calzar con
    // `metadata.orderIds` (que trae las 2) y el pago se veía como "no
    // cuadra" aunque Stripe sí cobró completo — eso cancelaba una pierna ya
    // pagada de verdad.
    const { data: siblings } = await admin
      .from('orders')
      .select('id, total, status')
      .eq('stripe_payment_intent_id', intentId)
    const orders = siblings ?? []
    const ids = orders.map((o) => o.id as string).sort()
    const amountCents = orders.reduce((sum, o) => sum + Math.round(Number(o.total) * 100), 0)
    const { ok, data: intent } = await stripe(`payment_intents/${intentId}`, stripeSecretKey)
    if (!ok) {
      for (const id of ids) results[id] = `error al consultar Stripe: ${JSON.stringify(intent)}`
      continue
    }
    const metaIds = String(intent.metadata?.orderIds ?? '').split(',').filter(Boolean).sort()
    const matches = intent.amount_received === amountCents && metaIds.join(',') === ids.join(',')
    const paid = intent.status === 'succeeded' && matches

    if (paid) {
      await admin
        .from('orders')
        .update({ payment_status: 'paid', status: 'pending' })
        .in('id', ids)
        .eq('status', 'awaiting_payment')
      confirmed += ids.length
      for (const id of ids) results[id] = 'confirmed (paid)'
      continue
    }

    // Si Stripe dice que el cobro SÍ se completó pero el monto o los ids no
    // cuadran con lo que hay en la BD, es justo el caso que no se debe tocar
    // solo — podría ser un pedido editado a mano, una fuga de datos, o un
    // bug nuevo. Se deja una alerta para revisión humana y no se cancela ni
    // se confirma nada (mismo criterio que stripe-webhook con el monto).
    if (intent.status === 'succeeded') {
      await admin.from('alerts').insert({
        title: 'Pago completado no coincide con el pedido (sweep)',
        description: `PaymentIntent ${intentId} succeeded por ${intent.amount_received / 100}` +
          ` pero los pedidos ${ids.join(', ') || '—'} suman ${amountCents / 100}.` +
          ` orderIds del intent: ${metaIds.join(', ') || '—'}.`,
        priority: 'alta',
        category: 'pagos',
        status: 'pendiente',
      })
      for (const id of ids) results[id] = 'revisión manual (pagado pero no coincide)'
      continue
    }

    if (!['canceled', 'processing'].includes(intent.status)) {
      await stripe(`payment_intents/${intentId}/cancel`, stripeSecretKey, { method: 'POST' })
    }
    if (intent.status === 'processing') {
      // Pago en curso de verdad (ej. OXXO esperando el depósito) — no se
      // cancela nada todavía, se revisa de nuevo en la siguiente pasada.
      for (const id of ids) results[id] = 'processing (se revisa en 10 min)'
      continue
    }
    await admin.from('orders').update({ status: 'cancelled' }).in('id', ids).eq('status', 'awaiting_payment')
    cancelled += ids.length
    for (const id of ids) results[id] = 'cancelled (pago no completado)'
  }

  return json({ swept: stale.length, confirmed, cancelled, results })
})
