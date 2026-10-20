// Supabase Edge Function — arma una sesión de Stripe Checkout (suscripción
// mensual) para que un dueño pague GOGO Premium. Antes de esto, "Disponible
// con GOGO Premium" era solo una etiqueta sin ningún botón real de pago —
// Premium se prendía a mano por SQL. Ahora el dueño paga de verdad y el
// webhook de Stripe (stripe-webhook) es quien prende/apaga is_premium según
// el estado real de su suscripción.
//
// Deploy: supabase functions deploy create-premium-checkout
// (SIN --no-verify-jwt: solo la llama la app ya logueada)
//
// body: { restaurantId: string, successUrl?: string, cancelUrl?: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// $99 MXN/mes — en centavos, como los espera Stripe.
const PREMIUM_PRICE_MXN_CENTS = 9900

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

    const { restaurantId, successUrl, cancelUrl } = await req.json()
    if (!restaurantId) {
      return new Response(JSON.stringify({ error: 'Falta restaurantId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Quien llama debe ser el dueño de ESTE restaurante — nunca se confía
    // en el restaurantId que mande el cliente sin cruzarlo contra su JWT.
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

    const { data: restaurant } = await admin
      .from('restaurants')
      .select('id, name, stripe_customer_id')
      .eq('id', restaurantId)
      .maybeSingle()
    if (!restaurant) {
      return new Response(JSON.stringify({ error: 'Restaurante no encontrado' }), {
        status: 404,
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

    let customerId = restaurant.stripe_customer_id as string | null

    // Reusa el mismo Customer de Stripe si ya pagó/intentó pagar antes —
    // así su historial de facturas queda junto en vez de duplicarse.
    if (!customerId) {
      const custRes = await fetch('https://api.stripe.com/v1/customers', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          name: restaurant.name as string,
          'metadata[restaurant_id]': restaurant.id as string,
        }),
      })
      const customer = await custRes.json()
      if (!custRes.ok) {
        return new Response(
          JSON.stringify({ error: customer.error?.message ?? 'No se pudo crear el cliente en Stripe' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      customerId = customer.id
      await admin.from('restaurants').update({ stripe_customer_id: customerId }).eq('id', restaurant.id)
    }

    const body = new URLSearchParams({
      mode: 'subscription',
      customer: customerId!,
      success_url: successUrl ?? 'https://gogo-food-web.vercel.app/dueno-login?premium=ok',
      cancel_url: cancelUrl ?? 'https://gogo-food-web.vercel.app/dueno-login?premium=cancelado',
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': 'mxn',
      'line_items[0][price_data][unit_amount]': String(PREMIUM_PRICE_MXN_CENTS),
      'line_items[0][price_data][recurring][interval]': 'month',
      'line_items[0][price_data][product_data][name]': 'GOGO Premium — suscripción mensual',
      'metadata[restaurant_id]': restaurant.id as string,
      'subscription_data[metadata][restaurant_id]': restaurant.id as string,
    })

    const sessionRes = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    })
    const session = await sessionRes.json()
    if (!sessionRes.ok) {
      return new Response(
        JSON.stringify({ error: session.error?.message ?? 'No se pudo crear la sesión de pago' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
