// Supabase Edge Function — un dueño rechaza un pedido de SU restaurante (o
// Admin rechaza cualquiera, o el cliente cancela el suyo mientras siga
// 'pending'). Antes `dueno_screen.dart` llamaba directo a
// updateOrderStatus(id, 'cancelled') sin tocar nada del pago — hueco real
// confirmado en esta sesión: un pedido pagado con tarjeta que el dueño
// rechazaba se quedaba cobrado para siempre, el cliente nunca recibía su
// dinero de vuelta aunque el restaurante jamás preparó nada.
//
// También es la pieza que hace segura la función de "2 restaurantes por
// pedido" (ver 20261031000000_multi_restaurant_orders.sql): si se rechaza
// una sola pierna de un pedido de grupo, la otra pierna sigue su curso
// normal sin tocarse — este endpoint solo opera sobre el pedido que recibe,
// nunca sobre su group_id ni sobre pedidos hermanos.
//
// Mismo principio que process-order-refund: nunca se marca "cancelado" un
// pedido con pago real hasta que Stripe confirme el reembolso de verdad. El
// reembolso es SIEMPRE por el total de ESTE pedido únicamente (nunca el de
// un pedido hermano, nunca el PaymentIntent completo si es compartido con
// uno) — Stripe soporta reembolsos parciales con el parámetro `amount`.
//
// Deploy: supabase functions deploy reject-order
// (SIN --no-verify-jwt: solo la llama un dueño o Admin ya logueado)
//
// body: { orderId: string, reason?: string }
// respuesta éxito: { ok: true, refunded: boolean, stripeRefundId?: string }
// respuesta error: { error: '<mensaje exacto para mostrar al usuario>' }

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

    // 1. Verifica quién llama con su PROPIO JWT (anon client) — mismo
    // patrón que delete-account/process-order-refund.
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    const user = callerData?.user
    if (!user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { orderId, reason } = await req.json()
    if (!orderId || typeof orderId !== 'string') {
      return new Response(JSON.stringify({ error: 'Falta orderId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. service_role SOLO para el trabajo privilegiado (leer/escribir el
    // pedido) — nunca expuesta al cliente. Se relee el pedido real de la
    // BD, nunca se confía en nada que mande el body sobre su pago.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: order, error: orderError } = await admin
      .from('orders')
      .select('id, restaurant_id, customer_id, status, payment_status, stripe_payment_intent_id, total')
      .eq('id', orderId)
      .maybeSingle()
    if (orderError || !order) {
      return new Response(JSON.stringify({ error: 'Este pedido ya no existe.' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. Autorización: Admin, o el dueño del restaurante de ESTE pedido —
    // mismo chequeo que is_dueno()/is_admin() usan en RLS, pero aquí hecho
    // a mano porque is_dueno() por sí solo no sabe de qué restaurante es
    // dueño quien llama, y lo que importa es que sea el de este pedido.
    const { data: isAdmin } = await callerClient.rpc('is_admin')
    const appMeta = (user.app_metadata ?? {}) as Record<string, unknown>
    const isOwnerOfThisRestaurant =
      appMeta.role === 'dueno' && appMeta.restaurant_id === order.restaurant_id
    // El cliente también puede cancelar SU pedido, pero solo mientras el
    // restaurante no lo haya confirmado (status 'pending') — mismo límite que
    // promete el Aviso de Términos. Antes usaba cancel_my_order(uuid), que
    // nunca funcionó (los ids de pedido son texto) y no reembolsaba.
    const isCustomer = order.customer_id === user.id
    if (!isAdmin && !isOwnerOfThisRestaurant && !isCustomer) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // El estado final (cancelado/entregado) se revisa ANTES que el límite de
    // "solo mientras siga pending" del cliente — antes era al revés, así que
    // un cliente que intentaba cancelar un pedido YA cancelado (ej. doble
    // clic, o reintento tras perder la red) veía "tu pedido ya está siendo
    // preparado" en vez del mensaje real. No cambiaba nada en la seguridad
    // (de cualquier forma no se reembolsaba dos veces), solo el mensaje.
    if (order.status === 'cancelled') {
      return new Response(JSON.stringify({ error: 'Este pedido ya está cancelado.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (order.status === 'delivered') {
      return new Response(JSON.stringify({ error: 'Este pedido ya fue entregado, no se puede rechazar.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    // El cliente también puede cancelar SU pedido, pero solo mientras el
    // restaurante no lo haya confirmado (status 'pending') — mismo límite que
    // promete el Aviso de Términos. Antes usaba cancel_my_order(uuid), que
    // nunca funcionó (los ids de pedido son texto) y no reembolsaba.
    if (!isAdmin && !isOwnerOfThisRestaurant && isCustomer && order.status !== 'pending') {
      return new Response(JSON.stringify({ error: 'Tu pedido ya está siendo preparado, ya no se puede cancelar.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const cancelReason = typeof reason === 'string' && reason.trim() ? reason.trim() : null
    const needsRefund = order.payment_status === 'paid' && !!order.stripe_payment_intent_id

    if (!needsRefund) {
      // Efectivo, o sin pago confirmado todavía — nada que reembolsar,
      // solo se cancela.
      await admin
        .from('orders')
        .update({ status: 'cancelled', cancel_reason: cancelReason })
        .eq('id', orderId)
      return new Response(JSON.stringify({ ok: true, refunded: false }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: 'Stripe no configurado' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // SOLO el total de ESTE pedido, en centavos — nunca el total del
    // PaymentIntent completo (que en un pedido de 2 restaurantes también
    // cubre la pierna hermana, que sigue viva y con su propio cobro
    // legítimo) ni el de otro pedido.
    const amountCents = Math.round(Number(order.total) * 100)
    const refundRes = await fetch('https://api.stripe.com/v1/refunds', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        // Un reintento (p. ej. tras un timeout) regresa el mismo reembolso
        // en vez de reembolsar dos veces.
        'Idempotency-Key': `gogo-refund-${order.id}`,
      },
      body: new URLSearchParams({
        payment_intent: order.stripe_payment_intent_id,
        amount: String(amountCents),
      }),
    })
    const refund = await refundRes.json()

    // Nunca se marca "cancelado"/"reembolsado" si Stripe no confirmó de
    // verdad — el pedido se queda exactamente como estaba y se regresa el
    // error real de Stripe.
    if (!refundRes.ok || refund.status === 'failed') {
      return new Response(
        JSON.stringify({ error: refund.error?.message ?? 'Stripe no pudo procesar el reembolso' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    await admin
      .from('orders')
      .update({ status: 'cancelled', payment_status: 'reembolsado', cancel_reason: cancelReason })
      .eq('id', orderId)

    return new Response(JSON.stringify({ ok: true, refunded: true, stripeRefundId: refund.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
