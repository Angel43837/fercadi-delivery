// Supabase Edge Function — recibe eventos de Stripe (webhook) para confirmar
// pagos asíncronos (OXXO Pay). El pago con tarjeta ya se confirma al instante
// en la app (PaymentSheet), así que este webhook solo importa para OXXO.
//
// Deploy: supabase functions deploy stripe-webhook --no-verify-jwt
// (--no-verify-jwt porque Stripe llama a esta URL sin el JWT de Supabase)
//
// Configuración manual necesaria en el Dashboard de Stripe:
//   Developers → Webhooks → Add endpoint
//   URL: https://<tu-proyecto>.supabase.co/functions/v1/stripe-webhook
//   Eventos a escuchar: payment_intent.succeeded, payment_intent.payment_failed, payment_intent.canceled
//   Copiar el "Signing secret" (empieza con whsec_...) y guardarlo como variable
//   de entorno STRIPE_WEBHOOK_SECRET en Supabase → Edge Functions → Secrets.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
}

// Verifica la firma del webhook sin depender del SDK completo de Stripe
// (Stripe-Signature: t=<timestamp>,v1=<hmac-sha256 hex>)
async function verifyStripeSignature(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(
    sigHeader.split(',').map((p) => p.split('=') as [string, string]),
  )
  const timestamp = parts['t']
  const signature = parts['v1']
  if (!timestamp || !signature) return false

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signedPayload = `${timestamp}.${payload}`
  const sigBytes = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signedPayload))
  const expected = Array.from(new Uint8Array(sigBytes))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')

  if (expected.length !== signature.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i)
  return diff === 0
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const sigHeader = req.headers.get('stripe-signature')
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')
  const rawBody = await req.text()

  if (!webhookSecret) {
    return new Response(JSON.stringify({ error: 'STRIPE_WEBHOOK_SECRET no configurado' }), { status: 500 })
  }
  if (!sigHeader || !(await verifyStripeSignature(rawBody, sigHeader, webhookSecret))) {
    return new Response(JSON.stringify({ error: 'Firma inválida' }), { status: 400 })
  }

  const event = JSON.parse(rawBody)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  try {
    const intent = event.data?.object
    const paymentIntentId = intent?.id

    if (paymentIntentId) {
      let newStatus: string | null = null
      if (event.type === 'payment_intent.succeeded') newStatus = 'paid'
      else if (event.type === 'payment_intent.payment_failed') newStatus = 'failed'
      else if (event.type === 'payment_intent.canceled') newStatus = 'failed'

      if (newStatus) {
        await supabase
          .from('orders')
          .update({ payment_status: newStatus })
          .eq('stripe_payment_intent_id', paymentIntentId)
      }
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
