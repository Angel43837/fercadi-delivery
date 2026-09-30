// login_screen.dart
// Pantalla de inicio de sesión y registro.
// Soporta tres métodos de autenticación:
//   1. Email + contraseña (Supabase Auth)
//   2. Google OAuth (abre el navegador externo, regresa por deep link fercadi://login-callback)
//   3. Facebook OAuth (igual que Google)
// Incluye un botón "demo" que entra sin credenciales para probar la app.
// La navegación post-login la maneja el listener _authSub según el rol del usuario.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/phone_otp/phone_otp_flow.dart';

// URL de regreso para móvil (deep link). En web se usa Uri.base.origin (localhost:PORT).
const _redirectUrl = 'fercadi://login-callback';

class LoginScreen extends StatefulWidget {
  // A dónde regresar tras iniciar sesión con éxito, en vez del home normal
  // del rol — se usa cuando un invitado llega aquí desde un punto donde
  // estaba haciendo algo (ej. pagar) y no queremos que pierda ese contexto.
  final String? returnTo;
  // Abre directo en modo "crear cuenta" — usado por el botón "Crear cuenta"
  // del aviso de "necesitas iniciar sesión".
  final bool startInSignUp;
  const LoginScreen({super.key, this.returnTo, this.startInSignUp = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController           = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading        = false;
  bool _obscurePassword  = true;
  bool _isSignUp         = false;
  bool _acceptedTerms    = false;
  // Inicio de sesión ahora arranca en un menú de 4 opciones (teléfono,
  // correo, Google, Facebook) — null = mostrando el menú; 'phone'/'email'
  // = ya eligió esa opción y se muestra solo ese formulario. No aplica a
  // "crear cuenta" (ese sigue mostrando teléfono + correo juntos, sin menú).
  String? _loginMethod;
  late final AnimationController _shakeController;
  // Supabase a veces dispara `signedIn` justo después de `passwordRecovery`
  // para el mismo enlace de recuperación — sin esta bandera, ese segundo
  // evento mandaba al usuario directo a la app antes de dejarlo poner la
  // contraseña nueva.
  bool _recovering       = false;
  // Mismo motivo/patrón que `_recovering`: verifyOTP (login por teléfono)
  // también dispara `signedIn` en este mismo stream — sin esta bandera, el
  // manejador genérico de abajo navegaría a la app ANTES de que el propio
  // flujo de teléfono decida si hace falta pasar por "completar perfil"
  // (alta nueva) o ir directo al home (cuenta ya existente).
  bool _phoneAuthInProgress = false;
  // Mismo motivo que _phoneAuthInProgress: el alta por correo también debe
  // pasar por "completar perfil" (pedir nombre) antes de entrar a la app —
  // sin esta bandera, el manejador genérico de abajo mandaba al cliente
  // nuevo directo a /restaurants en cuanto signUp() confirmaba su sesión,
  // sin darle nunca la oportunidad de poner su nombre.
  bool _emailSignUpInProgress = false;

  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startInSignUp;
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.passwordRecovery && mounted) {
        _recovering = true;
        context.go('/reset-password');
        return;
      }
      // El flujo de teléfono maneja su propia navegación (ver
      // _handlePhoneVerified) — este manejador genérico es para
      // correo/contraseña y Google/Facebook.
      if (_phoneAuthInProgress || _emailSignUpInProgress) return;
      if (data.event == AuthChangeEvent.signedIn && !_recovering && mounted) {
        final user  = data.session?.user;
        if (user == null) return;
        final role  = (user.appMetadata['role'] ?? user.userMetadata?['role']) as String?;
        final defaultRoute = role == 'repartidor'      ? '/repartidor'
                    : role == 'repartidor_plus' ? '/rider'
                    : role == 'dueno'           ? '/dueno'
                    : '/restaurants';
        // Si venía de algo pendiente como invitado (ej. pagar), regresa ahí
        // en vez del home normal — pero solo si de verdad es cliente, para
        // no mandar a un dueño/repartidor a una pantalla que no es suya.
        final route = (widget.returnTo != null && defaultRoute == '/restaurants')
            ? widget.returnTo!
            : defaultRoute;
        await AuthService.saveSession(user.id, defaultRoute, email: user.email, phone: user.phone);
        if (mounted) context.go(route);
      }
    });
  }

  // ── Login/registro por teléfono + OTP ────────────────────────────────────

  Future<bool> _beforeFirstPhoneSend() async {
    if (!_acceptedTerms) {
      _showMessage('Debes aceptar los Términos y el Aviso de Privacidad', isError: true);
      _shakeTermsBox();
      return false;
    }
    return true;
  }

  void _handlePhoneVerified(AuthResponse res, {required bool isNewUser}) {
    _phoneAuthInProgress = false;
    if (!mounted) return;
    if (isNewUser) {
      // Alta nueva — falta nombre/foto, eso lo pide complete_profile_screen.
      context.go('/complete-profile', extra: {
        if (widget.returnTo != null) 'returnTo': widget.returnTo,
      });
      return;
    }
    final user = res.user;
    if (user == null) return;
    final role = (user.appMetadata['role'] ?? user.userMetadata?['role']) as String?;
    final defaultRoute = role == 'repartidor'      ? '/repartidor'
                : role == 'repartidor_plus' ? '/rider'
                : role == 'dueno'           ? '/dueno'
                : '/restaurants';
    final route = (widget.returnTo != null && defaultRoute == '/restaurants')
        ? widget.returnTo!
        : defaultRoute;
    AuthService.saveSession(user.id, defaultRoute, email: user.email, phone: user.phone)
        .then((_) { if (mounted) context.go(route); });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _shakeTermsBox() => _shakeController.forward(from: 0);

  void _requireTermsThen(VoidCallback action) {
    if (!_acceptedTerms) {
      _showMessage('Debes aceptar los Términos y el Aviso de Privacidad', isError: true);
      _shakeTermsBox();
      return;
    }
    action();
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Por favor completa todos los campos', isError: true);
      return;
    }
    if (_isSignUp && _passwordController.text != _confirmPasswordController.text) {
      _showMessage('Las contraseñas no coinciden', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      if (SupabaseService.useMock) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final route = AuthService.roleToRoute(email);
        // Modo mock: no hay UID real de Supabase — se usa uno sintético
        // estable por correo, solo para que el caché local no se mezcle
        // entre las distintas cuentas demo.
        await AuthService.saveSession('mock:$email', route, email: email);
        if (!mounted) return;
        context.go(route);
        return;
      }
      if (_isSignUp) {
        _emailSignUpInProgress = true;
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'accepted_terms_at': DateTime.now().toIso8601String()},
        );
        if (!mounted) return;
        // Igual que el alta por teléfono: falta nombre/foto, eso lo pide
        // complete_profile_screen.dart antes de entrar a la app.
        context.go('/complete-profile', extra: {
          if (widget.returnTo != null) 'returnTo': widget.returnTo,
        });
      } else {
        final res = await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final role = (res.user?.appMetadata['role'] ?? res.user?.userMetadata?['role']) as String?;
        final defaultRoute = role == 'repartidor'      ? '/repartidor'
                    : role == 'repartidor_plus' ? '/rider'
                    : role == 'dueno'           ? '/dueno'
                    : '/restaurants';
        final route = (widget.returnTo != null && defaultRoute == '/restaurants')
            ? widget.returnTo!
            : defaultRoute;
        await AuthService.saveSession(res.user!.id, defaultRoute, email: res.user!.email, phone: res.user!.phone);
        if (!mounted) return;
        context.go(route);
      }
    } on AuthException catch (e) {
      // Mismo criterio que repartidor_login_screen.dart: no mostrar el
      // AuthException crudo (confunde a cualquier rol, no solo repartidores)
      // y distinguir "correo sin confirmar" de credenciales inválidas.
      final msg = _isSignUp
          ? (e.message.toLowerCase().contains('already registered') ||
                  e.code == 'user_already_exists'
              ? 'Este correo ya está registrado'
              : 'No se pudo crear la cuenta. Intenta de nuevo.')
          : (e.code == 'email_not_confirmed'
              ? 'Tu cuenta aún no está confirmada. Contacta a soporte.'
              : 'Correo o contraseña incorrectos');
      _showMessage(msg, isError: true);
    } catch (_) {
      _showMessage(
          _isSignUp ? 'No se pudo crear la cuenta. Intenta de nuevo.' : 'Correo o contraseña incorrectos',
          isError: true);
    } finally {
      _emailSignUpInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: const Text('Recuperar contraseña', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Correo electrónico',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : _redirectUrl,
      );
      if (mounted) _showMessage('Revisa tu correo para restablecer tu contraseña');
    } catch (_) {
      if (mounted) _showMessage('No se pudo enviar el correo. Intenta de nuevo.', isError: true);
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
    } catch (_) {
      if (mounted) _showMessage('No se pudo iniciar sesión con Google. Intenta de nuevo.', isError: true);
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
    } catch (_) {
      if (mounted) _showMessage('No se pudo iniciar sesión con Facebook. Intenta de nuevo.', isError: true);
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
              const SizedBox(height: 40),

              if (!_isSignUp && _loginMethod == null) ...[
                // ── Menú de inicio de sesión: logo grande, 137×158, centrado ───
                Center(
                  child: Column(children: [
                    Image.asset('assets/images/gogofood_go1.png', height: 62),
                    const SizedBox(height: 2),
                    Image.asset('assets/images/gogofood_go2.png', height: 62),
                    const SizedBox(height: 6),
                    Image.asset('assets/images/gogofood_word.png', height: 26),
                  ]),
                ),
                const SizedBox(height: 32),
                const Center(
                  child: Text(
                    'INICIO DE SESIÓN',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
                  ),
                ),
                const SizedBox(height: 24),
                _ChoiceButton(
                  label: 'NÚMERO TELEFÓNICO',
                  onTap: () => setState(() => _loginMethod = 'phone'),
                ),
                const SizedBox(height: 12),
                _ChoiceButton(
                  label: 'CORREO Y CONTRASEÑA',
                  onTap: () => setState(() => _loginMethod = 'email'),
                ),
                const SizedBox(height: 20),
                _SocialButton(
                  onTap: _isLoading ? null : () => _requireTermsThen(_signInWithGoogle),
                  color: Colors.white,
                  disabled: !_acceptedTerms,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _GoogleIcon(),
                    const SizedBox(width: 10),
                    const Text('Continuar con Google',
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 15)),
                  ]),
                ),
                const SizedBox(height: 12),
                _SocialButton(
                  onTap: _isLoading ? null : () => _requireTermsThen(_signInWithFacebook),
                  color: const Color(0xFF1877F2),
                  disabled: !_acceptedTerms,
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('f', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, height: 1)),
                    SizedBox(width: 10),
                    Text('Continuar con Facebook',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  ]),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isSignUp = true),
                    child: Text(
                      '¿No tienes cuenta? Regístrate',
                      style: TextStyle(
                        color: isDark ? AppConstants.primaryColor : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // ── Crear cuenta, o ya eligió un método de login ───────────────
                Center(
                  child: SvgPicture.asset(
                    'assets/images/logo.svg',
                    width: MediaQuery.of(context).size.width * 0.32,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                        isDark ? AppConstants.primaryColor : Colors.white,
                        BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: 28),
                if (_isSignUp)
                  const Center(
                    child: Text('Crea tu cuenta',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  )
                else
                  Row(children: [
                    IconButton(
                      onPressed: () => setState(() => _loginMethod = null),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _loginMethod == 'phone' ? 'Número telefónico' : 'Correo y contraseña',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ]),
                const SizedBox(height: 32),

                // ── Teléfono + código OTP ──────────────────────────────────────
                if (_isSignUp || _loginMethod == 'phone') ...[
                  PhoneOtpFlow(
                    mode: PhoneAuthMode.login,
                    beforeFirstSend: _beforeFirstPhoneSend,
                    onWillVerify: () => _phoneAuthInProgress = true,
                    onVerified: _handlePhoneVerified,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Formulario email/contraseña ────────────────────────────────
                if (_isSignUp || _loginMethod == 'email') ...[
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
                  if (_isSignUp) ...[
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _confirmPasswordController,
                      label: 'Confirmar contraseña',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: _acceptedTerms ? 1 : 0.5,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _requireTermsThen(_authenticate),
                        child: _isLoading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(
                                _isSignUp ? 'CREAR CUENTA' : 'INICIAR SESIÓN',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
                  if (!_isSignUp)
                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : _forgotPassword,
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _loginMethod = null;
                      _confirmPasswordController.clear();
                    }),
                    child: Text(
                      _isSignUp ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate',
                      style: TextStyle(
                        color: isDark ? AppConstants.primaryColor : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // ── Aceptación de términos y privacidad ───────────────────────────
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  final t = _shakeController.value;
                  final offset = sin(t * pi * 6) * (1 - t) * 10;
                  return Transform.translate(offset: Offset(offset, 0), child: child);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppConstants.primaryColor, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24, height: 24,
                        child: Checkbox(
                          value: _acceptedTerms,
                          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                          checkColor: Colors.white,
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? AppConstants.primaryColor
                                : Colors.white,
                          ),
                          side: BorderSide(color: AppConstants.primaryColor, width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            children: [
                              Text('Acepto los ',
                                  style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 12.5)),
                              GestureDetector(
                                onTap: () => context.push('/terms'),
                                child: Text('Términos y Condiciones',
                                    style: TextStyle(color: AppConstants.primaryColor, fontSize: 12.5,
                                        fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                              ),
                              Text(' y el ',
                                  style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 12.5)),
                              GestureDetector(
                                onTap: () => context.push('/privacy-policy'),
                                child: Text('Aviso de Privacidad',
                                    style: TextStyle(color: AppConstants.primaryColor, fontSize: 12.5,
                                        fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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

// Botón de opción del menú de inicio de sesión (teléfono / correo) — naranja
// oscuro sobre el fondo naranja, mismo estilo de píldora que los sociales.
class _ChoiceButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChoiceButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4C00),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            // Sombra exterior — 0px 1px 3.8px 1px #0000006E
            BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0x6E / 255), offset: const Offset(0, 1), blurRadius: 3.8, spreadRadius: 1),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Brillo interior naranja arriba — aproximación del
            // "box-shadow: 1px -19px 40.3px -1px #DA3A00 inset" del diseño
            // (Flutter no tiene sombra "inset" nativa, se simula con un
            // degradado recortado a la misma forma redondeada del botón).
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFDA3A00).withValues(alpha: 0.55),
                      const Color(0xFFDA3A00).withValues(alpha: 0),
                    ],
                    stops: const [0, 0.75],
                  ),
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color color;
  final Widget child;
  final bool disabled;
  const _SocialButton({
    required this.onTap,
    required this.color,
    required this.child,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          color: (onTap == null || disabled) ? color.withValues(alpha: 0.5) : color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0x6E / 255), offset: const Offset(0, 1), blurRadius: 3.8, spreadRadius: 1),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  static const _svg = '''
<svg viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
  <path fill="#4285F4" d="M17.64 9.2045c0-.6381-.0573-1.2518-.1636-1.8409H9v3.4818h4.8436c-.2086 1.125-.8427 2.0782-1.7959 2.7164v2.2582h2.9087c1.7018-1.5668 2.6836-3.874 2.6836-6.6155z"/>
  <path fill="#34A853" d="M9 18c2.43 0 4.4673-.806 5.9564-2.1805l-2.9087-2.2582c-.8059.5404-1.8368.8605-3.0477.8605-2.3436 0-4.3282-1.5831-5.036-3.7104H.9573v2.3318C2.4382 15.9832 5.4818 18 9 18z"/>
  <path fill="#FBBC05" d="M3.964 10.71c-.18-.5404-.2822-1.1177-.2822-1.71s.1023-1.1695.2822-1.71V4.9582H.9573C.3477 6.1731 0 7.5477 0 9c0 1.4523.3477 2.8268.9573 4.0418L3.964 10.71z"/>
  <path fill="#EA4335" d="M9 3.5795c1.3214 0 2.5077.4541 3.4405 1.346l2.5813-2.5814C13.4632.8918 11.426 0 9 0 5.4818 0 2.4382 2.0168.9573 4.9582L3.964 7.29C4.6718 5.1627 6.5564 3.5795 9 3.5795z"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20, height: 20,
      child: SvgPicture.string(_svg),
    );
  }
}
