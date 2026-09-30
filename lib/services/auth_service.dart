import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// auth_service.dart
// Maneja la sesión del usuario y todos sus datos de perfil guardados localmente.
// Usa SharedPreferences (almacenamiento local del teléfono) para persistir los datos.
// Cada dato de perfil se guarda con el UID de Supabase como prefijo para separar cuentas.
//
// Roles disponibles: cliente (sin rol), repartidor, dueno, admin
// La sesión guarda: uid + rol +, si existen, email/teléfono (solo como metadata,
// ya no como identidad — ver nota abajo).
//
// Antes de agregar login por teléfono, todo esto estaba indexado por email
// (session_email). Una cuenta de solo-teléfono no tiene email, así que se
// migró la identidad al UID de Supabase (auth.currentUser.id), que siempre
// existe sin importar el método de login. Para no perder los datos ya
// guardados de cuentas existentes, saveSession() migra automáticamente (una
// sola vez, la primera vez que esa cuenta inicia sesión después de este
// cambio) cada valor cacheado de '<email>:clave' a '<uid>:clave' — ver
// _migrateLegacyEmailKeyedData más abajo.

class AuthService {
  static const _keyRole         = 'session_role';
  static const _keyUid          = 'session_uid';
  static const _keyEmail        = 'session_email';
  static const _keyPhone        = 'session_phone';
  // Sesiones independientes para roles no-cliente (no interfieren con el splash del usuario)
  static const _keyDuenoEmail      = 'dueno_session_email';
  static const _keyRepartidorEmail = 'moto_session_email';
  static const _keyDisplayName  = 'profile_display_name';
  static const _keyPayment      = 'profile_payment';
  static const _keyAvatarColor  = 'profile_avatar_color';
  static const _keyProfilePhoto = 'profile_photo_path';
  static const _keyZona         = 'profile_zona';
  static const _keyCLABE          = 'bank_clabe';
  static const _keySavedAddresses  = 'saved_addresses';
  static const _keyRestName        = 'restaurant_name';
  static const _keyRestDesc        = 'restaurant_description';
  static const _keyRestPhone       = 'restaurant_phone';
  static const _keyRestAddress     = 'restaurant_address';
  static const _keyRestPhoto       = 'restaurant_photo';
  static const _keyRestEmoji       = 'restaurant_emoji';
  static const _keyRestaurantId    = 'restaurant_id';

  // Claves que antes vivían bajo '<email>:...' y que _migrateLegacyEmailKeyedData
  // copia a '<uid>:...' la primera vez que una cuenta existente inicia sesión.
  // Incluye las de este archivo más las de OrderHistoryService (viven en otro
  // archivo pero usan el mismo patrón de prefijo por identidad) — se listan
  // aquí como strings literales para no crear una dependencia circular entre
  // los dos servicios.
  static const _legacyMigrationKeys = [
    _keyDisplayName, _keyPayment, _keyAvatarColor, _keyProfilePhoto,
    _keyZona, _keyCLABE, _keySavedAddresses,
    'active_order', 'order_history', // OrderHistoryService
  ];

