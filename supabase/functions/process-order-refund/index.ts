// Supabase Edge Function — Admin aprueba o rechaza una solicitud de
// reembolso de un pedido normal (order_refund_requests, ver migración
// 20261026030000_order_refund_requests.sql). Antes no existía ningún
// mecanismo real de reembolso para un pedido — "contáctanos para
// resolverlo caso por caso" no tenía nada real detrás.
//
// Mismo principio que mark_rider_call_delivered / stripe-webhook: nunca se
// marca la solicitud como "procesado" solo porque Admin lo decidió — se
// marca procesado ÚNICAMENTE después de que Stripe confirma el reembolso
// de verdad (POST /v1/refunds exitoso). Si la llamada a Stripe falla, la
// solicitud se queda en 'pendiente' (nunca se avanza a medias) y se
// regresa el error real de Stripe para que Admin sepa qué pasó.
//
// Deploy: supabase functions deploy process-order-refund
// (SIN --no-verify-jwt: solo la llama Admin, ya logueado)
//
// body: { refundRequestId: string, action: 'approve' | 'reject', adminNotes?: string }

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

    // 1. Verifica que quien llama sea admin de verdad, con is_admin() —
    // la MISMA función que usa RLS en toda la base (checa el correo
    // admin@fercadi.com, ver baseline_schema.sql). No se usa un campo de
    // "role" en user_metadata/app_metadata: la cuenta de Admin no tiene
    // ningún role guardado, se identifica solo por correo.
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    if (!callerData?.user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    const { data: isAdmin } = await callerClient.rpc('is_admin')
    if (!isAdmin) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { refundRequestId, action, adminNotes } = await req.json()
    if (!refundRequestId || (action !== 'approve' && action !== 'reject')) {
      return new Response(JSON.stringify({ error: 'Faltan datos o acción inválida' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. service_role SOLO para el trabajo privilegiado (leer/escribir la
    // solicitud y el pedido) — nunca expuesta al cliente.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: reqRow, error: reqError } = await admin
      .from('order_refund_requests')
      .select('id, order_id, status')
      .eq('id', refundRequestId)
      .maybeSingle()
    if (reqError || !reqRow) {
      return new Response(JSON.stringify({ error: 'Solicitud de reembolso no encontrada' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (reqRow.status !== 'pendiente') {
      return new Response(JSON.stringify({ error: `Esta solicitud ya se resolvió (${reqRow.status}).` }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'reject') {
      await admin
        .from('order_refund_requests')
        .update({
          status: 'rechazado',
          admin_notes: adminNotes ?? null,
          resolved_at: new Date().toISOString(),
        })
        .eq('id', refundRequestId)
      return new Response(JSON.stringify({ ok: true, status: 'rechazado' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // action === 'approve' — SIEMPRE se relee el pedido real de la BD, nunca
    // se confía en nada que mande el body sobre el pago.
    const { data: order, error: orderError } = await admin
      .from('orders')
      .select('id, stripe_payment_intent_id, payment_status, total')
      .eq('id', reqRow.order_id)
      .maybeSingle()
    if (orderError || !order) {
      return new Response(JSON.stringify({ error: 'El pedido de esta solicitud ya no existe' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (order.payment_status !== 'paid' || !order.stripe_payment_intent_id) {
      return new Response(
        JSON.stringify({
          error: 'Este pedido no tiene un pago con tarjeta confirmado que se pueda reembolsar por Stripe.',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: 'Stripe no configurado' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const refundRes = await fetch('https://api.stripe.com/v1/refunds', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        // Misma llave que reject-order: un pedido nunca se reembolsa dos
        // veces, venga de donde venga.
        'Idempotency-Key': `gogo-refund-${order.id}`,
      },
      // SOLO el total de ESTE pedido — antes se reembolsaba el PaymentIntent
      // completo, que en un pedido de 2 restaurantes también cubre la pierna
      // hermana (que sigue 'paid' y se le sigue pagando a su restaurante y
      // repartidor).
      body: new URLSearchParams({
        payment_intent: order.stripe_payment_intent_id,
        amount: String(Math.round(Number(order.total) * 100)),
      }),
    })
    const refund = await refundRes.json()

    // Nunca se marca "procesado" si Stripe no confirmó de verdad — la
    // solicitud se queda en 'pendiente' (no a medias en otro estado) y se
    // regresa el error real de Stripe para que Admin sepa exactamente qué
    // pasó y pueda reintentar.
    if (!refundRes.ok || refund.status === 'failed') {
      return new Response(
        JSON.stringify({ error: refund.error?.message ?? 'Stripe no pudo procesar el reembolso' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    await admin
      .from('order_refund_requests')
      .update({
        status: 'procesado',
        admin_notes: adminNotes ?? null,
        stripe_refund_id: refund.id,
        resolved_at: new Date().toISOString(),
      })
      .eq('id', refundRequestId)

    // El pedido en sí también refleja que ya se reembolsó — mismo patrón
    // de 'reembolsado' que ya usa payment_status en rider_calls.
    await admin
      .from('orders')
      .update({ payment_status: 'reembolsado' })
      .eq('id', reqRow.order_id)

    return new Response(JSON.stringify({ ok: true, status: 'procesado', stripeRefundId: refund.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
