// Colores y medidas propias del panel de Admin.
// Deliberadamente separado de AppConstants: ese archivo lo comparten
// el cliente y el dueño, y este rediseño es solo para Admin.
import 'package:flutter/material.dart';

class AdminColors {
  AdminColors._();

  // Mismo naranja de Dueño (NO el de AppConstants, que es del cliente) —
  // surface/surfaceElevated son sombras más oscuras del mismo naranja,
  // para que las tarjetas se distingan del fondo sin dejar de ser naranja.
  static const bg = Color(0xFFFF5722);
  static const surface = Color(0xFFE64A19);
  static const surfaceElevated = Color(0xFFD84315);
  // Antes era naranja (0xFFFF6B00) — ahora que el fondo es naranja, los
  // botones/acentos interactivos pasan a azul para que de verdad resalten.
  static const accent = Color(0xFF2196F3);

  static const textPrimary = Colors.white;
  // Subidos de 0.55/0.35 — esos valores se calcularon para texto sobre
  // fondo casi negro; sobre naranja se ven lavados si no suben.
  static Color textSecondary = Colors.white.withValues(alpha: 0.85);
  static Color textFaint = Colors.white.withValues(alpha: 0.65);

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
