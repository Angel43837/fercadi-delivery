// reset_password_screen.dart
// Se abre cuando el usuario toca el link de recuperación que le llega por
// correo (Supabase dispara AuthChangeEvent.passwordRecovery, el listener de
// login_screen.dart lo manda aquí). Ya tiene una sesión temporal de
// recuperación activa — solo falta pedirle la contraseña nueva.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _obscure  = true;
  bool _loading  = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pass    = _passwordController.text;
    final confirm = _confirmController.text;
    if (pass.length < 6) {
      _msg('La contraseña debe tener al menos 6 caracteres', error: true);
      return;
    }
    if (pass != confirm) {
      _msg('Las contraseñas no coinciden', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final user = await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pass),
      );
      final role = (user.user?.appMetadata['role'] ?? user.user?.userMetadata?['role']) as String?;
      final route = role == 'repartidor'      ? '/repartidor'
                  : role == 'repartidor_plus' ? '/rider'
                  : role == 'dueno'           ? '/dueno'
                  : '/restaurants';
      if (!mounted) return;
      _msg('Contraseña actualizada');
      context.go(route);
    } catch (e) {
      _msg('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red[700] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Nueva contraseña',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Escribe tu nueva contraseña para tu cuenta.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              const SizedBox(height: 32),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contraseña nueva',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.75)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white.withValues(alpha: 0.75)),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: AppConstants.surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.75)),
                  filled: true,
                  fillColor: AppConstants.surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _guardar,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('GUARDAR CONTRASEÑA',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
