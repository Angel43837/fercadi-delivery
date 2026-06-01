import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

class RegistroRepartidorScreen extends StatefulWidget {
  const RegistroRepartidorScreen({super.key});
  @override
  State<RegistroRepartidorScreen> createState() => _RegistroRepartidorScreenState();
}

class _RegistroRepartidorScreenState extends State<RegistroRepartidorScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _loading       = false;
  bool _showPass      = false;
  bool _showConfirm   = false;
  bool _registrado    = false;
  String _nombreRegistrado = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final name    = _nameCtrl.text.trim();
    final email   = _emailCtrl.text.trim();
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      _msg('Completa todos los campos', error: true); return;
    }
    if (pass.length < 6) {
      _msg('La contraseña debe tener al menos 6 caracteres', error: true); return;
    }
    if (pass != confirm) {
      _msg('Las contraseñas no coinciden', error: true); return;
    }

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {'role': 'repartidor', 'name': name},
      );

      if (res.user == null) {
        _msg('No se pudo crear la cuenta', error: true);
        return;
      }

      // Iniciar sesión inmediatamente
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pass,
      );

      if (!mounted) return;
      setState(() { _registrado = true; _nombreRegistrado = name; });
    } catch (e) {
      final msg = e.toString().contains('already registered')
          ? 'Este correo ya está registrado'
          : 'Error: ${e.toString()}';
      _msg(msg, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red[700] : Colors.green[700],
    ));
  }

  Widget _buildExito() {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Ícono de éxito
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: AppConstants.primaryColor, size: 60),
              ),
              const SizedBox(height: 28),
              Text('¡Felicidades, $_nombreRegistrado!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Ahora eres miembro de',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('GOGO Food 🛵',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppConstants.primaryColor, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Vuelve a la app e inicia sesión\ncon tu correo para recoger pedidos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15, height: 1.5)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Ir al inicio de sesión',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_registrado) return _buildExito();
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),

            // Ícono
            Center(
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delivery_dining, size: 44, color: AppConstants.primaryColor),
              ),
            ),
            const SizedBox(height: 20),

            const Center(
              child: Text('Registro de repartidor',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Crea tu cuenta para empezar a repartir',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14)),
            ),
            const SizedBox(height: 36),

            // Nombre
            _label('Nombre completo'),
            const SizedBox(height: 8),
            _field(
              controller: _nameCtrl,
              hint: 'Tu nombre',
              icon: Icons.person_outline,
              capitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Email
            _label('Correo electrónico'),
            const SizedBox(height: 8),
            _field(
              controller: _emailCtrl,
              hint: 'tucorreo@gmail.com',
              icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Contraseña
            _label('Contraseña'),
            const SizedBox(height: 8),
            _field(
              controller: _passCtrl,
              hint: 'Mínimo 6 caracteres',
              icon: Icons.lock_outline,
              obscure: !_showPass,
              suffix: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.35), size: 18),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
            const SizedBox(height: 16),

            // Confirmar contraseña
            _label('Confirmar contraseña'),
            const SizedBox(height: 8),
            _field(
              controller: _confirmCtrl,
              hint: 'Repite tu contraseña',
              icon: Icons.lock_outline,
              obscure: !_showConfirm,
              suffix: IconButton(
                icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.35), size: 18),
                onPressed: () => setState(() => _showConfirm = !_showConfirm),
              ),
            ),
            const SizedBox(height: 32),

            // Botón registrar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _registrar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryColor,
                  disabledBackgroundColor: AppConstants.primaryColor.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Crear cuenta',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),

            // Ya tengo cuenta
            Center(
              child: GestureDetector(
                onTap: () => context.pop(),
                child: RichText(
                  text: TextSpan(
                    text: '¿Ya tienes cuenta? ',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                    children: const [
                      TextSpan(text: 'Inicia sesión',
                          style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    bool obscure = false,
    Widget? suffix,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        textCapitalization: capitalization,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppConstants.surfaceColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
        ),
      );
}
