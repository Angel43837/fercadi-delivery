// Colores y medidas propias del panel de Admin.
// Deliberadamente separado de AppConstants: ese archivo lo comparten
// el cliente y el dueño, y este rediseño es solo para Admin.
import 'package:flutter/material.dart';

class AdminColors {
  AdminColors._();

  static const bg = Color(0xFF0D0D0F);
  static const surface = Color(0xFF17171A);
  static const surfaceElevated = Color(0xFF1F1F23);
  static const accent = Color(0xFFFF6B00);

  static const textPrimary = Colors.white;
  static Color textSecondary = Colors.white.withValues(alpha: 0.55);
  static Color textFaint = Colors.white.withValues(alpha: 0.35);

  // Estados de pedido — única fuente de verdad para Admin.
  // No reutilizar AppOrderStatus (app_data_provider.dart): ese enum
  // solo tiene 4 valores y lo comparte la pantalla de Dueño.
  static const statusPending = Color(0xFFFFB300);
  static const statusAccepted = Color(0xFFFF6B00);
  static const statusDelivering = Color(0xFF2196F3);
  static const statusDelivered = Color(0xFF34C759);
  static const statusCancelled = Color(0xFFFF453A);
}

class AdminRadii {
  AdminRadii._();

  static const card = 18.0;
  static const chip = 20.0;
  static const button = 14.0;
}
