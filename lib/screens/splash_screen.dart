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
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 1500)),
      AuthService.getSession(),
    ]);
    if (!mounted) return;
    final session = results[1] as dynamic;
    if (session == null) { context.go('/login'); return; }

    // Para rutas privilegiadas, verificar contra Supabase live en modo real
    final candidateRoute = AuthService.roleToRoute(session.email);
    if (!SupabaseService.useMock &&
        (candidateRoute == '/admin' || candidateRoute == '/repartidor' || candidateRoute == '/dueno')) {
      final liveUser = Supabase.instance.client.auth.currentUser;
      final liveRole = liveUser?.userMetadata?['role'] as String?;
      final verifiedRoute = liveRole == 'repartidor' ? '/repartidor'
                          : liveRole == 'dueno'      ? '/dueno'
                          : liveRole == 'admin'      ? '/admin'
                          : '/login';
      context.go(verifiedRoute);
      return;
    }
    context.go(candidateRoute);
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
