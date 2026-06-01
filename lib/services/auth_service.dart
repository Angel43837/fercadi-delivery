import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static const _keyRole         = 'session_role';
  static const _keyEmail        = 'session_email';
  static const _keyDisplayName  = 'profile_display_name';
  static const _keyPayment      = 'profile_payment';
  static const _keyAvatarColor  = 'profile_avatar_color';
  static const _keyProfilePhoto = 'profile_photo_path';
  static const _keyCardNumber   = 'card_number';
  static const _keyCardExpiry   = 'card_expiry';
  static const _keyCardName     = 'card_name';
  static const _keyCLABE          = 'bank_clabe';
  static const _keySavedAddresses  = 'saved_addresses';
  static const _keyRestName        = 'restaurant_name';
  static const _keyRestDesc        = 'restaurant_description';
  static const _keyRestPhone       = 'restaurant_phone';
  static const _keyRestAddress     = 'restaurant_address';
  static const _keyRestPhoto       = 'restaurant_photo';
  static const _keyRestEmoji       = 'restaurant_emoji';
  static const _keyRestaurantId    = 'restaurant_id';

  // ── Sesión ───────────────────────────────────────────────────────────────────

  static Future<void> saveSession(String email, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);
    if (prefs.getString(_keyDisplayName) == null) {
      final name = email.split('@').first;
      await prefs.setString(_keyDisplayName, _capitalize(name));
    }
  }

  static Future<({String email, String role})?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final role  = prefs.getString(_keyRole);
    if (email == null || role == null) return null;
    return (email: email, role: role);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyRole);
  }

  static String roleToRoute(String email) {
    switch (email.toLowerCase()) {
      case 'admin@fercadi.com':      return '/admin';
      case 'repartidor@fercadi.com': return '/repartidor';
      case 'dueno@fercadi.com':      return '/dueno';
      default:                       return '/restaurants';
    }
  }

  // ── Perfil de usuario ────────────────────────────────────────────────────────

  static Future<String> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDisplayName) ?? 'Usuario';
  }

  static Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDisplayName, name.trim().isEmpty ? 'Usuario' : name.trim());
  }

  static Future<String> getPreferredPayment() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPayment) ?? 'cash';
  }

  static Future<void> savePreferredPayment(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPayment, method);
  }

  static Future<int> getAvatarColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAvatarColor) ?? 0;
  }

  static Future<void> saveAvatarColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAvatarColor, index);
  }

  // ── Foto de perfil ───────────────────────────────────────────────────────────

  static Future<String?> getProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProfilePhoto);
  }

  static Future<void> saveProfilePhoto(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_keyProfilePhoto);
    } else {
      await prefs.setString(_keyProfilePhoto, path);
    }
  }

  // ── Tarjeta de banco ─────────────────────────────────────────────────────────

  static Future<({String number, String expiry, String name})?> getCard() async {
    final prefs  = await SharedPreferences.getInstance();
    final number = prefs.getString(_keyCardNumber);
    final expiry = prefs.getString(_keyCardExpiry);
    final name   = prefs.getString(_keyCardName);
    if (number == null || number.isEmpty) return null;
    return (number: number, expiry: expiry ?? '', name: name ?? '');
  }

  static Future<void> saveCard(String number, String expiry, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCardNumber, number);
    await prefs.setString(_keyCardExpiry, expiry);
    await prefs.setString(_keyCardName,   name);
  }

  static Future<void> clearCard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCardNumber);
    await prefs.remove(_keyCardExpiry);
    await prefs.remove(_keyCardName);
  }

  // ── CLABE interbancaria (repartidor) ─────────────────────────────────────────

  static Future<String> getCLABE() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCLABE) ?? '';
  }

  static Future<void> saveCLABE(String clabe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCLABE, clabe.trim());
  }

  // ── Direcciones guardadas ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSavedAddresses() async {
    // Primero intenta cargar desde Supabase user metadata (persiste entre sesiones)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final raw = user.userMetadata?['saved_addresses'] as String?;
        if (raw != null && raw.isNotEmpty) {
          final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
          // Sincroniza localmente para acceso offline
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keySavedAddresses, raw);
          return list;
        }
      }
    } catch (_) {}

    // Fallback: SharedPreferences (funciona para usuarios demo/roles especiales)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySavedAddresses);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAddress({
    required String label,
    required String address,
    double? lat,
    double? lng,
  }) async {
    final list = await getSavedAddresses();
    list.removeWhere((a) => a['label'] == label);
    list.insert(0, {'label': label, 'address': address, 'lat': lat, 'lng': lng});
    if (list.length > 5) list.removeLast();

    final encoded = jsonEncode(list);

    // Guarda localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySavedAddresses, encoded);

    // Guarda en Supabase (persiste aunque se borre el navegador)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'saved_addresses': encoded}),
        );
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getDefaultAddress() async {
    final list = await getSavedAddresses();
    return list.isNotEmpty ? list.first : null;
  }

  // ── ID del restaurante del dueño ─────────────────────────────────────────────

  static Future<String> getRestaurantId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final id = user.userMetadata?['restaurant_id'] as String?;
      if (id != null && id.isNotEmpty) return id;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRestaurantId) ?? '1';
  }

  static Future<void> saveRestaurantId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRestaurantId, id);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'restaurant_id': id}),
        );
      }
    } catch (_) {}
  }

  // ── Configuración del restaurante (dueño) ────────────────────────────────────

  static Future<Map<String, String>> getRestaurantSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name':    prefs.getString(_keyRestName)    ?? '',
      'desc':    prefs.getString(_keyRestDesc)    ?? '',
      'phone':   prefs.getString(_keyRestPhone)   ?? '',
      'address': prefs.getString(_keyRestAddress) ?? '',
      'photo':   prefs.getString(_keyRestPhoto)   ?? '',
      'emoji':   prefs.getString(_keyRestEmoji)   ?? '🍴',
    };
  }

  static Future<void> saveRestaurantSettings({
    String? name,
    String? desc,
    String? phone,
    String? address,
    String? photo,
    String? emoji,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name    != null) await prefs.setString(_keyRestName,    name);
    if (desc    != null) await prefs.setString(_keyRestDesc,    desc);
    if (phone   != null) await prefs.setString(_keyRestPhone,   phone);
    if (address != null) await prefs.setString(_keyRestAddress, address);
    if (photo   != null) await prefs.setString(_keyRestPhoto,   photo);
    if (emoji   != null) await prefs.setString(_keyRestEmoji,   emoji);
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
