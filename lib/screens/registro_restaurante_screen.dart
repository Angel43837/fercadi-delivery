import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _loading         = false;
  bool _showPass        = false;
  bool _showConfirm     = false;
  bool _registrado      = false;
  bool _loadingLocation = false;
  String _nombreRest    = '';
  double? _detectedLat;
  double? _detectedLng;

  static const _orange  = Color(0xFFFF5722);
  static const _dark    = Color(0xFFE64A19); // naranja oscuro para inputs
  static const _white   = Colors.white;
  static const _hint    = Color(0xFFFFCCBB); // crema suave

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
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {'role': 'dueno', 'name': ownerName},
      );
      if (res.user == null) {
        _msg('No se pudo crear la cuenta', error: true); return;
      }
      await Supabase.instance.client.auth.signInWithPassword(
        email: email, password: pass,
      );
      final data = await Supabase.instance.client.from('restaurants').insert({
        'name': restName,
        'description': desc.isEmpty ? null : desc,
        'address': address.isEmpty ? null : address,
        'is_open': true,
        'rating': 0.0,
        'owner_id': res.user!.id,
        if (_detectedLat != null) 'lat': _detectedLat,
        if (_detectedLng != null) 'lng': _detectedLng,
      }).select().single();

      final restaurantId = data['id'] as String;
      await AuthService.saveRestaurantId(restaurantId);
      await AuthService.saveRestaurantSettings(
        name: restName, desc: desc, phone: phone, address: address,
      );
      await AuthService.saveDuenoSession(email);

      if (!mounted) return;
      setState(() { _registrado = true; _nombreRest = restName; });
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

  Future<void> _detectarUbicacion() async {
    setState(() => _loadingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _msg('Permiso de ubicación denegado', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));

      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=${pos.latitude}&lon=${pos.longitude}&format=json');
      final res = await http.get(url,
          headers: {'Accept-Language': 'es', 'User-Agent': 'GOGOFood/1.0'});

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final addr = json['address'] as Map<String, dynamic>? ?? {};
        final parts = [
          addr['road'] ?? addr['pedestrian'] ?? '',
          addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'] ?? '',
          addr['city'] ?? addr['town'] ?? addr['village'] ?? '',
        ].where((s) => (s as String).isNotEmpty).join(', ');
        _addressCtrl.text = parts.isNotEmpty ? parts : json['display_name'] ?? '';
        _detectedLat = pos.latitude;
        _detectedLng = pos.longitude;
      } else {
        _msg('No se pudo obtener la dirección', error: true);
      }
    } catch (e) {
      _msg('Error al obtener ubicación: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
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

            // Encabezado
            Center(
              child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store_mall_directory_outlined,
                      color: _white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text('Registra tu restaurante',
                    style: TextStyle(color: _white, fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Llega a más clientes con GOGO Food',
                    style: TextStyle(color: _white.withValues(alpha: 0.75),
                        fontSize: 14)),
              ]),
            ),
            const SizedBox(height: 36),

            _section('Información del restaurante'),
            const SizedBox(height: 16),
            _field(ctrl: _restNameCtrl, label: 'Nombre del restaurante *',
                hint: 'Ej. Tacos El Güero', icon: Icons.restaurant,
                capitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            _field(ctrl: _descCtrl, label: 'Descripción',
                hint: '¿Qué tipo de comida vendes?', icon: Icons.description_outlined),
            const SizedBox(height: 12),
            _field(ctrl: _addressCtrl, label: 'Dirección',
                hint: 'Ej: Calle Morelos 45, Col. Centro, Maravatío',
                icon: Icons.location_on_outlined,
                suffix: kIsWeb ? null : (_loadingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)))
                    : IconButton(
                        icon: const Icon(Icons.my_location, color: Colors.white, size: 20),
                        tooltip: 'Detectar mi ubicación',
                        onPressed: _detectarUbicacion,
                      ))),
            const SizedBox(height: 12),
            _field(ctrl: _phoneCtrl, label: 'Teléfono',
                hint: '443 000 0000', icon: Icons.phone_outlined,
                keyboard: TextInputType.phone),
            const SizedBox(height: 28),

            _section('Tu cuenta de acceso'),
            const SizedBox(height: 4),
            Text('Con esto entrarás a gestionar tu restaurante',
                style: TextStyle(color: _white.withValues(alpha: 0.7), fontSize: 13)),
            const SizedBox(height: 16),
            _field(ctrl: _ownerNameCtrl, label: 'Tu nombre *',
                hint: 'Nombre del dueño', icon: Icons.person_outline,
                capitalization: TextCapitalization.words),
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
                      color: _hint, size: 20),
                  onPressed: () => setState(() => _showPass = !_showPass),
                )),
            const SizedBox(height: 12),
            _field(ctrl: _confirmCtrl, label: 'Confirmar contraseña *',
                hint: 'Repite tu contraseña', icon: Icons.lock_outline,
                obscure: !_showConfirm,
                suffix: IconButton(
                  icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility,
                      color: _hint, size: 20),
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
                    : const Text('Registrar restaurante',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () => context.go('/login'),
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
    );
  }

  Widget _section(String text) => Text(text,
      style: const TextStyle(color: _white, fontWeight: FontWeight.bold,
          fontSize: 17));

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
                child: const Icon(Icons.store, color: _white, size: 56),
              ),
              const SizedBox(height: 28),
              const Text('¡Restaurante registrado!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('$_nombreRest ya está en',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white.withValues(alpha: 0.8),
                      fontSize: 16)),
              const SizedBox(height: 4),
              const Text('GOGO Food 🍽️',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Entra a la app con tu correo para\ngestionar tu menú y ver tus pedidos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white.withValues(alpha: 0.7),
                      fontSize: 15, height: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/dueno'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _white,
                    foregroundColor: _orange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Gestionar mi restaurante',
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
