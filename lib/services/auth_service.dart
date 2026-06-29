import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// auth_service.dart
// Maneja la sesión del usuario y todos sus datos de perfil guardados localmente.
// Usa SharedPreferences (almacenamiento local del teléfono) para persistir los datos.
// Cada dato de perfil se guarda con el email como prefijo para separar cuentas.
//
// Roles disponibles: cliente (sin rol), repartidor, dueno, admin
// La sesión guarda: email + ruta de destino según el rol

class AuthService {
  static const _keyRole         = 'session_role';
  static const _keyEmail        = 'session_email';
  // Sesiones independientes para roles no-cliente (no interfieren con el splash del usuario)
  static const _keyDuenoEmail      = 'dueno_session_email';
  static const _keyRepartidorEmail = 'moto_session_email';
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

    // ── Clave con prefijo por usuario ────────────────────────────────────────────
  // Prefija cada clave con el email del usuario actual para que los datos
  // de diferentes cuentas en el mismo teléfono no se mezclen.
  // Ejemplo: "anjelom227@gmail.com:profile_display_name"
  static Future<String> _userKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail) ?? 'guest';
    return '$email:$key';
  }

  // ── Sesión ───────────────────────────────────────────────────────────────────

  static Future<void> saveSession(String email, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);
    final nameKey = '$email:$_keyDisplayName';
    if (prefs.getString(nameKey) == null) {
      final name = email.split('@').first;
      await prefs.setString(nameKey, _capitalize(name));
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
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
  }

  // ── Sesión del dueño (independiente del cliente) ────────────────────────────

  static Future<void> saveDuenoSession(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDuenoEmail, email);
  }

  static Future<String?> getDuenoSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDuenoEmail);
  }

  static Future<void> clearDuenoSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDuenoEmail);
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
  }

  // ── Sesión del repartidor (independiente del cliente) ────────────────────────

  static Future<void> saveRepartidorSession(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRepartidorEmail, email);
  }

  static Future<String?> getRepartidorSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRepartidorEmail);
  }

  static Future<void> clearRepartidorSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRepartidorEmail);
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
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
    final key   = await _userKey(_keyDisplayName);
    return prefs.getString(key) ?? 'Usuario';
  }

  static Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyDisplayName);
    await prefs.setString(key, name.trim().isEmpty ? 'Usuario' : name.trim());
  }

  static Future<String> getPreferredPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyPayment);
    return prefs.getString(key) ?? 'cash';
  }

  static Future<void> savePreferredPayment(String method) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyPayment);
    await prefs.setString(key, method);
  }

  static Future<int> getAvatarColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyAvatarColor);
    return prefs.getInt(key) ?? 0;
  }

  static Future<void> saveAvatarColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyAvatarColor);
    await prefs.setInt(key, index);
  }

  // ── Foto de perfil ───────────────────────────────────────────────────────────

  static Future<String?> getProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyProfilePhoto);
    return prefs.getString(key);
  }

  static Future<void> saveProfilePhoto(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyProfilePhoto);
    if (path == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, path);
    }
  }

  // ── Tarjeta de banco ─────────────────────────────────────────────────────────

  static Future<({String number, String expiry, String name})?> getCard() async {
    final prefs  = await SharedPreferences.getInstance();
    final kNum   = await _userKey(_keyCardNumber);
    final kExp   = await _userKey(_keyCardExpiry);
    final kName  = await _userKey(_keyCardName);
    final number = prefs.getString(kNum);
    final expiry = prefs.getString(kExp);
    final name   = prefs.getString(kName);
    if (number == null || number.isEmpty) return null;
    return (number: number, expiry: expiry ?? '', name: name ?? '');
  }

  static Future<void> saveCard(String number, String expiry, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _userKey(_keyCardNumber), number);
    await prefs.setString(await _userKey(_keyCardExpiry), expiry);
    await prefs.setString(await _userKey(_keyCardName),   name);
  }

  static Future<void> clearCard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _userKey(_keyCardNumber));
    await prefs.remove(await _userKey(_keyCardExpiry));
    await prefs.remove(await _userKey(_keyCardName));
  }

  // ── CLABE interbancaria (repartidor) ─────────────────────────────────────────

  static Future<String> getCLABE() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyCLABE);
    return prefs.getString(key) ?? '';
  }

  static Future<void> saveCLABE(String clabe) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyCLABE);
    await prefs.setString(key, clabe.trim());
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
    final key   = await _userKey(_keySavedAddresses);
    final raw   = prefs.getString(key);
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
    await prefs.setString(await _userKey(_keySavedAddresses), encoded);

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
