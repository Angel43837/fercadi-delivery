// order_history_service.dart
// Guarda y recupera el historial de pedidos del cliente en el teléfono (SharedPreferences).
// También maneja el "pedido activo" — el pedido en curso que se puede volver a ver
// en la pantalla de tracking si el usuario sale y regresa a la app.
// Los datos se guardan como strings separados por "||" para evitar JSON complejo.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderHistoryService {
  static const _key        = 'order_history';
  static const _activeKey  = 'active_order';

  // Prefijo por usuario — se cachea para que clearActiveOrder funcione incluso después del logout
  static String? _lastKnownEmail;

  static String get _userActiveKey {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null) _lastKnownEmail = email;
    return '${_lastKnownEmail ?? 'guest'}:$_activeKey';
  }

  static String get _userHistoryKey {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null) _lastKnownEmail = email;
    return '${_lastKnownEmail ?? 'guest'}:$_key';
  }

  // ── Pedido activo (para volver a tracking después de salir) ─────────────────

  static Future<void> saveActiveOrder({
    required String orderId,
    required String restaurantName,
    required double total,
    required String address,
    double? lat,
    double? lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userActiveKey, [
      orderId,
      restaurantName,
      total.toString(),
      address,
      (lat ?? '').toString(),
      (lng ?? '').toString(),
    ].join('||'));
  }

  static Future<Map<String, dynamic>?> getActiveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_userActiveKey);
    if (s == null || s.isEmpty) return null;
    final p = s.split('||');
    if (p.isEmpty) return null;
    return {
      'orderId':        p[0],
      'restaurantName': p.length > 1 ? p[1] : '',
      'total':          p.length > 2 ? double.tryParse(p[2]) ?? 0.0 : 0.0,
      'address':        p.length > 3 ? p[3] : '',
      'lat':            p.length > 4 && p[4].isNotEmpty ? double.tryParse(p[4]) : null,
      'lng':            p.length > 5 && p[5].isNotEmpty ? double.tryParse(p[5]) : null,
    };
  }

  static Future<void> clearActiveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userActiveKey);
  }

  static Future<void> add({
    required String orderId,
    required String restaurantName,
    required double total,
    required String address,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    final entry = [
      orderId,
      restaurantName,
      total.toString(),
      address,
      DateTime.now().toIso8601String(),
    ].join('||');
    list.insert(0, entry);
    if (list.length > 30) list.removeLast();
    await prefs.setStringList(_userHistoryKey, list);
  }

  static Future<List<HistoryEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    return list.map((e) {
      final p = e.split('||');
      return HistoryEntry(
        orderId:        p.isNotEmpty       ? p[0] : '',
        restaurantName: p.length > 1       ? p[1] : '',
        total:          p.length > 2       ? double.tryParse(p[2]) ?? 0 : 0,
        address:        p.length > 3       ? p[3] : '',
        date:           p.length > 4       ? DateTime.tryParse(p[4]) ?? DateTime.now() : DateTime.now(),
      );
    }).toList();
  }
}

class HistoryEntry {
  final String orderId;
  final String restaurantName;
  final double total;
  final String address;
  final DateTime date;
  const HistoryEntry({
    required this.orderId,
    required this.restaurantName,
    required this.total,
    required this.address,
    required this.date,
  });
}
