// Supabase Edge Function — abre el "Billing Portal" hospedado por Stripe
// para que un dueño Premium vea/cancele su propia suscripción sin que
// tengamos que construir esa pantalla (y su lógica de cancelación) a mano.
//
// Deploy: supabase functions deploy create-billing-portal-session
//
// body: { restaurantId: string, returnUrl?: string }

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
    const user = userData?.user
    if (!user) {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { restaurantId, returnUrl } = await req.json()
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
    const { data: restaurant } = await admin
      .from('restaurants')
      .select('stripe_customer_id')
      .eq('id', restaurantId)
      .maybeSingle()

    if (!restaurant?.stripe_customer_id) {
      return new Response(JSON.stringify({ error: 'Este restaurante todavía no tiene una suscripción' }), {
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

    const portalRes = await fetch('https://api.stripe.com/v1/billing_portal/sessions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        customer: restaurant.stripe_customer_id as string,
        return_url: returnUrl ?? 'https://gogo-food-web.vercel.app/dueno-login',
      }),
    })
    const portal = await portalRes.json()
    if (!portalRes.ok) {
      return new Response(
        JSON.stringify({ error: portal.error?.message ?? 'No se pudo abrir el portal de facturación' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(JSON.stringify({ url: portal.url }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
