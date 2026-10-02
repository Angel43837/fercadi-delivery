// Supabase Edge Function — consulta o suspende cuentas de auth.users para el
// módulo "Reseñas" del panel de Admin. La service_role key vive SOLO aquí
// (variable de entorno), nunca dentro de la app de Admin — meterla en el
// binario sería un riesgo real (cualquiera podría extraerla y tener acceso
// total a la base de datos).
//
// Deploy: supabase functions deploy admin-user-lookup
// (SIN --no-verify-jwt: solo la llama la app de Admin, ya logueada)
//
// body: { action: 'lookup' | 'ban' | 'unban' | 'driverDocs', userId: string }
//     | { action: 'listByRole', role: string }

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

    const { action, userId, role: targetRole } = await req.json()

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Lista TODAS las cuentas de un rol (cliente/repartidor/repartidor_plus),
    // tengan o no pedidos — antes "Clientes y repartidores" en Admin solo
    // mostraba cuentas que ya habían hecho al menos un pedido, armado desde
    // la tabla orders, así que una cuenta recién creada sin pedidos
    // simplemente no aparecía en ningún lado.
    if (action === 'listByRole') {
      if (!targetRole) {
        return new Response(JSON.stringify({ error: 'Falta role' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const roles = Array.isArray(targetRole) ? targetRole : [targetRole]
      const matches: Record<string, unknown>[] = []
      let page = 1
      const perPage = 200
      while (true) {
        const { data, error } = await admin.auth.admin.listUsers({ page, perPage })
        if (error) throw error
        for (const u of data.users) {
          const r = u.app_metadata?.role ?? u.user_metadata?.role
          // Un cliente normal no tiene role guardado en absoluto (solo
          // dueño/repartidor/repartidor_plus/admin lo tienen) — 'cliente'
          // es un valor que nunca existe de verdad en la base, así que se
          // usa aquí como marcador para "cualquier cuenta sin role".
          const isMatch = r ? roles.includes(r) : roles.includes('cliente')
          if (isMatch) {
            matches.push({
              id: u.id,
              email: u.email ?? null,
              name: u.user_metadata?.name ?? null,
              avatarUrl: u.user_metadata?.avatar_url ?? null,
              phone: u.phone || u.user_metadata?.phone || null,
              createdAt: u.created_at ?? null,
            })
          }
        }
        if (data.users.length < perPage) break
        page += 1
      }
      return new Response(JSON.stringify({ users: matches }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!userId) {
      return new Response(JSON.stringify({ error: 'Falta userId' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Datos del registro web de un repartidor (vehículo, ciudad, tipo de
    // identificación) + enlaces temporales a sus documentos — el bucket
    // "identificaciones" es privado a propósito (identificación oficial y
    // comprobante de domicilio son datos sensibles), así que solo
    // service_role puede firmar URLs para verlos, ni siquiera Admin desde
    // el cliente puede leerlos directo.
    if (action === 'driverDocs') {
      const { data: driver, error: driverError } = await admin
        .from('drivers')
        .select(
          'first_name, last_name, phone, email, city, state, vehicle, id_type, ' +
            'id_front_path, id_back_path, proof_of_address_path, photo_url, status, created_at',
        )
        .eq('id', userId)
        .maybeSingle()
      if (driverError) throw driverError
      if (!driver) {
        return new Response(JSON.stringify({ driver: null }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const sign = async (path: string | null) => {
        if (!path) return null
        const { data, error } = await admin.storage
          .from('identificaciones')
          .createSignedUrl(path, 600) // 10 minutos
        if (error) return null
        return data.signedUrl
      }
      const [idFrontUrl, idBackUrl, proofUrl] = await Promise.all([
        sign(driver.id_front_path),
        sign(driver.id_back_path),
        sign(driver.proof_of_address_path),
      ])

      return new Response(
        JSON.stringify({ driver: { ...driver, idFrontUrl, idBackUrl, proofUrl } }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

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
