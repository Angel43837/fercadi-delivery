// Supabase Edge Function — envía push notification real vía FCM v1 (HTTP v1
// API), que reemplaza a la legacy API (fcm.googleapis.com/fcm/send),
// descontinuada por Google en junio 2024.
//
// FCM v1 no usa una "server key" fija — se autentica con OAuth2 usando una
// cuenta de servicio de Firebase (un JSON con client_email/private_key).
// Esta función firma su propio JWT y lo cambia por un access token en cada
// llamada (dura 1h, no se cachea entre invocaciones porque cada una es un
// proceso/isolate nuevo).
//
// Deploy: supabase functions deploy send-order-notification
// Requiere el secreto: FCM_SERVICE_ACCOUNT_JSON
//   (Firebase Console → Configuración del proyecto → Cuentas de servicio →
//   Generar nueva clave privada → pegar el JSON completo tal cual)
//   supabase secrets set FCM_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// Convierte una clave privada PEM (formato del JSON de Firebase) en una
// CryptoKey utilizable por Web Crypto (disponible nativamente en Deno).
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    binary,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let str = '';
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Firma un JWT de cuenta de servicio y lo cambia por un access token OAuth2
// con el scope de FCM — mismo flujo que usa cualquier SDK server-side de
// Google, hecho a mano porque Deno Edge Functions no trae el SDK completo.
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`No se pudo obtener access token: ${JSON.stringify(data)}`);
  return data.access_token as string;
}

// Texto de cada aviso, fijo en el servidor — antes la app mandaba token,
// título y cuerpo libres, y cualquiera con la anon key podía mandar
// cualquier push a cualquier teléfono.
const MESSAGES: Record<string, [string, string]> = {
  accepted: ['🍳 ¡Pedido aceptado!', 'Tu pedido está siendo preparado.'],
  delivering: ['🛵 ¡Repartidor en camino!', 'Tu pedido ya viene para acá.'],
  delivered: ['✅ ¡Pedido entregado!', '¡Buen provecho!'],
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Solo usuarios con sesión, y solo sobre un pedido donde participan
    // (repartidor asignado, dueño del restaurante o admin).
    const authHeader = req.headers.get('Authorization') ?? '';
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: callerData } = await callerClient.auth.getUser();
    const caller = callerData?.user;
    if (!caller) return json({ error: 'No autenticado' }, 401);

    const { orderId } = await req.json() as { orderId: string };
    if (!orderId) return json({ error: 'Falta orderId' }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );
    const { data: order } = await admin
      .from('orders')
      // '*' y no la columna por nombre: orders.client_fcm_token todavía no
      // existe (FCM sigue sin configurarse) y pedirla haría tronar la consulta.
      .select('*')
      .eq('id', orderId)
      .maybeSingle();
    if (!order) return json({ error: 'Pedido no encontrado' }, 404);

    const isAdmin = caller.email === 'admin@fercadi.com';
    const isRider = order.repartidor_id === caller.id;
    const isOwner = caller.app_metadata?.role === 'dueno' &&
      caller.app_metadata?.restaurant_id === order.restaurant_id;
    if (!isAdmin && !isRider && !isOwner) return json({ error: 'No autorizado' }, 403);

    const message = MESSAGES[order.status as string];
    const token = (order.client_fcm_token ?? null) as string | null;
    if (!message || !token) return json({ sent: false });
    const [title, body] = message;

    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!raw) return json({ error: 'No FCM_SERVICE_ACCOUNT_JSON' }, 500);
    const sa = JSON.parse(raw) as ServiceAccount;
    const accessToken = await getAccessToken(sa);

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            apns: { payload: { aps: { sound: 'default' } } },
            android: { priority: 'high' },
          },
        }),
      },
    );

    const result = await fcmRes.json();
    return json(result, fcmRes.status);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
