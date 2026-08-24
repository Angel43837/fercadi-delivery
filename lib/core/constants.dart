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
  // Service role key — Settings > API > service_role en tu dashboard de Supabase
  static const String supabaseServiceRoleKey = '';

  // Google Maps — usada tanto para el SDK de mapas como para Geocoding API
  static const String googleMapsApiKey = 'AIzaSyDGxOWhjgxZsHjsgDtZdMlJ7q2OYzdYHDE';

  // Stripe — obtén tus claves en dashboard.stripe.com > Developers > API Keys
  static const String stripePublishableKey = 'pk_test_51ThAd2JlrTraAKwstUDr3pynDCZiLz88mldbch47FD6Fa4XVMjPKl9CGvdbAGkE4UG85mxwkrXXgIMdxF2SpbmlV00e1EnYwvc';
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