    // ── Clave con prefijo por usuario ────────────────────────────────────────────
  // Prefija cada clave con el UID de Supabase del usuario actual para que los
  // datos de diferentes cuentas en el mismo teléfono no se mezclen.
  // Ejemplo: "3fa2c1e0-...:profile_display_name"
  static Future<String> _userKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_keyUid) ?? 'guest';
    return '$uid:$key';
  }

  // ── Sesión ───────────────────────────────────────────────────────────────────

  // [uid] es el identificador estable (auth.currentUser.id, o un uid sintético
  // 'mock:<email>' en modo mock). [email]/[phone] son opcionales — una cuenta
  // de solo-teléfono no tiene email, y viceversa.
  static Future<void> saveSession(
    String uid,
    String role, {
    String? email,
    String? phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyEmailKeyedData(prefs, uid: uid, email: email);
    await prefs.setString(_keyUid, uid);
    await prefs.setString(_keyRole, role);
    if (email != null && email.isNotEmpty) {
      await prefs.setString(_keyEmail, email);
    } else {
      await prefs.remove(_keyEmail);
    }
    if (phone != null && phone.isNotEmpty) {
      await prefs.setString(_keyPhone, phone);
    }
    final nameKey = '$uid:$_keyDisplayName';
    if (prefs.getString(nameKey) == null) {
      final base = (email != null && email.contains('@'))
          ? email.split('@').first
          : (phone ?? 'Usuario');
      await prefs.setString(nameKey, _capitalize(base));
    }
  }

  static Future<({String uid, String role, String? email, String? phone})?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final uid  = prefs.getString(_keyUid);
    final role = prefs.getString(_keyRole);
    if (uid == null || role == null) return null;
    return (uid: uid, role: role, email: prefs.getString(_keyEmail), phone: prefs.getString(_keyPhone));
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUid);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyPhone);
    await prefs.remove(_keyRole);
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
  }

  // Copia, una sola vez por cuenta, cada valor cacheado bajo '<email>:clave'
  // a '<uid>:clave' — para que una cuenta que ya tenía nombre/foto/direcciones
  // guardadas antes de este cambio no las pierda. Es seguro llamarla siempre
  // desde saveSession(): no hace nada si la cuenta es de solo-teléfono (sin
  // email, nada que migrar), nunca pisa un valor que ya exista bajo la clave
  // nueva, y una bandera 'migrated_to_uid:<uid>' la vuelve un no-op después
  // de la primera vez.
  static Future<void> _migrateLegacyEmailKeyedData(
    SharedPreferences prefs, {
    required String uid,
    String? email,
  }) async {
    if (email == null || email.isEmpty) return;
    final doneFlag = 'migrated_to_uid:$uid';
    if (prefs.getBool(doneFlag) == true) return;
    for (final k in _legacyMigrationKeys) {
      final legacyKey = '$email:$k';
      final newKey = '$uid:$k';
      if (prefs.containsKey(newKey)) continue;
      final v = prefs.get(legacyKey);
      if (v is String) {
        await prefs.setString(newKey, v);
      } else if (v is int) {
        await prefs.setInt(newKey, v);
      } else if (v is bool) {
        await prefs.setBool(newKey, v);
      } else if (v is double) {
        await prefs.setDouble(newKey, v);
      } else if (v is List<String>) {
        await prefs.setStringList(newKey, v);
      }
    }
    await prefs.setBool(doneFlag, true);
  }

  // ── Sesión del dueño (independiente del cliente) ────────────────────────────

  static Future<void> saveDuenoSession(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDuenoEmail, email);
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

  static String roleToRoute(String email) {
    switch (email.toLowerCase()) {
      case 'repartidor@fercadi.com': return '/repartidor';
      case 'dueno@fercadi.com':      return '/dueno';
      default:                       return '/restaurants';
    }
  }

  // ── Perfil de usuario ────────────────────────────────────────────────────────

  static Future<String> getDisplayName() async {
    // La caché local se escribe de inmediato (sin esperar red) en cada
    // saveDisplayName, así que siempre refleja el último cambio — por eso se
    // revisa primero. Si se consultara antes 'custom_name' de Supabase, un
    // cambio recién guardado podía verse "viejo" en otra pantalla mientras esa
    // llamada de red seguía en curso.
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyDisplayName);
    final local = prefs.getString(key);
    if (local != null && local.isNotEmpty) return local;
    // Sin caché local (dispositivo nuevo u otra sesión) — usa 'custom_name' de
    // Supabase, un campo propio distinto de 'name'/'full_name' que Google
    // reescribe en cada login con OAuth.
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final customName = user?.userMetadata?['custom_name'] as String?;
      if (customName != null && customName.trim().isNotEmpty) {
        await prefs.setString(key, customName);
        return customName;
      }
      // Si nunca se personalizó, muestra el nombre de Google como valor inicial.
      final oauthName = (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name']) as String?;
      if (oauthName != null && oauthName.trim().isNotEmpty) return oauthName;
    } catch (_) {}
    return 'Usuario';
  }

  static Future<void> saveDisplayName(String name) async {
    final trimmed = name.trim().isEmpty ? 'Usuario' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyDisplayName);
    await prefs.setString(key, trimmed);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Timeout: si la red se cuelga, esto no debe trabar la pantalla de
        // perfil para siempre esperando una respuesta que nunca llega.
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(data: {'custom_name': trimmed}))
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
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

  // ── Zona (Maravatío / Acámbaro) ───────────────────────────────────────────────

  static Future<String> getZona() async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyZona);
    final local = prefs.getString(key);
    if (local != null && local.isNotEmpty) return local;
    try {
      final metaZona = Supabase.instance.client.auth.currentUser?.userMetadata?['zona'] as String?;
      if (metaZona != null && metaZona.isNotEmpty) return metaZona;
    } catch (_) {}
    return 'maravatio';
  }

  static Future<void> saveZona(String zona) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyZona);
    await prefs.setString(key, zona);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(data: {'zona': zona}))
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
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
    // Misma razón que en getDisplayName: la caché local ya refleja el último
    // cambio al instante, sin depender de que la subida a Supabase termine.
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyProfilePhoto);
    final local = prefs.getString(key);
    if (local != null) return local;
    // Sin caché local — usa 'custom_avatar_url' de Supabase (campo propio,
    // 'avatar_url'/'picture' los puede repoblar Google en cada login) o, si
    // nunca se personalizó, la foto de Google como valor inicial.
    try {
      final user    = Supabase.instance.client.auth.currentUser;
      final metaUrl = user?.userMetadata?['custom_avatar_url'] as String?;
      if (metaUrl != null && metaUrl.startsWith('http')) {
        await prefs.setString(key, metaUrl);
        return metaUrl;
      }
      final picture = user?.userMetadata?['picture'] as String?;
      if (picture != null && picture.startsWith('http')) return picture;
    } catch (_) {}
    return null;
  }

  // Regresa false si la foto (siendo una URL real, ya subida) no se pudo
  // guardar en la cuenta — antes se tragaba el error en silencio y el
  // llamador nunca se enteraba de que solo quedó en la caché local.
  static Future<bool> saveProfilePhoto(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = await _userKey(_keyProfilePhoto);
    if (path == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, path);
    }
    // Solo se guarda en Supabase si es una URL real (la subida ya se hizo);
    // una ruta de archivo local no sirve en otro dispositivo.
    if (path != null && path.startsWith('http')) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return false;
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(data: {'custom_avatar_url': path}))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        return false;
      }
    }
    return true;
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
    // Antes se quitaba por 'label', y como checkout siempre guarda con el
    // mismo label ('Reciente'), cada pedido borraba la dirección anterior
    // en vez de acumular varias — el historial nunca pasaba de 1 elemento.
    // Ahora se deduplica por dirección: la misma dirección se actualiza y
    // sube al frente, pero direcciones distintas sí se acumulan.
    list.removeWhere((a) => a['address'] == address);
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

  static Future<void> removeAddress(String address) async {
    final list = await getSavedAddresses();
    list.removeWhere((a) => a['address'] == address);
    final encoded = jsonEncode(list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _userKey(_keySavedAddresses), encoded);
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
      final id = (user.appMetadata['restaurant_id'] ?? user.userMetadata?['restaurant_id']) as String?;
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
