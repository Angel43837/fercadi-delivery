// Supabase Edge Function — Admin la llama al aprobar un retiro de
// restaurante: transiciona el retiro (pendiente → en_proceso) y, si el
// restaurante ya terminó su registro con Stripe Connect, transfiere el
// dinero de verdad (Stripe). Mismo patrón que rider-withdrawal-transfer.
//
// Deploy: supabase functions deploy restaurant-withdrawal-transfer
// (SIN --no-verify-jwt: la autorización real la hace
// admin_transition_restaurant_withdrawal, vía RPC con el JWT de quien llama)
//
// body: { withdrawalId: string }

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
    const { withdrawalId } = await req.json()
    if (!withdrawalId) {
      return new Response(JSON.stringify({ error: 'Falta withdrawalId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: rowAfterApprove, error: approveError } = await callerClient.rpc('admin_transition_restaurant_withdrawal', {
      p_withdrawal_id: withdrawalId,
      p_new_status: 'en_proceso',
    })
    if (approveError) {
      return new Response(JSON.stringify({ error: approveError.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: payoutAccount } = await admin
      .from('restaurant_payout_accounts')
      .select('stripe_connect_account_id, stripe_onboarding_status')
      .eq('restaurant_id', rowAfterApprove.restaurant_id)
      .maybeSingle()

    const acctId = payoutAccount?.stripe_connect_account_id
    if (!acctId || payoutAccount?.stripe_onboarding_status !== 'completed') {
      return new Response(JSON.stringify({
        error: 'El restaurante no ha terminado su registro bancario con Stripe. Pídele que lo complete desde "Retiros" en su panel, o márcalo como completado a mano si ya le pagaste por otro medio.',
        approved: true,
      }), {
        status: 409,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: 'Stripe no configurado', approved: true }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const transferBody = new URLSearchParams({
      amount: String(Math.round(Number(rowAfterApprove.amount) * 100)),
      currency: 'mxn',
      destination: acctId,
      'metadata[withdrawalId]': withdrawalId,
    })

    const stripeRes = await fetch('https://api.stripe.com/v1/transfers', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': `restaurant-withdrawal-${withdrawalId}`,
      },
      body: transferBody.toString(),
    })
    const transfer = await stripeRes.json()

    if (!stripeRes.ok) {
      return new Response(JSON.stringify({ error: transfer.error?.message ?? 'Error de Stripe', approved: true }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: finalRow, error: completeError } = await callerClient.rpc('admin_transition_restaurant_withdrawal', {
      p_withdrawal_id: withdrawalId,
      p_new_status: 'completado',
      p_transaction_reference: transfer.id,
      p_admin_notes: 'Pagado automáticamente vía Stripe Connect',
    })
    if (completeError) {
      await admin.from('restaurant_withdrawals')
        .update({ stripe_payout_id: transfer.id, stripe_payout_status: transfer.reversed ? 'reversed' : 'paid' })
        .eq('id', withdrawalId)
      return new Response(JSON.stringify({ error: `Dinero transferido (${transfer.id}) pero no se pudo actualizar el estatus: ${completeError.message}`, approved: true, transferred: true }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    await admin.from('restaurant_withdrawals')
      .update({ stripe_payout_id: transfer.id, stripe_payout_status: transfer.reversed ? 'reversed' : 'paid' })
      .eq('id', withdrawalId)

    return new Response(JSON.stringify({ ok: true, withdrawal: finalRow, transferId: transfer.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e instanceof Error ? e.message : e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
