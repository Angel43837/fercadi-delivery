// splash_screen.dart
// Pantalla de bienvenida que se muestra 3 segundos al abrir la app.
// Muestra el logo con animación de fade-in y luego redirige según el estado de sesión:
//   - Si hay sesión guardada → va directo a la pantalla del rol (restaurantes, repartidor, etc.)
//   - Si no hay sesión → va al login

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

// Espera a que Supabase restaure su sesión del localStorage (o confirme que no hay ninguna).
// Supabase emite AuthChangeEvent.initialSession cuando termina de leer el token guardado.
// Sin esto, auth.currentUser es null en web aunque el token siga válido.
Future<Session?> _waitForSupabaseSession() async {
  final current = Supabase.instance.client.auth.currentSession;
  if (current != null) return current;
  try {
    final state = await Supabase.instance.client.auth.onAuthStateChange
        .firstWhere((s) =>
            s.event == AuthChangeEvent.initialSession ||
            s.event == AuthChangeEvent.signedIn ||
            s.event == AuthChangeEvent.tokenRefreshed)
        .timeout(const Duration(seconds: 6));
    return state.session;
  } catch (_) {
    return null;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _navigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    if (SupabaseService.useMock) {
      final session = await AuthService.getSession();
      if (!mounted) return;
      context.go(session?.role ?? '/login');
      return;
    }

    // Supabase es la fuente de verdad — siempre verificar la sesión activa
    final supabaseSession = await _waitForSupabaseSession();
    if (!mounted) return;

    if (supabaseSession == null) {
      context.go('/login');
      return;
    }

    final role = (supabaseSession.user.appMetadata['role'] ??
                  supabaseSession.user.userMetadata?['role']) as String?;

    final route = switch (role) {
      'dueno'          => '/dueno',
      'admin'          => '/admin',
      'repartidor'     => '/repartidor',
      'repartidor_plus'=> '/rider',
      'jefe_flota'     => '/flota',
      _                => '/restaurants',
    };

    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppConstants.bgColor : AppConstants.primaryColor;
    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // Logo ocupa la mayor parte de la pantalla
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SvgPicture.asset(
                    'assets/images/logo.svg',
                    width: size.width * 0.6,
                    fit: BoxFit.contain,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
              ),
            ),
            // Barra de carga abajo
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Column(
                children: [
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
