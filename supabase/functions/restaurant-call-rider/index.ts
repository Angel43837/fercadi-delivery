// Supabase Edge Function — cobra $38 MXN ($3 cuota + $35 de envío) a la
// tarjeta guardada del restaurante Y crea la fila de rider_calls, en un
// solo paso server-side — para que nunca quede una llamada creada sin
// cobro, ni un cobro hecho sin llamada creada.
//
// Deploy: supabase functions deploy restaurant-call-rider
// (SIN --no-verify-jwt: solo la llama el dueño ya logueado)
//
// body: { restaurantId, restaurantName }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const AMOUNT_FEE_MXN = 3
const AMOUNT_ENVIO_MXN = 35
const AMOUNT_TOTAL_CENTS = (AMOUNT_FEE_MXN + AMOUNT_ENVIO_MXN) * 100

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
    const user = userData?.user
    if (!user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { restaurantId, restaurantName } = await req.json()
    if (!restaurantId) {
      return new Response(JSON.stringify({ error: 'Falta restaurantId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const ownRestaurantId = (user.app_metadata as Record<string, unknown> | null)?.restaurant_id
      ?? (user.user_metadata as Record<string, unknown> | null)?.restaurant_id
    if (ownRestaurantId !== restaurantId) {
      return new Response(JSON.stringify({ error: 'No autorizado para este restaurante' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )
    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: 'Stripe no configurado' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: restaurant } = await admin
      .from('restaurants')
      .select('id, name, stripe_customer_id')
      .eq('id', restaurantId)
      .maybeSingle()
    const customerId = restaurant?.stripe_customer_id as string | undefined
    if (!customerId) {
      return new Response(JSON.stringify({ error: 'Primero agrega un método de pago.', code: 'no_payment_method' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const pmRes = await fetch(
      `https://api.stripe.com/v1/payment_methods?customer=${customerId}&type=card&limit=1`,
      { headers: { Authorization: `Bearer ${stripeSecretKey}` } },
    )
    const pmList = await pmRes.json()
    const paymentMethodId = pmList?.data?.[0]?.id as string | undefined
    if (!paymentMethodId) {
      return new Response(JSON.stringify({ error: 'Primero agrega un método de pago.', code: 'no_payment_method' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const piRes = await fetch('https://api.stripe.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        amount: String(AMOUNT_TOTAL_CENTS),
        currency: 'mxn',
        customer: customerId,
        payment_method: paymentMethodId,
        off_session: 'true',
        confirm: 'true',
        'metadata[restaurant_id]': restaurantId,
        'metadata[type]': 'rider_call',
        description: `GOGO — pedir repartidor (${restaurantName ?? restaurant?.name ?? restaurantId})`,
      }),
    })
    const pi = await piRes.json()

    if (!piRes.ok || pi.status !== 'succeeded') {
      const code = pi?.error?.code === 'authentication_required'
        ? 'requiere_verificacion'
        : 'cobro_fallido'
      return new Response(JSON.stringify({
        error: pi.error?.message ?? 'No se pudo cobrar la tarjeta.',
        code,
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: call, error: insertError } = await admin
      .from('rider_calls')
      .insert({
        restaurant_id: restaurantId,
        restaurant_name: restaurantName ?? restaurant?.name ?? '',
        payment_intent_id: pi.id,
        payment_status: 'cobrado',
        amount_fee: AMOUNT_FEE_MXN,
        amount_envio: AMOUNT_ENVIO_MXN,
      })
      .select('id')
      .single()

    if (insertError || !call) {
      // El cobro ya se hizo pero la fila no se pudo crear — se reembolsa de
      // inmediato para no dejar dinero cobrado sin ninguna llamada real.
      await fetch('https://api.stripe.com/v1/refunds', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({ payment_intent: pi.id }),
      })
      return new Response(JSON.stringify({ error: 'No se pudo crear la llamada, se reembolsó el cobro.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ id: call.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
