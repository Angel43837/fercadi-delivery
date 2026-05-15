import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/supabase_service.dart';

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

  @override
  void dispose() {
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
      if (SupabaseService.useMock) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        final email = _emailController.text.trim().toLowerCase();
        if (email == 'admin@fercadi.com') {
          context.go('/admin');
        } else if (email == 'repartidor@fercadi.com') {
          context.go('/repartidor');
        } else if (email == 'dueno@fercadi.com') {
          context.go('/dueno');
        } else {
          context.go('/restaurants');
        }
        return;
      }
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _showMessage('Cuenta creada. Revisa tu correo para confirmar.');
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) context.go('/restaurants');
      }
    } catch (e) {
      _showMessage('Error: ${e.toString()}', isError: true);
    } finally {
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
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.delivery_dining, size: 54, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  _isSignUp ? 'Crear cuenta' : 'Bienvenido',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _isSignUp ? 'Regístrate en Grupo Fercadi' : 'Inicia sesión en Grupo Fercadi',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 40),
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
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _isSignUp ? 'CREAR CUENTA' : 'INICIAR SESIÓN',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Regístrate',
                    style: const TextStyle(color: AppConstants.primaryColor),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/restaurants'),
                  child: Text(
                    'Entrar como demo (cliente)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
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
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.5)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: AppConstants.surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppConstants.primaryColor),
        ),
      ),
    );
  }
}
