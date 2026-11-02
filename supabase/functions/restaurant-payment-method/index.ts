// Supabase Edge Function — guarda/consulta la tarjeta con la que se le
// cobra al restaurante por "Pedir un repartidor" desde la app de escritorio.
// Es un Customer/tarjeta COMPLETAMENTE APARTE de su cuenta de Stripe
// Connect (esa es para que A ÉL le paguen sus ventas; esta es para que ÉL
// pague, mismo patrón que create-premium-checkout pero en modo 'setup').
//
// Deploy: supabase functions deploy restaurant-payment-method
// (SIN --no-verify-jwt: solo la llama el dueño ya logueado)
//
// body: { action: 'setup', restaurantId, successUrl?, cancelUrl? }
//     | { action: 'status', restaurantId }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// La URL de regreso de Stripe solo puede ser del sitio oficial — antes se
// aceptaba cualquiera del body (redirección abierta: después de guardar su
// tarjeta, el dueño podía terminar en un sitio ajeno).
const ALLOWED_RETURN_ORIGIN = 'https://pagina-web-gogo-rho.vercel.app/'
function safeReturnUrl(url: unknown, fallback: string): string {
  return typeof url === 'string' && url.startsWith(ALLOWED_RETURN_ORIGIN) ? url : fallback
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

    const { action, restaurantId, successUrl, cancelUrl } = await req.json()
    if (!restaurantId) {
      return new Response(JSON.stringify({ error: 'Falta restaurantId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // owns_restaurant() (app_metadata o restaurants.owner_id) — antes se
    // aceptaba user_metadata.restaurant_id, que cualquier usuario edita:
    // bastaba ponerse el id de otro restaurante para ver su tarjeta o
    // agregarle una.
    const { data: owns } = await userClient.rpc('owns_restaurant', { p_restaurant_id: restaurantId })
    if (owns !== true) {
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
    if (!restaurant) {
      return new Response(JSON.stringify({ error: 'Restaurante no encontrado' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let customerId = restaurant.stripe_customer_id as string | null

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

    if (action === 'status') {
      const pmRes = await fetch(
        `https://api.stripe.com/v1/payment_methods?customer=${customerId}&type=card&limit=1`,
        { headers: { Authorization: `Bearer ${stripeSecretKey}` } },
      )
      const pmList = await pmRes.json()
      const pm = pmList?.data?.[0]
      return new Response(JSON.stringify({
        hasCard: !!pm,
        brand: pm?.card?.brand ?? null,
        last4: pm?.card?.last4 ?? null,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup') {
      const body = new URLSearchParams({
        mode: 'setup',
        customer: customerId!,
        success_url: safeReturnUrl(successUrl, 'https://pagina-web-gogo-rho.vercel.app/pago-confirmado'),
        cancel_url: safeReturnUrl(cancelUrl, 'https://pagina-web-gogo-rho.vercel.app/?pago=cancelado'),
        'payment_method_types[0]': 'card',
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
    }

    return new Response(JSON.stringify({ error: 'Acción no reconocida' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
