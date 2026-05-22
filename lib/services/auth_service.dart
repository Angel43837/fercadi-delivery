import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _keyRole  = 'session_role';
  static const _keyEmail = 'session_email';

  static Future<void> saveSession(String email, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);
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
}
