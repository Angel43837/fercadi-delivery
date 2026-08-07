// flota_rider_detail_screen.dart
// Vista de detalle de un motociclista dentro del panel de flota:
// datos personales, estado actual, estadísticas e historial de entregas.
// Incluye edición de perfil (nombre, teléfono, correo, foto, placa).

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';

enum _RiderStatus { activo, ocupado, desconectado }

class RiderDetailScreen extends StatefulWidget {
  final String riderId;
  final Map<String, dynamic>? initialData;
  const RiderDetailScreen({super.key, required this.riderId, this.initialData});

  @override
  State<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends State<RiderDetailScreen> {
  static const _bg      = Color(0xFF0F1117);
  static const _surface = Color(0xFF1A1D27);
  static const _card    = Color(0xFF22263A);
  static const _accent  = Color(0xFF4F8EF7);
  static const _muted   = Color(0xFF6B7280);
  static const _border  = Color(0xFF2A2D3E);

  bool _loading = true;
  String _name = '';
  String _email = '';
  String? _phone;
  String? _plate;
  String? _photoUrl;
  Map<String, dynamic>? _location;
  Map<String, dynamic>? _activeOrder;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _name  = widget.initialData?['rider_name'] as String? ?? '';
    _email = widget.initialData?['rider_email'] as String? ?? '';
    _plate = widget.initialData?['rider_plate'] as String?;
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SupabaseService.getRiderLocations([widget.riderId]),
      SupabaseService.getRiderActiveOrder(widget.riderId),
      SupabaseService.getRiderOrderHistory(widget.riderId),
      SupabaseService.getRiderAuthProfile(widget.riderId),
      SupabaseService.getFlotaMember(widget.riderId),
    ]);
    if (!mounted) return;
    final locations    = results[0] as Map<String, Map<String, dynamic>>;
    final activeOrder  = results[1] as Map<String, dynamic>?;
    final history      = results[2] as List<Map<String, dynamic>>;
    final authProfile  = results[3] as Map<String, dynamic>?;
    final flotaMember  = results[4] as Map<String, dynamic>?;
    final meta = authProfile?['user_metadata'] as Map<String, dynamic>?;
    setState(() {
      _location    = locations[widget.riderId];
      _activeOrder = activeOrder;
      _history     = history;
      if (flotaMember != null) {
        _name  = (flotaMember['rider_name']  as String?) ?? _name;
        _email = (flotaMember['rider_email'] as String?) ?? _email;
        _plate = flotaMember['rider_plate'] as String?;
      }
      if (meta != null) {
        _name     = (meta['name'] as String?) ?? _name;
        _phone    = meta['phone'] as String?;
        _photoUrl = meta['avatar_url'] as String?;
      }
      _email   = (authProfile?['email'] as String?) ?? _email;
      _loading = false;
    });
  }

  bool get _isOnline {
    final lastSeen = DateTime.tryParse(_location?['last_seen'] as String? ?? '');
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen).inMinutes < 5;
  }

  _RiderStatus get _status {
    if (!_isOnline) return _RiderStatus.desconectado;
    if (_activeOrder != null) return _RiderStatus.ocupado;
    return _RiderStatus.activo;
  }

  List<Map<String, dynamic>> get _entregados =>
      _history.where((o) => o['status'] == 'delivered').toList();

  int get _totalEntregas => _entregados.length;

  double get _totalRecaudado => _entregados.fold(
      0.0, (s, o) => s + ((o['delivery_fee'] as num?)?.toDouble() ?? 0));

  List<Map<String, dynamic>> get _semanaPasada {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _entregados.where((o) {
      final d = DateTime.tryParse(o['created_at'] as String? ?? '');
      return d != null && d.isAfter(weekAgo);
    }).toList();
  }

  int get _entregasSemana => _semanaPasada.length;

  double get _recaudadoSemana => _semanaPasada.fold(
      0.0, (s, o) => s + ((o['delivery_fee'] as num?)?.toDouble() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_name.isEmpty ? 'Rider' : _name,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            onPressed: _loading ? null : _showEditSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 16),
                  _buildStatsGrid(),
                  const SizedBox(height: 20),
                  const Text('Historial de entregas',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Sin entregas registradas', style: TextStyle(color: _muted)),
                      ),
                    )
                  else
                    ..._history.map(_buildHistoryRow),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard() {
    final (label, color) = switch (_status) {
      _RiderStatus.activo        => ('Activo', const Color(0xFF22C55E)),
      _RiderStatus.ocupado       => ('Ocupado', _accent),
      _RiderStatus.desconectado  => ('Desconectado', _muted),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: _accent.withValues(alpha: 0.15),
            backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
            child: _photoUrl == null
                ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                    style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 24))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.isEmpty ? 'Rider' : _name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 4, backgroundColor: color),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 12),
        _infoRow(Icons.email_outlined, 'Correo', _email.isEmpty ? '—' : _email),
        const SizedBox(height: 10),
        _infoRow(Icons.phone_outlined, 'Teléfono', (_phone == null || _phone!.isEmpty) ? '—' : _phone!),
        const SizedBox(height: 10),
        _infoRow(Icons.pin_outlined, 'Placa', (_plate == null || _plate!.isEmpty) ? 'Sin registrar' : _plate!),
        if (_status == _RiderStatus.ocupado && _activeOrder != null) ...[
          const SizedBox(height: 10),
          _infoRow(Icons.delivery_dining_rounded, 'Entregando en', _activeOrder!['address'] as String? ?? '—'),
        ],
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: _muted, size: 16),
      const SizedBox(width: 10),
      SizedBox(width: 66, child: Text(label, style: const TextStyle(color: _muted, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _buildStatsGrid() {
    return Column(children: [
      Row(children: [
        _statCard(Icons.check_circle_outline_rounded, '$_totalEntregas', 'Entregas totales', const Color(0xFF4F8EF7)),
        const SizedBox(width: 10),
        _statCard(Icons.payments_rounded, '\$${_totalRecaudado.toStringAsFixed(0)}', 'Recaudado total', const Color(0xFFF59E0B)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _statCard(Icons.date_range_rounded, '$_entregasSemana', 'Entregas (7 días)', const Color(0xFFA855F7)),
        const SizedBox(width: 10),
        _statCard(Icons.savings_rounded, '\$${_recaudadoSemana.toStringAsFixed(0)}', 'Recaudado (7 días)', const Color(0xFF22C55E)),
      ]),
    ]);
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> o) {
    final status  = o['status'] as String? ?? '';
    final total   = (o['total'] as num?)?.toDouble() ?? 0;
    final fee     = (o['delivery_fee'] as num?)?.toDouble() ?? 0;
    final created = DateTime.tryParse(o['created_at'] as String? ?? '')?.toLocal();
    final (label, color) = switch (status) {
      'delivered'  => ('Entregado', const Color(0xFF22C55E)),
      'cancelled'  => ('Cancelado', const Color(0xFFEF4444)),
      'delivering' => ('En camino', _accent),
      'accepted'   => ('Aceptado', const Color(0xFFF59E0B)),
      _            => (status, _muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(created != null ? _fmtDate(created) : '—', style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 2),
            Text('Total: \$${total.toStringAsFixed(0)} · Envío: \$${fee.toStringAsFixed(0)}',
                style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  String _fmtDate(DateTime d) {
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${meses[d.month - 1]}, $hh:$mm';
  }

  Future<void> _showEditSheet() async {
    final nameCtrl  = TextEditingController(text: _name);
    final phoneCtrl = TextEditingController(text: _phone ?? '');
    final emailCtrl = TextEditingController(text: _email);
    final plateCtrl = TextEditingController(text: _plate ?? '');
    String? photoUrl = _photoUrl;
    Uint8List? pickedBytes;
    String? error;
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          ImageProvider? avatarImage;
          if (pickedBytes != null) {
            avatarImage = MemoryImage(pickedBytes!);
          } else if (photoUrl != null) {
            avatarImage = NetworkImage(photoUrl);
          }
          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(
                  child: Text('Editar perfil', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85,
                      );
                      if (picked == null) return;
                      final bytes = await picked.readAsBytes();
                      setS(() => pickedBytes = bytes);
                    },
                    child: Stack(children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: _accent.withValues(alpha: 0.15),
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                                style: const TextStyle(color: _accent, fontSize: 28, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                _field(nameCtrl, 'Nombre', Icons.badge_outlined),
                const SizedBox(height: 12),
                _field(phoneCtrl, 'Teléfono', Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 12),
                _field(emailCtrl, 'Correo electrónico', Icons.email_outlined),
                const SizedBox(height: 12),
                _field(plateCtrl, 'Placa de la moto', Icons.pin_outlined),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : () async {
                      final name  = nameCtrl.text.trim();
                      final email = emailCtrl.text.trim();
                      if (name.isEmpty || email.isEmpty) {
                        setS(() => error = 'Nombre y correo son obligatorios');
                        return;
                      }
                      setS(() { loading = true; error = null; });
                      var newPhotoUrl = photoUrl;
                      if (pickedBytes != null) {
                        newPhotoUrl = await SupabaseService.uploadProfilePhotoBytes(pickedBytes!, widget.riderId);
                      }
                      final err = await SupabaseService.updateFlotaMember(
                        riderId: widget.riderId,
                        name: name,
                        email: email,
                        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                        plate: plateCtrl.text.trim().isEmpty ? null : plateCtrl.text.trim(),
                        photoUrl: newPhotoUrl,
                      );
                      if (err != null) {
                        setS(() { loading = false; error = err; });
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Guardar cambios', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    plateCtrl.dispose();
    await _load();
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {TextInputType? type}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(color: _muted),
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent)),
      ),
    );
  }
}
