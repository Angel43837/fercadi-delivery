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
// (SIN --no-verify-jwt: la llama cualquier usuario ya logueado, pero solo
// actúa sobre filas que de verdad ya vencieron, nunca sobre las de otros)
//
// body: {} — procesa todo lo vencido (3h)
//     | { callId } — reembolsa ESA llamada específica ya mismo, sin
//       esperar 3h (usado cuando el dueño cancela a mano una pendiente)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    let expired: { id: string; payment_intent_id: string | null }[] | null
    if (callId) {
      const { data } = await admin
        .from('rider_calls')
        .select('id, payment_intent_id')
        .eq('id', callId)
        .eq('status', 'pendiente')
        .eq('payment_status', 'cobrado')
        .limit(1)
      expired = data
    } else {
      const cutoff = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString()
      const { data } = await admin
        .from('rider_calls')
        .select('id, payment_intent_id')
        .eq('status', 'pendiente')
        .eq('payment_status', 'cobrado')
        .lt('created_at', cutoff)
        .limit(25)
      expired = data
    }

    let refunded = 0
    for (const call of expired ?? []) {
      try {
        if (stripeSecretKey && call.payment_intent_id) {
          await fetch('https://api.stripe.com/v1/refunds', {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${stripeSecretKey}`,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({ payment_intent: call.payment_intent_id }),
          })
        }
        await admin.from('rider_calls')
          .update({ status: 'cancelado', payment_status: 'reembolsado' })
          .eq('id', call.id)
        refunded++
      } catch (_) {
        // Sigue con las demás aunque una falle — se reintenta sola la
        // próxima vez que alguien vuelva a llamar a esta función.
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
