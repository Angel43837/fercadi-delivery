// onboarding_screen.dart
// Alta de cuenta nueva — un paso por pantalla (nombre, edad, dirección,
// género, método de pago) en vez de un formulario largo de un solo jalón.
// Reemplaza a complete_profile_screen.dart: cubre lo mismo que esa pantalla
// hacía (nombre, antes de dejar entrar a la app) y lo extiende. Se muestra
// para CUALQUIER cuenta de cliente nueva sin importar el método de alta
// (teléfono, correo, Google o Facebook) — el router (ver router.dart) es
// quien decide cuándo mandar aquí, revisando 'onboarding_completed' en
// user_metadata, así que esta pantalla no necesita saber por qué llegó.
//
// Nombre y dirección se piden siempre; edad y género se pueden omitir
// (son datos sensibles/opcionales, no hace sentido bloquear la app por
// ellos); método de pago ya trae 'Efectivo' preseleccionado, así que
// "Siguiente" siempre tiene un valor válido ahí.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../map_picker_screen.dart';

// Paleta propia de esta pantalla (naranja de fondo, blanco para texto/
// bolitas de progreso, azul para el botón de avanzar/seleccionado) — a
// propósito independiente de AppConstants, que otras pantallas usan con
// otro significado (ej. el naranja de dueño).
const _bgOrange  = Color(0xFFF4510C);
const _nextBlue  = Color(0xFF1E88E5);
const _cardFill  = Color(0x26FFFFFF); // blanco translúcido sobre el naranja

const _paymentOptions = [
  (value: 'cash', label: 'Efectivo', subtitle: 'Pago al repartidor', icon: Icons.money),
  (value: 'card', label: 'Tarjeta', subtitle: 'Crédito o débito', icon: Icons.credit_card),
];

const _genderOptions = [
  ('masculino', 'Masculino'),
  ('femenino', 'Femenino'),
  ('otro', 'Otro'),
  ('prefiero_no_decir', 'Prefiero no decir'),
];

class OnboardingScreen extends StatefulWidget {
  final String? returnTo;
  const OnboardingScreen({super.key, this.returnTo});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  int _step = 0;
  bool _saving = false;

  String? _addrText;
  double? _addrLat;
  double? _addrLng;
  bool _addrLoading = false;

  String? _gender;
  String _payment = 'cash';

  static const _totalSteps = 5;

