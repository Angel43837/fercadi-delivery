import 'package:flutter/material.dart';

class AppConstants {
  static const String supabaseUrl = 'https://mmjzyqvjdwhzefbaiums.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tanp5cXZqZHdoemVmYmFpdW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzMyMzAsImV4cCI6MjA5NDQ0OTIzMH0.5RC11kFCcKtPCeHFarByZDc9zzVBBvsZPYlI5Ed-PNM';
  // Service role key — Settings > API > service_role en tu dashboard de Supabase
  static const String supabaseServiceRoleKey = '';

  // Stripe — obtén tus claves en dashboard.stripe.com > Developers > API Keys
  static const String stripePublishableKey = 'pk_test_51ThAd2JlrTraAKwstUDr3pynDCZiLz88mldbch47FD6Fa4XVMjPKl9CGvdbAGkE4UG85mxwkrXXgIMdxF2SpbmlV00e1EnYwvc';
  // La clave secreta NUNCA va aquí — va en la Supabase Edge Function como variable de entorno

  // Colores principales — tema oscuro con naranja
  static const Color primaryColor  = Color(0xFFFF5722); // Naranja principal
  static const Color bgColor       = Color(0xFF121212); // Fondo oscurou
  static const Color surfaceColor  = Color(0xFF1E1E1E); // Tarjetas
  static const Color surface2Color = Color(0xFF2A2A2A); // Sub-tarjetas
}
