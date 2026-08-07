// Supabase Edge Function — consulta o suspende cuentas de auth.users para el
// módulo "Reseñas" del panel de Admin. La service_role key vive SOLO aquí
// (variable de entorno), nunca dentro de la app de Admin — meterla en el
// binario sería un riesgo real (cualquiera podría extraerla y tener acceso
// total a la base de datos).
//
// Deploy: supabase functions deploy admin-user-lookup
// (SIN --no-verify-jwt: solo la llama la app de Admin, ya logueada)
//
// body: { action: 'lookup' | 'ban' | 'unban', userId: string }

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

    // Verifica que quien llama sea un admin real, usando el JWT que ya
    // Supabase validó para llegar hasta aquí (no se puede falsificar el rol).
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: callerData } = await callerClient.auth.getUser()
    const role = callerData?.user?.app_metadata?.role ?? callerData?.user?.user_metadata?.role
    if (role !== 'admin') {
      return new Response(JSON.stringify({ error: 'No autorizado' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { action, userId } = await req.json()
    if (!userId) {
      return new Response(JSON.stringify({ error: 'Falta userId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    if (action === 'ban' || action === 'unban') {
      const { error } = await admin.auth.admin.updateUserById(userId, {
        ban_duration: action === 'ban' ? '876000h' : 'none',
      })
      if (error) throw error
      return new Response(JSON.stringify({ ok: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // action === 'lookup' (default)
    const { data, error } = await admin.auth.admin.getUserById(userId)
    if (error) throw error
    const user = data.user
    const provider = user?.identities?.[0]?.provider ?? 'email'
    const bannedUntil = user?.banned_until ?? null
    const isBanned = !!bannedUntil && new Date(bannedUntil).getTime() > Date.now()

    return new Response(
      JSON.stringify({
        email: user?.email ?? null,
        createdAt: user?.created_at ?? null,
        provider,
        banned: isBanned,
        avatarUrl: user?.user_metadata?.avatar_url ?? null,
        name: user?.user_metadata?.name ?? null,
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
