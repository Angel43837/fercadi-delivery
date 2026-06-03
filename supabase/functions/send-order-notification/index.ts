// Supabase Edge Function — envía push notification via FCM
// Deploy: supabase functions deploy send-order-notification
// Requiere variable de entorno: FCM_SERVER_KEY (Firebase Console → Project Settings → Cloud Messaging → Server Key)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const FCM_URL = 'https://fcm.googleapis.com/fcm/send';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const { token, title, body } = await req.json() as {
      token: string;
      title: string;
      body:  string;
    };

    if (!token) return new Response(JSON.stringify({ error: 'No token' }), { status: 400 });

    const serverKey = Deno.env.get('FCM_SERVER_KEY');
    if (!serverKey) return new Response(JSON.stringify({ error: 'No FCM_SERVER_KEY' }), { status: 500 });

    const fcmRes = await fetch(FCM_URL, {
      method: 'POST',
      headers: {
        'Authorization': `key=${serverKey}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        to: token,
        priority: 'high',
        notification: { title, body, sound: 'default' },
        data:         { title, body },
      }),
    });

    const result = await fcmRes.json();
    return new Response(JSON.stringify(result), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
