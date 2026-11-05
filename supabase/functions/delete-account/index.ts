// Supabase Edge Function — borra la cuenta del usuario que llama (cliente,
// repartidor o dueño), bloqueador real para publicar en App Store/Play
// Store (ambas exigen un flujo de eliminación de cuenta DENTRO de la app).
//
// La lógica de negocio (candados de "retiro en proceso"/"pedidos activos"
// + anonimización del restaurante del dueño) vive en el RPC de Postgres
// `delete_my_account()` (ver supabase/migrations/20261026000000_account_deletion.sql)
// — aquí solo se verifica identidad, se invoca ese RPC con el JWT del
// propio usuario (para que auth.uid() adentro resuelva bien) y, SOLO si no
// lanzó excepción, se borra la cuenta de auth.users con la Admin API.
//
// Se usa la Admin API (admin.auth.admin.deleteUser), no un
// `DELETE FROM auth.users` en SQL, porque es la vía oficialmente soportada
// por GoTrue — limpia también identities/sessions/refresh_tokens/factores
// MFA de forma consistente, sin depender de que cada tabla de auth.* tenga
// el ON DELETE CASCADE correcto.
//
// Deploy: supabase functions deploy delete-account
// (SIN --no-verify-jwt: solo la llama el propio usuario ya logueado)
//
// body: {} (no necesita nada — actúa sobre quien manda el JWT)
// respuesta éxito: { ok: true }
// respuesta bloqueado/error: { error: '<mensaje exacto para mostrar al usuario>' }

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

    // 1. Verifica quién llama con su PROPIO JWT (anon client) — mismo
    // patrón que restaurant-payment-method. Este mismo cliente se reusa
    // para invocar el RPC, así auth.uid() adentro de delete_my_account()
    // resuelve exactamente a esta persona (no a service_role).
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

    // 2. Candados + anonimización (ver migración) — si cualquiera de los
    // dos refusals aplica, esto lanza y nada se borra ni se modifica (todo
    // corre dentro de una sola transacción en Postgres).
    const { error: rpcError } = await userClient.rpc('delete_my_account')
    if (rpcError) {
      // El mensaje de `raise exception '<texto>'` en Postgres llega tal
      // cual en rpcError.message — se lo regresamos íntegro al usuario, no
      // un genérico, para que sepa exactamente por qué se bloqueó.
      return new Response(JSON.stringify({ error: rpcError.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. Solo si el RPC no fue bloqueado: borra la cuenta de verdad con la
    // Admin API (requiere service_role, nunca expuesta al cliente).
    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // La fila de `drivers` se borra sola al borrar auth.users (FK ON DELETE
    // CASCADE), pero los ARCHIVOS reales en el bucket privado
    // `identificaciones` (INE frente/reverso, comprobante de domicilio) no
    // se cascadean nunca — se quedarían huérfanos en Storage para siempre,
    // justo el tipo de dato más sensible que la cuenta tiene. Se borran
    // aquí, antes de borrar la cuenta, con service_role (el bucket es
    // privado — ni el propio dueño puede borrarlos directo).
    const { data: driver } = await admin
      .from('drivers')
      .select('id_front_path, id_back_path, proof_of_address_path')
      .eq('id', user.id)
      .maybeSingle()
    if (driver) {
      const paths = [driver.id_front_path, driver.id_back_path, driver.proof_of_address_path]
        .filter((p): p is string => typeof p === 'string' && p.length > 0)
      if (paths.length > 0) {
        await admin.storage.from('identificaciones').remove(paths)
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
    if (deleteError) {
      return new Response(
        JSON.stringify({ error: `No se pudo eliminar la cuenta: ${deleteError.message}` }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
