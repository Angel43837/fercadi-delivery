import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistroRepartidorScreen extends StatefulWidget {
  const RegistroRepartidorScreen({super.key});
  @override
  State<RegistroRepartidorScreen> createState() => _RegistroRepartidorScreenState();
}

class _RegistroRepartidorScreenState extends State<RegistroRepartidorScreen> {
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading      = false;
  bool _showPass     = false;
  bool _showConfirm  = false;
  bool _registrado   = false;
  String _nombre     = '';

  static const _orange = Color(0xFFFF5722);
  static const _dark   = Color(0xFFE64A19);
  static const _white  = Colors.white;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
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
        _msg('No se pudo crear la cuenta', error: true); return;
      }
      await Supabase.instance.client.auth.signInWithPassword(
        email: email, password: pass,
      );
      if (!mounted) return;
      setState(() { _registrado = true; _nombre = name; });
    } catch (e) {
      final msg = e.toString().contains('already registered')
          ? 'Este correo ya está registrado'
          : 'Error: ${e.toString()}';
      _msg(msg, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _mostrarRecuperacion() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Recuperar contraseña',
            style: TextStyle(color: _white, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ingresa tu correo y te enviaremos un enlace para crear una nueva contraseña.',
              style: TextStyle(color: _white.withValues(alpha: 0.7), fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: _white),
            decoration: InputDecoration(
              labelText: 'Correo electrónico',
              labelStyle: TextStyle(color: _white.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54),
              filled: true,
              fillColor: _white.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _orange)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: TextStyle(color: _white.withValues(alpha: 0.5))),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(email);
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Revisa tu correo — te enviamos el enlace 📧'),
                  backgroundColor: Colors.green,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: _white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );
  }

  void _msg(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red[900] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_registrado) return _buildExito();
    return Scaffold(
      backgroundColor: _orange,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 40),

            Center(
              child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delivery_dining, color: _white, size: 42),
                ),
                const SizedBox(height: 16),
                const Text('Únete como repartidor',
                    style: TextStyle(color: _white, fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Crea tu cuenta para empezar a repartir',
                    style: TextStyle(color: _white.withValues(alpha: 0.75),
                        fontSize: 14)),
              ]),
            ),
            const SizedBox(height: 36),

            _field(ctrl: _nameCtrl, label: 'Nombre completo',
                hint: 'Tu nombre', icon: Icons.person_outline,
                capitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            _field(ctrl: _emailCtrl, label: 'Correo electrónico',
                hint: 'tucorreo@gmail.com', icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _field(ctrl: _passCtrl, label: 'Contraseña',
                hint: 'Mínimo 6 caracteres', icon: Icons.lock_outline,
                obscure: !_showPass,
                suffix: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                      color: _white.withValues(alpha: 0.5), size: 20),
                  onPressed: () => setState(() => _showPass = !_showPass),
                )),
            const SizedBox(height: 12),
            _field(ctrl: _confirmCtrl, label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña', icon: Icons.lock_outline,
                obscure: !_showConfirm,
                suffix: IconButton(
                  icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility,
                      color: _white.withValues(alpha: 0.5), size: 20),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                )),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _registrar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _white,
                  disabledBackgroundColor: _white.withValues(alpha: 0.5),
                  foregroundColor: _orange,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: _orange, strokeWidth: 2.5))
                    : const Text('Crear cuenta',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _mostrarRecuperacion,
                icon: const Icon(Icons.lock_reset, color: Colors.white70, size: 18),
                label: const Text('¿Olvidaste tu contraseña?',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _white, fontWeight: FontWeight.w600,
          fontSize: 13)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        textCapitalization: capitalization,
        style: const TextStyle(color: _white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _white.withValues(alpha: 0.45)),
          prefixIcon: Icon(icon, color: _white, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: _dark,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _white, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
      ),
    ]);
  }

  Widget _buildExito() {
    return Scaffold(
      backgroundColor: _orange,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: _white, size: 60),
              ),
              const SizedBox(height: 28),
              Text('¡Bienvenido, $_nombre!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _white, fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Ahora eres miembro de',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('GOGO Food 🛵',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Inicia sesión con tu correo\npara empezar a recoger pedidos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white.withValues(alpha: 0.75),
                      fontSize: 15, height: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/moto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _white,
                    foregroundColor: _orange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Iniciar sesión',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
