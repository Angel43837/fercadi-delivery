import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { amount, currency = 'mxn', orderId } = await req.json()

    // Validar monto básico
    if (!amount || amount <= 0) {
      return new Response(JSON.stringify({ error: 'Monto inválido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Límite razonable: máximo $50,000 MXN por pedido
    if (amount > 50000) {
      return new Response(JSON.stringify({ error: 'Monto fuera de rango permitido' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Si viene orderId, verificar el monto real contra la BD para evitar manipulación
    let verifiedAmount = amount
    if (orderId) {
      try {
        const supabase = createClient(
          Deno.env.get('SUPABASE_URL') ?? '',
          Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        )
        const { data: order } = await supabase
          .from('orders')
          .select('total')
          .eq('id', orderId)
          .single()
        if (order?.total) {
          verifiedAmount = order.total
        }
      } catch (_) {
        // Si no se puede verificar, usar el monto del cliente pero con límite
      }
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: 'Stripe no configurado' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = new URLSearchParams({
      amount: String(Math.round(verifiedAmount * 100)), // Stripe usa centavos
      currency,
      'metadata[orderId]': orderId ?? '',
      'automatic_payment_methods[enabled]': 'true',
    })

    const stripeRes = await fetch('https://api.stripe.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body.toString(),
    })

    const paymentIntent = await stripeRes.json()

    if (!stripeRes.ok) {
      return new Response(JSON.stringify({ error: paymentIntent.error?.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ clientSecret: paymentIntent.client_secret }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
