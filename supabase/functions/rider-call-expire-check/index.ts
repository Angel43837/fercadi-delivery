// Supabase Edge Function — reembolsa solas las llamadas de "pedir
// repartidor" que nadie aceptó en 3 horas. No hay cron configurado en este
// proyecto (pg_cron/vault no están armados aquí) — en vez de eso, esta
// función se llama de oquis (fire-and-forget, se ignora el resultado)
// cada vez que la app de escritorio o la de rider hacen su sondeo normal
// de llamadas activas. Es "mejor esfuerzo": si nadie tiene ninguna app
// abierta justo cuando se cumplen las 3 horas, el reembolso se procesa en
// cuanto alguien vuelva a abrir una.
//
// Deploy: supabase functions deploy rider-call-expire-check
// (SIN --no-verify-jwt: la llama cualquier usuario ya logueado; sin callId
// solo actúa sobre llamadas ya vencidas, con callId solo el dueño de ese
// restaurante)
//
// body: {} — procesa todo lo vencido (3h)
//     | { callId } — reembolsa ESA llamada específica ya mismo, sin
//       esperar 3h (usado cuando el dueño cancela a mano una pendiente)

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: userData } = await userClient.auth.getUser()
    if (!userData?.user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    let callId: string | undefined
    try { ({ callId } = await req.json()) } catch (_) { /* body vacío, modo normal */ }

    // 1. Primero se CANCELA (update condicional status='pendiente') y solo
    // después se reembolsa: así un rider ya no puede aceptar una llamada
    // cuyo dinero se está devolviendo (antes el update no tenía condición y
    // una llamada recién aceptada quedaba 'cancelado' con el rider sin
    // cobrar).
    if (callId) {
      // Con callId solo el restaurante dueño de esa llamada (o Admin) —
      // antes cualquier usuario podía cancelar y reembolsar llamadas ajenas.
      const { data: call } = await admin
        .from('rider_calls')
        .select('restaurant_id')
        .eq('id', callId)
        .maybeSingle()
      if (!call) return json({ refunded: 0 })
      const { data: owns } = await userClient.rpc('owns_restaurant', { p_restaurant_id: call.restaurant_id })
      if (owns !== true) return json({ error: 'No autorizado' }, 403)
      await admin.from('rider_calls')
        .update({ status: 'cancelado' })
        .eq('id', callId)
        .eq('status', 'pendiente')
        .eq('payment_status', 'cobrado')
    } else {
      const cutoff = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString()
      await admin.from('rider_calls')
        .update({ status: 'cancelado' })
        .eq('status', 'pendiente')
        .eq('payment_status', 'cobrado')
        .lt('created_at', cutoff)
    }

    // 2. Reembolsa todo lo cancelado que siga cobrado — incluye los que
    // fallaron en una pasada anterior (antes se marcaba 'reembolsado'
    // aunque Stripe hubiera rechazado el reembolso).
    let pendingQuery = admin
      .from('rider_calls')
      .select('id, payment_intent_id')
      .eq('status', 'cancelado')
      .eq('payment_status', 'cobrado')
      .limit(25)
    if (callId) pendingQuery = pendingQuery.eq('id', callId)
    const { data: toRefund } = await pendingQuery

    let refunded = 0
    for (const call of toRefund ?? []) {
      if (!stripeSecretKey || !call.payment_intent_id) continue
      try {
        const refundRes = await fetch('https://api.stripe.com/v1/refunds', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${stripeSecretKey}`,
            'Content-Type': 'application/x-www-form-urlencoded',
            // Una misma llamada nunca se reembolsa dos veces, aunque esta
            // función corra en paralelo desde varias apps.
            'Idempotency-Key': `rider-call-refund-${call.id}`,
          },
          body: new URLSearchParams({ payment_intent: call.payment_intent_id }),
        })
        const refund = await refundRes.json()
        if (!refundRes.ok || refund.status === 'failed') continue
        await admin.from('rider_calls')
          .update({ payment_status: 'reembolsado' })
          .eq('id', call.id)
        refunded++
      } catch (_) {
        // Sigue con las demás — se reintenta sola la próxima vez.
      }
    }

    return new Response(JSON.stringify({ refunded }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
