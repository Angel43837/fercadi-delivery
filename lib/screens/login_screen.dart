// login_screen.dart
// Pantalla de inicio de sesión y registro.
// Soporta tres métodos de autenticación:
//   1. Email + contraseña (Supabase Auth)
//   2. Google OAuth (abre el navegador externo, regresa por deep link fercadi://login-callback)
//   3. Facebook OAuth (igual que Google)
// Incluye un botón "demo" que entra sin credenciales para probar la app.
// La navegación post-login la maneja el listener _authSub según el rol del usuario.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';

// URL de regreso para móvil (deep link). En web se usa Uri.base.origin (localhost:PORT).
const _redirectUrl = 'fercadi://login-callback';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading        = false;
  bool _obscurePassword  = true;
  bool _isSignUp         = false;

  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        final user  = data.session?.user;
        final role  = user?.userMetadata?['role'] as String?;
        final email = user?.email ?? '';
        final route = role == 'repartidor' ? '/repartidor'
                    : role == 'dueno'      ? '/dueno'
                    : role == 'admin'      ? '/admin'
                    : '/restaurants';
        await AuthService.saveSession(email, route);
        if (mounted) context.go(route);
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Por favor completa todos los campos', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      if (email == 'dueno@fercadi.com' ||
          email == 'repartidor@fercadi.com' || SupabaseService.useMock) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final route = AuthService.roleToRoute(email);
        await AuthService.saveSession(email, route);
        if (!mounted) return;
        context.go(route);
        return;
      }
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _showMessage('Cuenta creada. Revisa tu correo para confirmar.');
      } else {
        final res = await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final role = res.user?.userMetadata?['role'] as String?;
        if (role == 'admin') {
          await Supabase.instance.client.auth.signOut();
          _showMessage('Usa la app de Administrador para acceder.', isError: true);
          return;
        }
        final route = role == 'repartidor' ? '/repartidor'
                    : role == 'dueno'      ? '/dueno'
                    : '/restaurants';
        await AuthService.saveSession(_emailController.text.trim(), route);
        if (!mounted) return;
        context.go(route);
      }
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final redirect = kIsWeb ? Uri.base.origin : _redirectUrl;
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirect,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      // La navegación la maneja el listener _authSub
    } catch (e) {
      if (mounted) _showMessage('Error con Google: $e', isError: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() => _isLoading = true);
    try {
      final redirect = kIsWeb ? Uri.base.origin : _redirectUrl;
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: redirect,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      // La navegación la maneja el listener _authSub
    } catch (e) {
      if (mounted) _showMessage('Error con Facebook: $e', isError: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppConstants.bgColor : AppConstants.primaryColor;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Center(
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: isDark ? AppConstants.primaryColor : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.delivery_dining, size: 54,
                      color: isDark ? Colors.white : AppConstants.primaryColor),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  _isSignUp ? 'Crear cuenta' : 'Bienvenido',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _isSignUp ? 'Regístrate en Grupo Fercadi' : 'Inicia sesión en Grupo Fercadi',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ),
              const SizedBox(height: 32),

              // ── Botones sociales ─────────────────────────────────────────────
              _SocialButton(
                onTap: _isLoading ? null : _signInWithGoogle,
                color: Colors.white,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _GoogleIcon(),
                  const SizedBox(width: 10),
                  const Text('Continuar con Google',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 12),
              _SocialButton(
                onTap: _isLoading ? null : _signInWithFacebook,
                color: const Color(0xFF1877F2),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('f', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, height: 1)),
                  SizedBox(width: 10),
                  Text('Continuar con Facebook',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Divider ──────────────────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o usa tu correo',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.12))),
              ]),
              const SizedBox(height: 24),

              // ── Formulario email/contraseña ───────────────────────────────────
              _buildField(
                controller: _emailController,
                label: 'Correo electrónico',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _passwordController,
                label: 'Contraseña',
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _authenticate,
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isSignUp ? 'CREAR CUENTA' : 'INICIAR SESIÓN',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate',
                    style: TextStyle(
                      color: isDark ? AppConstants.primaryColor : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final router = GoRouter.of(context);
                    await AuthService.saveSession('demo@fercadi.com', '/restaurants');
                    router.go('/restaurants');
                  },
                  child: Text('Entrar como demo (cliente)',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.75)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.75)),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: isDark
            ? AppConstants.surfaceColor
            : Colors.white.withValues(alpha: 0.25),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 1.5)),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color color;
  final Widget child;
  const _SocialButton({required this.onTap, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: onTap == null ? color.withValues(alpha: 0.5) : color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: child,
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22, height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, r, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: r * 0.8);

    void drawArc(double start, double sweep, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.38
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
    }

    const pi = 3.14159265;
    drawArc(-pi / 6, pi * 2 / 3, const Color(0xFF4285F4));
    drawArc(pi / 2, pi * 2 / 3, const Color(0xFF34A853));
    drawArc(pi * 7 / 6, pi * 2 / 3, const Color(0xFFFBBC05));
    drawArc(-pi * 5 / 6, pi * 2 / 3 - 0.1, const Color(0xFFEA4335));

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = r * 0.38
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + r * 0.75, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(_GooglePainter _) => false;
}
