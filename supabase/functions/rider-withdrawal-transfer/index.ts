// Supabase Edge Function — Admin la llama al aprobar un retiro de
// repartidor_plus: transiciona el retiro (pendiente → en_proceso) y, si el
// repartidor ya terminó su registro con Stripe Connect, transfiere el
// dinero de verdad (Stripe) en vez de que Admin haga el SPEI a mano.
//
// También sirve para REINTENTAR un retiro que se quedó en 'en_proceso'
// (Stripe falló, o el registro bancario no estaba listo) — antes eso
// tronaba con transicion_invalida y no había forma de volver a intentar.
//
// Candados contra doble pago:
//   - El id de la transferencia se guarda en stripe_payout_id en cuanto
//     Stripe la acepta, ANTES de marcar 'completado'. Con eso lleno, un
//     reintento ya no vuelve a transferir, y el trigger
//     trg_block_cancel_after_transfer impide rechazar/cancelar el retiro
//     (que liberaría el saldo para cobrarlo otra vez).
//   - Idempotency-Key por retiro: aunque se perdiera la respuesta de
//     Stripe, reintentar devuelve la misma transferencia.
//
// Deploy: supabase functions deploy rider-withdrawal-transfer
// (SIN --no-verify-jwt: la autorización real la hace admin_transition_withdrawal
// / is_admin(), vía RPC con el JWT de quien llama)
//
// body: { withdrawalId: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { withdrawalId } = await req.json()
    if (!withdrawalId) return json({ error: 'Falta withdrawalId' }, 400)

    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: withdrawal } = await admin
      .from('rider_withdrawals')
      .select('id, status, amount, rider_id, stripe_payout_id')
      .eq('id', withdrawalId)
      .maybeSingle()
    if (!withdrawal) return json({ error: 'retiro_no_encontrado' }, 404)

    if (withdrawal.status === 'pendiente') {
      // Este RPC exige is_admin() y la transición válida pendiente→en_proceso
      // por sí solo — si quien llama no es Admin, truena aquí y nunca se
      // llega a tocar Stripe.
      const { error: approveError } = await callerClient.rpc('admin_transition_withdrawal', {
        p_withdrawal_id: withdrawalId,
        p_new_status: 'en_proceso',
      })
      if (approveError) return json({ error: approveError.message }, 400)
    } else if (withdrawal.status === 'en_proceso') {
      // Reintento: no hay transición que haga el chequeo de Admin, se hace aquí.
      const { data: isAdmin } = await callerClient.rpc('is_admin')
      if (isAdmin !== true) return json({ error: 'no_autorizado' }, 403)
    } else {
      return json({ error: `Este retiro ya está ${withdrawal.status}` }, 409)
    }

    let transferId = withdrawal.stripe_payout_id as string | null
    if (!transferId) {
      const { data: payoutAccount } = await admin
        .from('rider_payout_accounts')
        .select('stripe_connect_account_id, stripe_onboarding_status')
        .eq('rider_id', withdrawal.rider_id)
        .maybeSingle()

      const acctId = payoutAccount?.stripe_connect_account_id
      if (!acctId || payoutAccount?.stripe_onboarding_status !== 'completed') {
        // Se queda en 'en_proceso' — Admin puede reintentar cuando termine
        // el registro, o completarlo a mano si ya pagó por otro medio.
        return json({
          error: 'El repartidor no ha terminado su registro bancario con Stripe. Pídele que lo complete desde "Retiros" en su app, o márcalo como completado a mano si ya le pagaste por otro medio.',
          approved: true,
        }, 409)
      }

      const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
      if (!stripeSecretKey) return json({ error: 'Stripe no configurado', approved: true }, 500)

      const stripeRes = await fetch('https://api.stripe.com/v1/transfers', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Idempotency-Key': `withdrawal-${withdrawalId}`,
        },
        body: new URLSearchParams({
          amount: String(Math.round(Number(withdrawal.amount) * 100)),
          currency: 'mxn',
          destination: acctId,
          'metadata[withdrawalId]': withdrawalId,
        }).toString(),
      })
      const transfer = await stripeRes.json()
      if (!stripeRes.ok) {
        return json({ error: transfer.error?.message ?? 'Error de Stripe', approved: true }, 400)
      }

      transferId = transfer.id as string
      await admin.from('rider_withdrawals')
        .update({ stripe_payout_id: transferId, stripe_payout_status: transfer.reversed ? 'reversed' : 'paid' })
        .eq('id', withdrawalId)
    }

    const { data: finalRow, error: completeError } = await callerClient.rpc('admin_transition_withdrawal', {
      p_withdrawal_id: withdrawalId,
      p_new_status: 'completado',
      p_transaction_reference: transferId,
      p_admin_notes: 'Pagado automáticamente vía Stripe Connect',
    })
    if (completeError) {
      // La transferencia SÍ se hizo y quedó guardada — reintentar solo
      // termina de marcarlo, no vuelve a transferir.
      return json({
        error: `Dinero transferido (${transferId}) pero no se pudo marcar como completado: ${completeError.message}. Puedes reintentar sin riesgo de pagar doble.`,
        approved: true,
        transferred: true,
      }, 500)
    }

    return json({ ok: true, withdrawal: finalRow, transferId })
  } catch (e) {
    return json({ error: String(e instanceof Error ? e.message : e) }, 500)
  }
})
