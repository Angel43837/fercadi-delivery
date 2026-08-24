// theme_provider.dart
// Maneja el modo de tema (oscuro / claro) de la app.
// Persiste la preferencia del usuario con SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'app_theme_dark';

  bool _isDark = false;
  bool get isDark => _isDark;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('theme_v3')) {
      _isDark = false;
      await prefs.setBool(_key, false);
      await prefs.setBool('theme_v3', true);
    } else {
      _isDark = prefs.getBool(_key) ?? false;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDark);
    notifyListeners();
  }
}
