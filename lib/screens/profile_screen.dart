// profile_screen.dart
// Pantalla de perfil del usuario.
// Permite al usuario configurar:
//   - Nombre y foto de perfil
//   - Dirección de entrega predeterminada (GPS, mapa o texto manual)
//   - Método de pago preferido (efectivo, OXXO, tarjeta)
//   - Datos de tarjeta bancaria
//   - CLABE interbancaria (solo para repartidores)
// También tiene los botones de cerrar sesión y reiniciar la app.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'map_picker_screen.dart';

const _avatarColors = [
  AppConstants.primaryColor,
  Color(0xFFFF6D00),
  Color(0xFF00BFA5),
  Color(0xFF7C4DFF),
  Color(0xFF2196F3),
  Color(0xFFFFB300),
  Colors.green,
  Colors.redAccent,
];

const _paymentOptions = [
  (value: 'cash',  label: 'Efectivo',  subtitle: 'Pago al repartidor', icon: Icons.money),
  (value: 'oxxo',  label: 'OXXO Pay',  subtitle: 'Referencia en OXXO', icon: Icons.store),
  (value: 'card',  label: 'Tarjeta',   subtitle: 'Crédito o débito',   icon: Icons.credit_card),
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _cardNumCtrl = TextEditingController();
  final _cardExpCtrl = TextEditingController();
  final _cardNameCtrl= TextEditingController();
  final _clabeCtrl   = TextEditingController();
  String  _payment    = 'cash';
  int     _colorIndex = 0;
  bool    _loading    = true;
  String  _email      = '';
  String  _role       = '';
  String? _photoPath;
  bool    _showCvv    = false;
  final   _cvvCtrl    = TextEditingController();

  // Ubicación de entrega
  String  _addrText    = '';
  double? _addrLat;
  double? _addrLng;
  bool    _addrLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name    = await AuthService.getDisplayName();
    final payment = await AuthService.getPreferredPayment();
    final color   = await AuthService.getAvatarColorIndex();
    final session = await AuthService.getSession();
    final photo   = await AuthService.getProfilePhoto();
    final card    = await AuthService.getCard();
    final clabe   = await AuthService.getCLABE();
    final defAddr = await AuthService.getDefaultAddress();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text  = name;
      _payment        = payment;
      _colorIndex     = color;
      _email          = session?.email ?? '';
      _role           = session?.role  ?? '';
      _photoPath      = photo;
      _clabeCtrl.text = clabe;
      if (card != null) {
        _cardNumCtrl.text  = _formatCardDisplay(card.number);
        _cardExpCtrl.text  = card.expiry;
        _cardNameCtrl.text = card.name;
      }
      if (defAddr != null) {
        _addrText = defAddr['address'] as String? ?? '';
        _addrLat  = (defAddr['lat'] as num?)?.toDouble();
        _addrLng  = (defAddr['lng'] as num?)?.toDouble();
      }
      _loading = false;
    });
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Cambiar dirección de entrega',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppConstants.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.my_location, color: AppConstants.primaryColor, size: 20)),
            title: const Text('Usar mi ubicación actual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('El GPS detecta dónde estás', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickByGPS(); },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF2196F3).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.map_outlined, color: Color(0xFF2196F3), size: 20)),
            title: const Text('Elegir en el mapa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Mueve el pin a tu dirección', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () {
              final initial = (_addrLat != null && _addrLng != null)
                  ? LatLng(_addrLat!, _addrLng!)
                  : null;
              Navigator.pop(context);
              _pickByMap(initial);
            },
          ),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF00BFA5).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.edit_location_outlined, color: Color(0xFF00BFA5), size: 20)),
            title: const Text('Escribir dirección', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Ingresa tu dirección manualmente', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickManual(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener tu ubicación GPS'),
            backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _pickByMap(LatLng? initial) async {
    final result = await Navigator.push<LatLng>(
      context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: initial)));
    if (result == null || !mounted) return;
    setState(() => _addrLoading = true);
    final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
    if (!mounted) return;
    final text = addr ?? '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}';
    setState(() { _addrText = text; _addrLat = result.latitude; _addrLng = result.longitude; _addrLoading = false; });
    await AuthService.saveAddress(label: 'Casa', address: text, lat: result.latitude, lng: result.longitude);
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
            prefixIcon: const Icon(Icons.location_on_outlined, color: AppConstants.primaryColor, size: 20),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))),
          TextButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              setState(() { _addrText = text; _addrLat = null; _addrLng = null; });
              await AuthService.saveAddress(label: 'Casa', address: text);
            },
            child: const Text('Guardar', style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await AuthService.saveDisplayName(_nameCtrl.text);
    await AuthService.savePreferredPayment(_payment);
    await AuthService.saveAvatarColorIndex(_colorIndex);
    await AuthService.saveProfilePhoto(_photoPath);
    await AuthService.saveCLABE(_clabeCtrl.text);

    final rawNum = _cardNumCtrl.text.replaceAll(' ', '');
    if (rawNum.length >= 15) {
      await AuthService.saveCard(rawNum, _cardExpCtrl.text, _cardNameCtrl.text);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Perfil guardado'),
        backgroundColor: AppConstants.primaryColor,
        duration: Duration(seconds: 2),
      ),
    );
    context.pop();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final xfile  = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 400);
    if (xfile == null) return;

    final userId = _email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    if (kIsWeb) {
      // En web: leer bytes directamente y subir a Supabase
      final bytes = await xfile.readAsBytes();
      final remoteUrl = await SupabaseService.uploadProfilePhotoBytes(bytes, userId);
      if (!mounted) return;
      setState(() => _photoPath = remoteUrl);
    } else {
      // En móvil: copiar a almacenamiento local permanente
      final appDir   = await getApplicationDocumentsDirectory();
      final destPath = p.join(appDir.path, 'profile_photo.jpg');
      await File(xfile.path).copy(destPath);
      final remoteUrl = await SupabaseService.uploadProfilePhoto(destPath, userId);
      if (!mounted) return;
      setState(() => _photoPath = remoteUrl ?? destPath);
    }
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppConstants.primaryColor),
            title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppConstants.primaryColor),
            title: const Text('Elegir de galería', style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); },
          ),
          if (_photoPath != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
              title: Text('Quitar foto', style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.8))),
              onTap: () { Navigator.pop(context); setState(() => _photoPath = null); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _formatCardDisplay(String raw) {
    final digits = raw.replaceAll(' ', '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cardNumCtrl.dispose();
    _cardExpCtrl.dispose();
    _cardNameCtrl.dispose();
    _cvvCtrl.dispose();
    _clabeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppConstants.primaryColor)),
      );
    }

    final avatarColor = _avatarColors[_colorIndex % _avatarColors.length];
    final initials = _nameCtrl.text.trim().isEmpty
        ? '?'
        : _nameCtrl.text.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    // Colores adaptativos para las tarjetas internas
    final cardBg     = isDark ? AppConstants.surfaceColor : Colors.white;
    final cardText   = isDark ? Colors.white : Colors.black87;
    final cardSub    = isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black54;
    final cardDiv    = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.07);
    final cardChev   = isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black38;
    final inputText  = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Mi perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final router = GoRouter.of(context);
              await AuthService.clearSession();
              if (!mounted) return;
              router.go('/login');
            },
          ),
          TextButton(
            onPressed: _save,
            child: const Text('Guardar',
                style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── Avatar / Foto ───────────────────────────────────────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _showPhotoPicker,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        color: avatarColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: avatarColor.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)],
                      ),
                      child: _photoPath != null
                          ? ClipOval(child: _ProfileImage(path: _photoPath!, size: 96))
                          : Center(
                              child: Text(initials,
                                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Toca para cambiar foto',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
              const SizedBox(height: 12),
              if (_photoPath == null) ...[
                Text('Elige un color para tu avatar',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_avatarColors.length, (i) {
                    final selected = i == _colorIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _colorIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: selected ? 34 : 28, height: selected ? 34 : 28,
                        decoration: BoxDecoration(
                          color: _avatarColors[i],
                          shape: BoxShape.circle,
                          border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 28),

          // ── Nombre ──────────────────────────────────────────────────────────
          _SectionLabel('Nombre'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: inputText, fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco('Tu nombre', Icons.person_outline),
          ),
          const SizedBox(height: 6),
          Text(_email, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          const SizedBox(height: 28),

          // ── Dirección de entrega ─────────────────────────────────────────────
          _SectionLabel('Dirección de entrega'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showLocationPicker,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: _addrLoading
                  ? const Center(child: SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(color: AppConstants.primaryColor, strokeWidth: 2)))
                  : Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppConstants.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.location_on, color: AppConstants.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _addrText.isEmpty ? 'Sin dirección guardada' : _addrText,
                          style: TextStyle(
                              color: _addrText.isEmpty ? cardSub : cardText, fontSize: 14),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text('Toca para cambiar',
                            style: TextStyle(color: AppConstants.primaryColor, fontSize: 11)),
                      ])),
                      Icon(Icons.chevron_right, color: cardChev),
                    ]),
            ),
          ),
          const SizedBox(height: 28),

          // ── Método de pago ───────────────────────────────────────────────────
          _SectionLabel('Método de pago preferido'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: List.generate(_paymentOptions.length, (i) {
                final opt      = _paymentOptions[i];
                final selected = _payment == opt.value;
                final isLast   = i == _paymentOptions.length - 1;
                return Column(children: [
                  InkWell(
                    borderRadius: BorderRadius.vertical(
                      top:    i == 0  ? const Radius.circular(16) : Radius.zero,
                      bottom: isLast  ? const Radius.circular(16) : Radius.zero,
                    ),
                    onTap: () => setState(() => _payment = opt.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Icon(opt.icon,
                            color: selected ? AppConstants.primaryColor : cardSub, size: 24),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(opt.label, style: TextStyle(
                              color: selected ? AppConstants.primaryColor : cardText,
                              fontWeight: FontWeight.w600, fontSize: 15)),
                          Text(opt.subtitle, style: TextStyle(color: cardSub, fontSize: 12)),
                        ])),
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: selected ? AppConstants.primaryColor : cardChev, width: 2),
                          ),
                          child: selected
                              ? Center(child: Container(width: 11, height: 11,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle, color: AppConstants.primaryColor)))
                              : null,
                        ),
                      ]),
                    ),
                  ),
                  if (!isLast) Divider(height: 1, color: cardDiv, indent: 16, endIndent: 16),
                ]);
              }),
            ),
          ),
          const SizedBox(height: 28),

          // ── CLABE interbancaria (solo repartidor) ────────────────────────────
          if (_role == 'repartidor') ...[
            _SectionLabel('Cuenta bancaria para recibir pagos'),
            const SizedBox(height: 8),
            TextField(
              controller: _clabeCtrl,
              style: TextStyle(color: inputText, fontSize: 16, letterSpacing: 1.5),
              keyboardType: TextInputType.number,
              maxLength: 18,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco('CLABE interbancaria (18 dígitos)', Icons.account_balance_outlined)
                  .copyWith(counterText: ''),
            ),
            const SizedBox(height: 28),
          ],

          // ── Tarjeta de banco ─────────────────────────────────────────────────
          _SectionLabel('Tarjeta de banco'),
          const SizedBox(height: 12),
          _CardPreview(
            number: _cardNumCtrl.text,
            expiry: _cardExpCtrl.text,
            name:   _cardNameCtrl.text,
            color:  avatarColor,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cardNumCtrl,
            style: TextStyle(color: inputText, fontSize: 16, letterSpacing: 2),
            keyboardType: TextInputType.number,
            maxLength: 19,
            inputFormatters: [_CardNumberFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco('Número de tarjeta', Icons.credit_card).copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cardExpCtrl,
                style: TextStyle(color: inputText, fontSize: 16),
                keyboardType: TextInputType.number,
                maxLength: 5,
                inputFormatters: [_ExpiryFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: _inputDeco('MM/AA', Icons.calendar_today_outlined).copyWith(counterText: ''),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _cvvCtrl,
                style: TextStyle(color: inputText, fontSize: 16),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: !_showCvv,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDeco('CVV', Icons.lock_outline).copyWith(
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_showCvv ? Icons.visibility_off : Icons.visibility,
                        color: cardSub, size: 18),
                    onPressed: () => setState(() => _showCvv = !_showCvv),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _cardNameCtrl,
            style: TextStyle(color: inputText, fontSize: 16),
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: _inputDeco('Nombre en la tarjeta', Icons.person_outline),
          ),
          const SizedBox(height: 40),

          // ── Sesión ──────────────────────────────────────────────────────────
          _SectionLabel('Sesión'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.logout, color: Colors.orange, size: 20),
                ),
                title: Text('Cerrar sesión', style: TextStyle(color: cardText, fontWeight: FontWeight.w600)),
                subtitle: Text('Mantiene tus datos guardados', style: TextStyle(color: cardSub, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: cardChev),
                onTap: () async {
                  final router = GoRouter.of(context);
                  await AuthService.clearSession();
                  if (!mounted) return;
                  router.go('/login');
                },
              ),
              Divider(height: 1, color: cardDiv, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.restart_alt, color: Colors.redAccent, size: 20),
                ),
                title: const Text('Reiniciar aplicación',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                subtitle: Text('Borra todos tus datos y empieza de cero',
                    style: TextStyle(color: cardSub, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: cardChev),
                onTap: () => _confirmarReinicio(),
              ),
            ]),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _confirmarReinicio() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Reiniciar todo?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Se borrarán tu sesión, datos de perfil, historial de pedidos y direcciones guardadas.\n\nEsta acción no se puede deshacer.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () async {
              final router = GoRouter.of(context);
              Navigator.pop(ctx);
              await AuthService.clearAll();
              if (!mounted) return;
              router.go('/login');
            },
            child: const Text('Sí, reiniciar', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black38),
      prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
      filled: true,
      fillColor: isDark ? AppConstants.surfaceColor : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
    );
  }
}

