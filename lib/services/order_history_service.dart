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

  // Prefijo por usuario — se cachea para que clearActiveOrder funcione incluso
  // después del logout. Indexado por UID (no por email): una cuenta de solo-
  // teléfono no tiene email, y antes de este cambio caía siempre en 'guest',
  // compartiendo historial con cualquier otra cuenta de solo-teléfono en el
  // mismo celular. La migración de datos ya cacheados bajo el email de cuentas
  // existentes la hace AuthService._migrateLegacyEmailKeyedData (que conoce
  // las claves _activeKey/_key de este archivo como 'active_order'/'order_history').
  static String? _lastKnownUid;

  static String get _userActiveKey {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) _lastKnownUid = uid;
    return '${_lastKnownUid ?? 'guest'}:$_activeKey';
  }

  static String get _userHistoryKey {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) _lastKnownUid = uid;
    return '${_lastKnownUid ?? 'guest'}:$_key';
  }

  // ── Pedido activo (para volver a tracking después de salir) ─────────────────

  static Future<void> saveActiveOrder({
    required String orderId,
    required String restaurantName,
    required double total,
    required String address,
    double? lat,
    double? lng,
    double? restaurantLat,
    double? restaurantLng,
    String? restaurantImageUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userActiveKey, [
      orderId,
      restaurantName,
      total.toString(),
      address,
      (lat ?? '').toString(),
      (lng ?? '').toString(),
      (restaurantLat ?? '').toString(),
      (restaurantLng ?? '').toString(),
      // Agregado al final a propósito — un pedido activo guardado ANTES de
      // este campo (formato viejo, sin esta posición) debe seguir leyéndose
      // bien con los primeros 8 campos, solo sin logo.
      restaurantImageUrl ?? '',
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
      'restaurantLat':  p.length > 6 && p[6].isNotEmpty ? double.tryParse(p[6]) : null,
      'restaurantLng':  p.length > 7 && p[7].isNotEmpty ? double.tryParse(p[7]) : null,
      'restaurantImageUrl': p.length > 8 && p[8].isNotEmpty ? p[8] : null,
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
    String? restaurantImageUrl,
    String? itemsSummary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    final entry = [
      orderId,
      restaurantName,
      total.toString(),
      address,
      DateTime.now().toIso8601String(),
      // Agregados al final a propósito — un pedido ya guardado antes de
      // estos campos (formato viejo) debe seguir leyéndose bien, solo sin
      // logo/resumen de productos.
      restaurantImageUrl ?? '',
      (itemsSummary ?? '').replaceAll('||', ' '),
    ].join('||');
    list.insert(0, entry);
    if (list.length > 30) list.removeLast();
    await prefs.setStringList(_userHistoryKey, list);
  }

  // Completa logo/resumen de productos en un pedido ya guardado (de antes
  // de que estos dos campos existieran) sin perder el resto de sus datos.
  static Future<void> backfill(
    String orderId, {
    String? restaurantImageUrl,
    String? itemsSummary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_userHistoryKey) ?? [];
    final i = list.indexWhere((e) => e.split('||').firstOrNull == orderId);
    if (i == -1) return;
    final p = list[i].split('||');
    while (p.length < 7) {
      p.add('');
    }
    if (restaurantImageUrl != null) p[5] = restaurantImageUrl;
    if (itemsSummary != null) p[6] = itemsSummary.replaceAll('||', ' ');
    list[i] = p.join('||');
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
        restaurantImageUrl: p.length > 5 && p[5].isNotEmpty ? p[5] : null,
        itemsSummary: p.length > 6 && p[6].isNotEmpty ? p[6] : null,
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
  final String? restaurantImageUrl;
  final String? itemsSummary;
  const HistoryEntry({
    required this.orderId,
    required this.restaurantName,
    required this.total,
    required this.address,
    required this.date,
    this.restaurantImageUrl,
    this.itemsSummary,
  });
}
