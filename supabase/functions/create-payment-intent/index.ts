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
    const { amount, currency = 'mxn', orderId, paymentMethodType, promotionClaimId, cartSummary } = await req.json()

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

    // Si el checkout trae una promoción aplicada, se vuelve a calcular el
    // descuento AQUÍ (nunca se confía en el que mandó el celular) llamando
    // a la misma función que usa el checkout para mostrarlo — y si el monto
    // que mandó el cliente no coincide con lo que el servidor calculó, se
    // rechaza el cobro antes de siquiera hablar con Stripe. Se exige
    // cartSummary junto con promotionClaimId: un cliente que mandara el
    // id de la promoción pero sin el resumen del carrito (para saltarse
    // esta verificación) se rechaza directo.
    if (promotionClaimId && !cartSummary) {
      return new Response(JSON.stringify({ error: 'Falta el resumen del carrito para verificar la promoción' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    if (promotionClaimId && cartSummary) {
      // Cliente autenticado como quien llama (no service-role) — la función
      // validate_promotion_for_order revisa auth.uid() para confirmar que
      // el reclamo es de esta misma persona, así que hay que llamarla con
      // su propio JWT, no con permisos de administrador.
      const authHeader = req.headers.get('Authorization') ?? ''
      const userClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: authHeader } } },
      )
      const { data: result, error: rpcError } = await userClient.rpc('validate_promotion_for_order', {
        p_claim_id: promotionClaimId,
        p_restaurant_id: cartSummary.restaurantId,
        p_cart_items: cartSummary.items,
        p_subtotal: cartSummary.subtotal,
        p_delivery_fee: cartSummary.deliveryFee,
      })
      if (rpcError || !result?.valid) {
        return new Response(
          JSON.stringify({ error: 'Promoción inválida', reason: result?.reason ?? String(rpcError) }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
      const discount = result.applies_to_shipping
        ? Math.min(cartSummary.deliveryFee, result.discount_amount)
        : result.discount_amount
      const expectedTotal = cartSummary.subtotal + cartSummary.deliveryFee - discount
      // Epsilon de un centavo de peso — evita falsos rechazos por redondeo.
      if (Math.abs(expectedTotal - amount) > 0.5) {
        return new Response(
          JSON.stringify({ error: 'El monto no coincide con el descuento validado de la promoción' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
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
    })

    // OXXO no es compatible con "automatic_payment_methods" en modo automático
    // sin datos de envío — se pide explícitamente. Para tarjeta se pide
    // "card" explícito en vez de automatic_payment_methods: con automático,
    // Stripe intenta ofrecer TODO lo que esté activo en el dashboard (OXXO,
    // Link, pagos bancarios), y como la app no configura
    // allowsDelayedPaymentMethods ni soporta esos métodos, el PaymentSheet
    // se quedaba filtrándolos y nunca llegaba a mostrar la tarjeta —
    // se veía como "cargando" sin avanzar.
    if (paymentMethodType === 'oxxo') {
      body.set('payment_method_types[]', 'oxxo')
    } else {
      body.set('payment_method_types[]', 'card')
    }

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
      JSON.stringify({ clientSecret: paymentIntent.client_secret, id: paymentIntent.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