  @override
  void initState() {
    super.initState();
    // Si ya viene con nombre de Google/Facebook, se precarga — el usuario
    // solo confirma o lo corrige, no empieza desde cero.
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final oauthName = (meta?['full_name'] ?? meta?['name']) as String?;
    if (oauthName != null && oauthName.trim().isNotEmpty) _nameCtrl.text = oauthName.trim();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe tu nombre para continuar'), backgroundColor: Colors.redAccent));
      return;
    }
    if (_step == _totalSteps - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
    _pageController.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _skip() {
    setState(() => _step++);
    _pageController.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pageController.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  Future<void> _pickByGPS() async {
    setState(() => _addrLoading = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      await _pickByMap(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (!mounted) return;
      setState(() => _addrLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo obtener tu ubicación GPS'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _pickByMap(LatLng? initial) async {
    final result = await Navigator.push<LatLng>(
        context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: initial)));
    if (result == null || !mounted) return;
    setState(() => _addrLoading = true);
    final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
    if (!mounted) return;
    setState(() {
      _addrText = addr ?? '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}';
      _addrLat = result.latitude;
      _addrLng = result.longitude;
      _addrLoading = false;
    });
  }

  void _pickManual() {
    final ctrl = TextEditingController(text: _addrText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Escribe tu dirección', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Calle, número, colonia...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: AppConstants.surface2Color,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.location_on_outlined, color: _nextBlue, size: 20),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              setState(() { _addrText = text; _addrLat = null; _addrLng = null; });
            },
            child: const Text('Guardar', style: TextStyle(color: _nextBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    final age = int.tryParse(_ageCtrl.text.trim());
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {
        'role': 'cliente',
        'custom_name': name,
        'onboarding_completed': true,
        if (age != null) 'age': age,
        if (_gender != null) 'gender': _gender,
      }));
      // Mismo motivo que complete_profile_screen.dart: el JWT recién emitido
      // no trae todavía el app_metadata que acaba de escribir el trigger
      // sync_role_to_app_metadata, así que se refresca antes de navegar a
      // una ruta que el router pueda proteger por rol.
      await Supabase.instance.client.auth.refreshSession();

      final user = Supabase.instance.client.auth.currentUser;
      await AuthService.saveSession(user?.id ?? 'guest', '/restaurants', email: user?.email, phone: user?.phone);
      await AuthService.saveDisplayName(name);
      if (age != null) await AuthService.saveAge(age);
      if (_gender != null) await AuthService.saveGender(_gender!);
      await AuthService.savePreferredPayment(_payment);
      if (_addrText != null && _addrText!.isNotEmpty) {
        await AuthService.saveAddress(label: 'Casa', address: _addrText!, lat: _addrLat, lng: _addrLng);
        if (_addrLat != null && _addrLng != null) {
          await AuthService.saveZona(LocationService.zonaFromCoords(_addrLat!, _addrLng!));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar tu perfil: $e'), backgroundColor: Colors.redAccent));
        setState(() => _saving = false);
      }
      return;
    }
    if (!mounted) return;
    final target = (widget.returnTo != null && widget.returnTo!.isNotEmpty) ? widget.returnTo! : '/restaurants';
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgOrange,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_totalSteps, (i) {
            final active = i <= _step;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _step ? 22 : 8, height: 8,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.white38,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          })),
          const SizedBox(height: 8),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepScaffold(
                  title: '¿Cómo te llamas?',
                  subtitle: 'Así te vamos a reconocer en GOGO',
                  child: TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration('Tu nombre', Icons.person_outline),
                  ),
                ),
                _StepScaffold(
                  title: '¿Qué edad tienes?',
                  subtitle: 'Opcional — puedes omitir este paso',
                  child: TextField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Tu edad', Icons.cake_outlined),
                  ),
                ),
                _StepScaffold(
                  title: '¿A dónde te entregamos?',
                  subtitle: 'Opcional — puedes agregarla después desde tu perfil',
                  child: _buildAddressPicker(),
                ),
                _StepScaffold(
                  title: '¿Con qué género te identificas?',
                  subtitle: 'Opcional — puedes omitir este paso',
                  child: Column(children: _genderOptions.map((g) {
                    final selected = _gender == g.$1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _gender = g.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: _cardFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? _nextBlue : Colors.transparent, width: 1.5),
                          ),
                          child: Row(children: [
                            Expanded(child: Text(g.$2, style: const TextStyle(color: Colors.white, fontSize: 15))),
                            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? _nextBlue : Colors.white38),
                          ]),
                        ),
                      ),
                    );
                  }).toList()),
                ),
                _StepScaffold(
                  title: '¿Cómo prefieres pagar?',
                  subtitle: 'Puedes cambiarlo cuando quieras desde tu perfil',
                  child: Column(children: _paymentOptions.map((opt) {
                    final selected = _payment == opt.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _payment = opt.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: _cardFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? _nextBlue : Colors.transparent, width: 1.5),
                          ),
                          child: Row(children: [
                            Icon(opt.icon, color: selected ? _nextBlue : Colors.white60),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(opt.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                              Text(opt.subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                            ])),
                            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? _nextBlue : Colors.white38),
                          ]),
                        ),
                      ),
                    );
                  }).toList()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(children: [
              if (_step > 0)
                IconButton(
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Regresar',
                ),
              if (_step == 1 || _step == 2 || _step == 3)
                TextButton(
                  onPressed: _saving ? null : _skip,
                  child: Text('Omitir', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _nextBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_step == _totalSteps - 1 ? 'FINALIZAR' : 'SIGUIENTE',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddressPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _cardFill, borderRadius: BorderRadius.circular(14)),
        child: _addrLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Row(children: [
                const Icon(Icons.location_on, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _addrText?.isNotEmpty == true ? _addrText! : 'Sin dirección todavía',
                  style: TextStyle(color: _addrText?.isNotEmpty == true ? Colors.white : Colors.white38, fontSize: 14),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                )),
              ]),
      ),
      const SizedBox(height: 16),
      _AddressActionButton(icon: Icons.my_location, label: 'Usar mi ubicación GPS', onTap: _addrLoading ? null : _pickByGPS),
      const SizedBox(height: 10),
      _AddressActionButton(icon: Icons.map_outlined, label: 'Elegir en el mapa', onTap: _addrLoading ? null : () => _pickByMap(null)),
      const SizedBox(height: 10),
      _AddressActionButton(icon: Icons.edit_outlined, label: 'Escribir dirección', onTap: _addrLoading ? null : _pickManual),
    ]);
  }

  InputDecoration _fieldDecoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: _cardFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _nextBlue, width: 1.5)),
      );
}

class _StepScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _StepScaffold({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 24),
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 32),
        child,
      ]),
    );
  }
}

class _AddressActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _AddressActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
