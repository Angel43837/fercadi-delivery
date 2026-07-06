import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistroRiderPlusScreen extends StatefulWidget {
  const RegistroRiderPlusScreen({super.key});
  @override
  State<RegistroRiderPlusScreen> createState() => _RegistroRiderPlusScreenState();
}

class _RegistroRiderPlusScreenState extends State<RegistroRiderPlusScreen> {
  static const Color _bg     = Color(0xFFFF5722);
  static const Color _card   = Color(0xFFE64A19);
  static const Color _gold   = Color(0xFFFFD700);

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || pass.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {
          'name': name,
          'phone': phone,
          'role': 'repartidor_plus',
        },
      );
      setState(() {
        _success = '¡Cuenta creada! Ya puedes iniciar sesión en la app.';
      });
    } on AuthException catch (e) {
      setState(() => _error = e.message.contains('already')
          ? 'Ese correo ya está registrado'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Error al registrar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/moto'),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text('Únete a GOGO Riders',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(left: 44),
                child: Text('Regístrate y empieza a ganar con bonificaciones',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              const SizedBox(height: 32),

              // Badges de beneficios
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _badge('🪙', 'Coins'),
                  _badge('🏆', 'Retos'),
                  _badge('⭐', 'Niveles'),
                  _badge('💸', 'Retiros'),
                ],
              ),
              const SizedBox(height: 32),

              _buildField(controller: _nameCtrl, label: 'Nombre completo', icon: Icons.person_outline),
              const SizedBox(height: 14),
              _buildField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                icon: Icons.email_outlined,
                type: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _phoneCtrl,
                label: 'Teléfono',
                icon: Icons.phone_outlined,
                type: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // Contraseña
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contraseña (mín. 6 caracteres)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.2),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 1.5)),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_error!,
                        style: const TextStyle(color: Colors.white, fontSize: 13))),
                  ]),
                ),
              ],

              if (_success != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Flexible(child: Text(_success!,
                        style: const TextStyle(color: Colors.white, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => context.go('/moto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('IR AL LOGIN',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],

              if (_success == null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _registrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _bg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(color: _bg, strokeWidth: 2.5))
                        : const Text('CREAR MI CUENTA',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/moto'),
                  child: const Text('¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? type,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.2),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 1.5)),
      ),
    );
  }
}
