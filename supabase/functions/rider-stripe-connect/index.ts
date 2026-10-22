// Supabase Edge Function — alta y estado de la cuenta de Stripe Connect
// (Express) de un repartidor_plus, para que su retiro se pague de verdad
// por Stripe en vez de que Admin haga la transferencia SPEI a mano.
//
// Deploy: supabase functions deploy rider-stripe-connect
// (SIN --no-verify-jwt: solo la llama un repartidor ya logueado, sobre su
// propia cuenta — el rider_id nunca lo manda el cliente, se lee de su JWT)
//
// body: { action: 'onboard' } | { action: 'status' }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Página neutral a la que Stripe redirige al terminar/reintentar el
// registro — no se depende de ella para saber si terminó (eso se resuelve
// con 'status' cuando el repartidor vuelve a la app), solo evita dejarlo
// viendo una URL en blanco.
const RETURN_URL = 'https://gogo-food-web.vercel.app'
// Versión preview documentada por Stripe para Accounts v2 al momento de
// escribir esto — si Stripe la retira, el error de la API dice cuál usar.
const STRIPE_V2_VERSION = '2026-09-30.preview'

async function stripeV2Fetch(path: string, method: string, secretKey: string, body?: Record<string, unknown>) {
  const res = await fetch(`https://api.stripe.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Stripe-Version': STRIPE_V2_VERSION,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error?.message ?? 'Error de Stripe');
  return json
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    const rider = callerData?.user
    if (!rider) {
      return new Response(JSON.stringify({ error: 'No autenticado' }), {
        status: 401,
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

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { action } = await req.json()

    const { data: account } = await admin
      .from('rider_payout_accounts')
      .select('stripe_connect_account_id, stripe_onboarding_status')
      .eq('rider_id', rider.id)
      .maybeSingle()

    if (action === 'status') {
      let status = account?.stripe_onboarding_status ?? 'not_started'
      const acctId = account?.stripe_connect_account_id
      let debugInfo: Record<string, unknown> | undefined
      if (acctId) {
        // Se vuelve a preguntar a Stripe directo (no se confía en el valor
        // guardado) — es la única forma real de saber si ya pasó la
        // verificación o sigue pendiente, sin webhook configurado.
        const acct = await stripeV2Fetch(
          `/v2/core/accounts/${acctId}?include[0]=configuration.recipient&include[1]=requirements`, 'GET', stripeSecretKey,
        )
        const cap = acct.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers
        status = cap?.status === 'active' ? 'completed' : 'pending'
        debugInfo = {
          capability_status: cap?.status ?? null,
          capability_status_details: cap?.status_details ?? null,
          requirements: acct.requirements ?? null,
        }
        if (status !== account?.stripe_onboarding_status) {
          await admin.from('rider_payout_accounts')
            .update({ stripe_onboarding_status: status, updated_at: new Date().toISOString() })
            .eq('rider_id', rider.id)
        }
      }
      return new Response(JSON.stringify({ status, debugInfo }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'onboard') {
      let acctId = account?.stripe_connect_account_id

      if (!acctId) {
        const displayName = (rider.user_metadata?.custom_name ?? rider.user_metadata?.full_name ?? rider.user_metadata?.name ?? rider.email) as string
        const acct = await stripeV2Fetch('/v2/core/accounts', 'POST', stripeSecretKey, {
          contact_email: rider.email ?? '',
          display_name: displayName,
          defaults: {
            responsibilities: { fees_collector: 'application', losses_collector: 'application' },
          },
          dashboard: 'express',
          identity: { country: 'mx' },
          configuration: {
            recipient: {
              capabilities: { stripe_balance: { stripe_transfers: { requested: true } } },
            },
          },
        })
        acctId = acct.id as string
        await admin.from('rider_payout_accounts').upsert({
          rider_id: rider.id,
          stripe_connect_account_id: acctId,
          stripe_onboarding_status: 'pending',
        })
      }

      const link = await stripeV2Fetch('/v2/core/account_links', 'POST', stripeSecretKey, {
        account: acctId,
        use_case: {
          type: 'account_onboarding',
          account_onboarding: { refresh_url: RETURN_URL, return_url: RETURN_URL },
        },
      })
      return new Response(JSON.stringify({ url: link.url }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ error: 'Acción no reconocida' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e instanceof Error ? e.message : e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
