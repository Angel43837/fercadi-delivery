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

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { token, title, body } = await req.json() as {
      token: string;
      title: string;
      body: string;
    };
    if (!token) {
      return new Response(JSON.stringify({ error: 'No token' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!raw) {
      return new Response(JSON.stringify({ error: 'No FCM_SERVICE_ACCOUNT_JSON' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
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
    return new Response(JSON.stringify(result), {
      status: fcmRes.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
