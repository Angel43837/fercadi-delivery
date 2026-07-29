// main_flota.dart
// Punto de entrada de la app GOGO Flota (jefe de flota) — completamente
// separada de GOGO Food. No comparte router.dart con la app cliente.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'screens/flota_screen.dart';
import 'screens/flota_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
  runApp(const FlotaApp());
}

// Notifica al router cuando cambia la sesión de Supabase (restauración async
// del localStorage en web) — mismo patrón que appRouter en router.dart.
class _FlotaAuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;
  _FlotaAuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}

final _flotaRouter = GoRouter(
  initialLocation: '/flota-login',
  refreshListenable: _FlotaAuthNotifier(),
  redirect: (context, state) {
    if (state.matchedLocation == '/flota-login') return null;
    final user = Supabase.instance.client.auth.currentUser;
    final role = (user?.appMetadata['role'] ?? user?.userMetadata?['role']) as String?;
    if (role != 'jefe_flota') return '/flota-login';
    return null;
  },
  routes: [
    GoRoute(path: '/flota-login', builder: (_, _) => const FlotaLoginScreen()),
    GoRoute(path: '/flota',       builder: (_, _) => const FlotaScreen()),
  ],
);

class FlotaApp extends StatelessWidget {
  const FlotaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GOGO Flota',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF4F8EF7)),
      ),
      routerConfig: _flotaRouter,
    );
  }
}
