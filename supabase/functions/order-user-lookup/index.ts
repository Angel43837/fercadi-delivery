// Supabase Edge Function — permite que el cliente y el repartidor de UN
// mismo pedido vean el nombre/foto del otro (como en Uber). La service_role
// key vive SOLO aquí, nunca en la app — y a diferencia de admin-user-lookup
// (solo para Admin), aquí cualquier usuario autenticado puede llamarla, pero
// SOLO para ver a su contraparte en un pedido donde de verdad participa:
// se verifica que quien llama sea el customer_id o el repartidor_id de ese
// pedido exacto, y que el perfil pedido sea el del otro lado, no cualquiera.
//
// Deploy: supabase functions deploy order-user-lookup
// (SIN --no-verify-jwt: requiere sesión real de cliente o repartidor)
//
// body: { orderId: string, targetUserId: string }

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
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    const callerId = callerData?.user?.id
    if (!callerId) {
      return new Response(JSON.stringify({ error: 'No autenticado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { orderId, targetUserId } = await req.json()
    if (!orderId || !targetUserId) {
      return new Response(JSON.stringify({ error: 'Falta orderId o targetUserId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Confirma que quien llama de verdad participa en ese pedido, y que
    // el perfil solicitado es el de la OTRA parte (no cualquier usuario).
    const { data: order, error: orderError } = await admin
      .from('orders')
      .select('customer_id, repartidor_id')
      .eq('id', orderId)
      .single()
    if (orderError || !order) {
      return new Response(JSON.stringify({ error: 'Pedido no encontrado' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const isCustomerCallingForRider = callerId === order.customer_id && targetUserId === order.repartidor_id
    const isRiderCallingForCustomer = callerId === order.repartidor_id && targetUserId === order.customer_id
    if (!isCustomerCallingForRider && !isRiderCallingForCustomer) {
      return new Response(JSON.stringify({ error: 'No autorizado para ver este perfil' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data, error } = await admin.auth.admin.getUserById(targetUserId)
    if (error) throw error
    const meta = data.user?.user_metadata ?? {}

    // Si el cliente está consultando a SU repartidor, se incluyen también
    // sus repartos/nivel (público, para las medallas) — nunca coins ni
    // dinero (privado, es su cuenta/ganancias).
    let repartos: number | null = null
    let nivel: number | null = null
    if (isCustomerCallingForRider) {
      const { data: stats } = await admin
        .from('rider_stats')
        .select('repartos, nivel')
        .eq('rider_id', targetUserId)
        .maybeSingle()
      repartos = stats?.repartos ?? 0
      nivel = stats?.nivel ?? 1
    }

    return new Response(
      JSON.stringify({
        // Distintas pantallas guardan el nombre/foto con keys distintas
        // (repartidor de flota vs. repartidor plus vs. cliente) — se
        // revisan todas las variantes conocidas.
        name: meta.custom_name ?? meta.name ?? meta.full_name ?? null,
        avatarUrl: meta.custom_avatar_url ?? meta.avatar_url ?? meta.picture ?? null,
        repartos,
        nivel,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
