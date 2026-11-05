import 'package:flutter/material.dart';

class AppConstants {
  // Default: GOGO-Pruebas (cuenta eloy41543), ya no la cuenta original de Angel.
  // Se puede sobreescribir al compilar con --dart-define=SUPABASE_URL=...
  // --dart-define=SUPABASE_ANON_KEY=... (por ejemplo para apuntar a gogo-food-dev
  // cuando esa quede lista con datos reales).
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ymztoayxzewghbethahv.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_eEimQboqykVjDWpnXG8VNQ_iVlNhgbo',
  );
  // GOGO Food compila con --dart-define=SUPABASE_URL=...dlukaxbcyetcdbdjjgct...;
  // Pruebas se queda en el default de arriba — así se puede diferenciar en
  // runtime sin agregar un flag nuevo, para cosas exclusivas de pruebas/QA.
  static const bool isPruebas = supabaseUrl == 'https://ymztoayxzewghbethahv.supabase.co';
  // Service role key — Settings > API > service_role en tu dashboard de Supabase
  static const String supabaseServiceRoleKey = '';

  // App Group de iOS (HomeWidget, para pasarle datos al widget de
  // seguimiento) — antes fijo a "group.com.fercadi.app" sin importar el
  // flavor, igual que pasaba del lado nativo (ver Bloque 2, nov 2026: ahora
  // Xcode ya usa un grupo separado por flavor vía APP_GROUP_ID). GOGO Food
  // DEBE compilarse con --dart-define=APP_GROUP_ID=group.com.fercadi.app
  // para que coincida con el entitlement real de ese flavor — si no
  // coincide, HomeWidget simplemente no encuentra los datos (falla en
  // silencio, el widget se queda en su estado vacío).
  static const String appGroupId = String.fromEnvironment(
    'APP_GROUP_ID',
    defaultValue: 'group.com.fercadi.app.pruebas',
  );

  // Google Maps — usada tanto para el SDK de mapas como para Geocoding API
  static const String googleMapsApiKey = 'AIzaSyDGxOWhjgxZsHjsgDtZdMlJ7q2OYzdYHDE';

  // Stripe — obtén tus claves en dashboard.stripe.com > Developers > API Keys
  // El default de abajo es la pk_test de Pruebas. GOGO Food (producción)
  // DEBE compilarse con --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
  // (ver CLAUDE.md, sección de compilación de producción) — sin esto, un
  // build de producción cobraría con la llave de pruebas, sin cobrar nada
  // de verdad, sin ningún aviso.
  // nov 2026: la pk_test anterior pertenecía a OTRA cuenta de Stripe distinta
  // a la que tiene configurado STRIPE_SECRET_KEY en la Edge Function — se
  // descubrió al configurar el webhook (Bloque B, auditoría nov 2026): el
  // webhook y la clave secreta no estaban en la misma cuenta, así que ningún
  // evento le habría llegado nunca a stripe-webhook. Esta pk_test sí es de la
  // cuenta correcta ("Grupo fercadi", acct_1ThAckJOgZRwLcU8).
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_51ThAckJOgZRwLcU8dhFUinKBgjBYCCcs1TntgCxi4ZquDFIjoqrSdZI8VucUnrTSDeS90LAahjZzRaVePin0ADmS0043SkfH6U',
  );
  // La clave secreta NUNCA va aquí — va en la Supabase Edge Function como variable de entorno

  // Sentry — obtén tu DSN en sentry.io > tu proyecto > Settings > Client Keys
  // Dejar vacío en desarrollo para no enviar errores de prueba
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  // Colores principales — tema oscuro con naranja
  static const Color primaryColor  = Color(0xFFF4510C); // Naranja principal
  static const Color bgColor       = Color(0xFF121212); // Fondo oscurou
  static const Color surfaceColor  = Color(0xFF1E1E1E); // Tarjetas
  static const Color surface2Color = Color(0xFF2A2A2A); // Sub-tarjetas
}
