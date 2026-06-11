// registro_restaurante_screen.dart
// Formulario de registro para nuevos restaurantes que quieren unirse a la plataforma.
// El dueño llena nombre, descripción, dirección y teléfono del restaurante.
// Al registrarse, se crea el usuario con rol "dueno" en Supabase Auth.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';

class RegistroRestauranteScreen extends StatefulWidget {
  const RegistroRestauranteScreen({super.key});
  @override
  State<RegistroRestauranteScreen> createState() => _RegistroRestauranteScreenState();
}

class _RegistroRestauranteScreenState extends State<RegistroRestauranteScreen> {
  final _restNameCtrl  = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _passCtrl      = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  bool _loading        = false;
  bool _showPass       = false;
  bool _showConfirm    = false;
  bool _registrado     = false;
  String _nombreRest   = '';

  @override
  void dispose() {
    _restNameCtrl.dispose(); _descCtrl.dispose(); _phoneCtrl.dispose();
    _addressCtrl.dispose(); _emailCtrl.dispose(); _ownerNameCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final restName  = _restNameCtrl.text.trim();
    final desc      = _descCtrl.text.trim();
    final phone     = _phoneCtrl.text.trim();
    final address   = _addressCtrl.text.trim();
    final ownerName = _ownerNameCtrl.text.trim();
    final email     = _emailCtrl.text.trim();
    final pass      = _passCtrl.text;
    final confirm   = _confirmCtrl.text;

    if (restName.isEmpty || email.isEmpty || pass.isEmpty || ownerName.isEmpty) {
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
      // 1. Crear cuenta en Supabase Auth
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {'role': 'dueno', 'name': ownerName},
      );
      if (res.user == null) {
        _msg('No se pudo crear la cuenta', error: true); return;
      }

      // 2. Iniciar sesión para tener permisos
      await Supabase.instance.client.auth.signInWithPassword(
        email: email, password: pass,
      );

      // 3. Insertar restaurante en la tabla
      final data = await Supabase.instance.client.from('restaurants').insert({
        'name': restName,
        'description': desc.isEmpty ? null : desc,
        'address': address.isEmpty ? null : address,
        'is_open': true,
        'rating': 0.0,
        'owner_id': res.user!.id,
      }).select().single();

      final restaurantId = data['id'] as String;

      // 4. Guardar el restaurant_id en metadata y SharedPreferences
      await AuthService.saveRestaurantId(restaurantId);
      await AuthService.saveRestaurantSettings(
        name: restName,
        desc: desc,
        phone: phone,
        address: address,
      );
      await AuthService.saveSession(email, '/dueno');

      if (!mounted) return;
      setState(() { _registrado = true; _nombreRest = restName; });
    } catch (e) {
      final msg = e.toString().contains('already registered')
          ? 'Este correo ya está registrado'
          : e.toString().contains('violates')
              ? 'Error al guardar el restaurante. Verifica la configuración de Supabase.'
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
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.store, color: AppConstants.primaryColor, size: 56),
              ),
              const SizedBox(height: 28),
              const Text('¡Restaurante registrado!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('$_nombreRest ya está en',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('GOGO Food 🍽️',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppConstants.primaryColor, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Entra a la app con tu correo para\ngestionar tu menú y ver tus pedidos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15, height: 1.5)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/dueno'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Gestionar mi restaurante',
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
            Center(
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.store_mall_directory_outlined, size: 44, color: AppConstants.primaryColor),
              ),
            ),
            const SizedBox(height: 20),
            const Center(child: Text('Registra tu restaurante',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
            const SizedBox(height: 6),
            Center(child: Text('Llega a más clientes con GOGO Food',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14))),
            const SizedBox(height: 32),

            _label('Nombre del restaurante *'),
            const SizedBox(height: 8),
            _field(controller: _restNameCtrl, hint: 'Ej. Tacos El Güero', icon: Icons.restaurant,
                capitalization: TextCapitalization.words),
            const SizedBox(height: 16),

            _label('Descripción'),
            const SizedBox(height: 8),
            _field(controller: _descCtrl, hint: '¿Qué tipo de comida vendes?', icon: Icons.description_outlined),
            const SizedBox(height: 16),

            _label('Dirección'),
            const SizedBox(height: 8),
            _field(controller: _addressCtrl, hint: 'Calle, número, colonia', icon: Icons.location_on_outlined),
            const SizedBox(height: 16),

            _label('Teléfono'),
            const SizedBox(height: 8),
            _field(controller: _phoneCtrl, hint: '443 000 0000', icon: Icons.phone_outlined,
                keyboard: TextInputType.phone),
            const SizedBox(height: 24),

            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 20),
            const Text('Tu cuenta de acceso',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Con esto entrarás a gestionar tu restaurante',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            const SizedBox(height: 16),

            _label('Tu nombre *'),
            const SizedBox(height: 8),
            _field(controller: _ownerNameCtrl, hint: 'Nombre del dueño', icon: Icons.person_outline,
                capitalization: TextCapitalization.words),
            const SizedBox(height: 16),

            _label('Correo electrónico *'),
            const SizedBox(height: 8),
            _field(controller: _emailCtrl, hint: 'tucorreo@gmail.com', icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 16),

            _label('Contraseña *'),
            const SizedBox(height: 8),
            _field(controller: _passCtrl, hint: 'Mínimo 6 caracteres', icon: Icons.lock_outline,
                obscure: !_showPass,
                suffix: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withValues(alpha: 0.35), size: 18),
                  onPressed: () => setState(() => _showPass = !_showPass),
                )),
            const SizedBox(height: 16),

            _label('Confirmar contraseña *'),
            const SizedBox(height: 8),
            _field(controller: _confirmCtrl, hint: 'Repite tu contraseña', icon: Icons.lock_outline,
                obscure: !_showConfirm,
                suffix: IconButton(
                  icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withValues(alpha: 0.35), size: 18),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                )),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity, height: 52,
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
                    : const Text('Registrar restaurante',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