// ── Card Preview ─────────────────────────────────────────────────────────────

class _CardPreview extends StatelessWidget {
  final String number, expiry, name;
  final Color color;
  const _CardPreview({required this.number, required this.expiry, required this.name, required this.color});

  String _masked(String raw) {
    final digits = raw.replaceAll(' ', '');
    if (digits.isEmpty) return '•••• •••• •••• ••••';
    final buf = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(i < digits.length ? digits[i] : '•');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          // Círculos decorativos
          Positioned(top: -20, right: -20,
            child: Container(width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Positioned(bottom: -30, right: 30,
            child: Container(width: 80, height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.credit_card, color: Colors.white, size: 28),
                  const Spacer(),
                  Text('BANCO', style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 2)),
                ]),
                const Spacer(),
                Text(_masked(number),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
                        letterSpacing: 3, fontFamily: 'monospace')),
                const SizedBox(height: 16),
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TITULAR', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1)),
                    Text(name.isEmpty ? '••••••••••' : name.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                  const Spacer(),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('VENCE', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1)),
                    Text(expiry.isEmpty ? '••/••' : expiry,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formatters ────────────────────────────────────────────────────────────────

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    if (digits.length > 4) return oldValue;
    String text = digits;
    if (digits.length >= 3) {
      text = '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else if (digits.length == 2 && oldValue.text.length < newValue.text.length) {
      text = '$digits/';
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// ── Widgets pequeños ──────────────────────────────────────────────────────────

class _ProfileImage extends StatelessWidget {
  final String path;
  final double size;
  const _ProfileImage({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover, width: size, height: size,
          errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white));
    }
    return Image.file(File(path), fit: BoxFit.cover, width: size, height: size,
        errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, shadows: [
          Shadow(color: Colors.black26, blurRadius: 4),
        ]));
  }
}
