// registro_rider_plus_screen.dart
// Registro de repartidor DENTRO de la app — restaurado en septiembre 2026.
//
// Mismo motivo que registro_restaurante_screen.dart: el registro se había
// movido a gogo-registro.vercel.app, un sitio que resultó estar conectado a
// OTRO proyecto de Supabase (mmjzyqvjdwhzefbaiums) distinto al que usa esta
// app (ymztoayxzewghbethahv, "GOGO-Pruebas") — cualquier rider que se
// registrara ahí nunca podía entrar a la app, porque su cuenta vivía en un
// proyecto que la app nunca consulta.
//
// Nota: antes existían DOS pantallas de registro de repartidor que creaban
// la misma cuenta (rol repartidor_plus) — se consolidaron en una sola del
// lado del sitio nuevo; aquí se restaura solo esa, no la duplicada.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistroRiderPlusScreen extends StatefulWidget {
  const RegistroRiderPlusScreen({super.key});
  @override
  State<RegistroRiderPlusScreen> createState() => _RegistroRiderPlusScreenState();
}

class _RegistroRiderPlusScreenState extends State<RegistroRiderPlusScreen> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading      = false;
  bool _showPass     = false;
  bool _showConfirm  = false;
  bool _registrado   = false;

  static const _blue = Color(0xFF0EA3D8);
  static const _dark = Color(0xFF0B7FAA);
  static const _white = Colors.white;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final name    = _nameCtrl.text.trim();
    final phone   = _phoneCtrl.text.trim();
    final email   = _emailCtrl.text.trim();
    final pass    = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      _msg('Completa los campos obligatorios', error: true); return;
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
        data: {'name': name, 'phone': phone, 'role': 'repartidor_plus'},
      );
      if (res.user == null) {
        _msg('No se pudo crear la cuenta', error: true); return;
      }
      if (!mounted) return;
      setState(() => _registrado = true);
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
      backgroundColor: error ? Colors.red[900] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_registrado) return _buildExito();
    return Scaffold(
      backgroundColor: _blue,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: _white),
                onPressed: () => context.go('/moto'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                Center(
                  child: Column(children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.two_wheeler, color: _white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text('Únete a GOGO Riders',
                        style: TextStyle(color: _white, fontSize: 26,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Gana dinero repartiendo con tu moto',
                        style: TextStyle(color: _white.withValues(alpha: 0.75),
                            fontSize: 14)),
                  ]),
                ),
                const SizedBox(height: 36),
                _field(ctrl: _nameCtrl, label: 'Nombre completo *',
                    hint: 'Tu nombre', icon: Icons.person_outline,
                    capitalization: TextCapitalization.words),
                const SizedBox(height: 12),
                _field(ctrl: _phoneCtrl, label: 'Teléfono',
                    hint: '443 000 0000', icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone),
                const SizedBox(height: 12),
                _field(ctrl: _emailCtrl, label: 'Correo electrónico *',
                    hint: 'tucorreo@gmail.com', icon: Icons.email_outlined,
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _field(ctrl: _passCtrl, label: 'Contraseña *',
                    hint: 'Mínimo 6 caracteres', icon: Icons.lock_outline,
                    obscure: !_showPass,
                    suffix: IconButton(
                      icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                          color: _white, size: 20),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    )),
                const SizedBox(height: 12),
                _field(ctrl: _confirmCtrl, label: 'Confirmar contraseña *',
                    hint: 'Repite tu contraseña', icon: Icons.lock_outline,
                    obscure: !_showConfirm,
                    suffix: IconButton(
                      icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility,
                          color: _white, size: 20),
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
                      foregroundColor: _blue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: _blue, strokeWidth: 2.5))
                        : const Text('Registrarme como rider',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/repartidor-login'),
                    child: RichText(
                      text: TextSpan(
                        text: '¿Ya tienes cuenta? ',
                        style: TextStyle(color: _white.withValues(alpha: 0.7),
                            fontSize: 13),
                        children: const [
                          TextSpan(text: 'Inicia sesión',
                              style: TextStyle(color: _white,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ]),
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
      backgroundColor: _blue,
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
                child: const Icon(Icons.check_circle_outline, color: _white, size: 56),
              ),
              const SizedBox(height: 28),
              const Text('¡Cuenta creada!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Ya puedes iniciar sesión con tu\ncorreo y contraseña para empezar\na recibir pedidos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white.withValues(alpha: 0.8),
                      fontSize: 15, height: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/repartidor-login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _white,
                    foregroundColor: _blue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Ir al login',
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
