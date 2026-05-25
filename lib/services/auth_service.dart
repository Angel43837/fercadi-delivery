import 'package:shared_preferences/shared_preferences.dart';

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
  static const _keyCLABE        = 'bank_clabe';

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

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
