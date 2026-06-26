// flota_screen.dart
// Panel del jefe de flota.
// Muestra en tiempo real a todos sus riders: ubicación, pedido activo y ganancias del día.
// Solo accesible con rol "jefe_flota".

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class FlotaScreen extends StatefulWidget {
  const FlotaScreen({super.key});
  @override
  State<FlotaScreen> createState() => _FlotaScreenState();
}

class _FlotaScreenState extends State<FlotaScreen> {
  List<Map<String, dynamic>> _riders = [];
  Map<String, Map<String, dynamic>> _locations = {};
  Map<String, List<Map<String, dynamic>>> _ordersHoy = {};
  Map<String, Map<String, dynamic>?> _pedidoActivo = {};
  bool _loading = true;
  Timer? _pollTimer;
  String? _jefeId;

  static const _bg      = Color(0xFF0F1117);
  static const _surface = Color(0xFF1A1D27);
  static const _card    = Color(0xFF22263A);
  static const _accent  = Color(0xFF4F8EF7);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _jefeId = Supabase.instance.client.auth.currentUser?.id;
    await _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadAll());
  }

  Future<void> _loadAll() async {
    if (_jefeId == null) return;
    final riders = await SupabaseService.getFlotaRiders(_jefeId!);
    final riderIds = riders.map((r) => r['rider_id'] as String).toList();
    final locations = await SupabaseService.getRiderLocations(riderIds);

    final Map<String, List<Map<String, dynamic>>> orders = {};
    final Map<String, Map<String, dynamic>?> activos = {};
    for (final riderId in riderIds) {
      orders[riderId] = await SupabaseService.getRiderOrdersToday(riderId);
      activos[riderId] = await SupabaseService.getRiderActiveOrder(riderId);
    }

    if (!mounted) return;
    setState(() {
      _riders = riders;
      _locations = locations;
      _ordersHoy = orders;
      _pedidoActivo = activos;
      _loading = false;
    });
  }

  Future<void> _abrirMapa(String riderId) async {
    final loc = _locations[riderId];
    if (loc == null) return;
    final lat = loc['lat'];
    final lng = loc['lng'];
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _isOnline(String riderId) {
    final loc = _locations[riderId];
    if (loc == null) return false;
    final lastSeen = DateTime.tryParse(loc['last_seen'] as String? ?? '');
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen).inMinutes < 5;
  }

  double _gananciaHoy(String riderId) {
    final orders = _ordersHoy[riderId] ?? [];
    return orders
        .where((o) => o['status'] == 'delivered')
        .fold(0.0, (sum, o) => sum + ((o['delivery_fee'] as num?)?.toDouble() ?? 0));
  }

  int _entregasHoy(String riderId) {
    return (_ordersHoy[riderId] ?? [])
        .where((o) => o['status'] == 'delivered')
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final totalOnline = _riders.where((r) => _isOnline(r['rider_id'] as String)).length;
    final totalGanancias = _riders.fold(0.0, (s, r) => s + _gananciaHoy(r['rider_id'] as String));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildSummary(totalOnline, totalGanancias),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _riders.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        color: _accent,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _riders.length,
                          itemBuilder: (_, i) => _buildRiderCard(_riders[i]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D3E))),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.directions_bike_rounded, color: _accent, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mi Flota', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Panel de control', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6B7280)),
          onPressed: _loadAll,
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Color(0xFF6B7280)),
          onPressed: () async {
            await AuthService.clearSession();
            if (mounted) context.go('/');
          },
        ),
      ]),
    );
  }

  Widget _buildSummary(int online, double ganancias) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        _summaryCard(Icons.people_rounded, '${_riders.length}', 'Riders totales', const Color(0xFF4F8EF7)),
        const SizedBox(width: 10),
        _summaryCard(Icons.circle, '$online', 'En línea', const Color(0xFF22C55E)),
        const SizedBox(width: 10),
        _summaryCard(Icons.attach_money_rounded, '\$${ganancias.toStringAsFixed(0)}', 'Ganancias hoy', const Color(0xFFF59E0B)),
      ]),
    );
  }

  Widget _summaryCard(IconData icon, String value, String label, Color color) {
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
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildRiderCard(Map<String, dynamic> rider) {
    final riderId = rider['rider_id'] as String;
    final name    = rider['rider_name'] as String? ?? 'Rider';
    final email   = rider['rider_email'] as String? ?? '';
    final online  = _isOnline(riderId);
    final activo  = _pedidoActivo[riderId];
    final entregas = _entregasHoy(riderId);
    final ganancia = _gananciaHoy(riderId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: online ? const Color(0xFF22C55E).withValues(alpha: 0.3) : const Color(0xFF2A2D3E),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header del rider
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _accent.withValues(alpha: 0.15),
              child: Text(name[0].toUpperCase(),
                  style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Text(email, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            ])),
            // Indicador online/offline
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (online ? const Color(0xFF22C55E) : const Color(0xFF6B7280)).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 4,
                  backgroundColor: online ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Text(
                  online ? 'En línea' : 'Inactivo',
                  style: TextStyle(
                    color: online ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF2A2D3E), height: 1),
          const SizedBox(height: 14),
          // Stats del día
          Row(children: [
            _statChip(Icons.check_circle_outline_rounded, '$entregas', 'entregas hoy', const Color(0xFF4F8EF7)),
            const SizedBox(width: 10),
            _statChip(Icons.attach_money_rounded, '\$${ganancia.toStringAsFixed(0)}', 'ganado hoy', const Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            // Pedido activo
            if (activo != null)
              _statChip(Icons.delivery_dining_rounded, 'Entregando', activo['address'] as String? ?? '', const Color(0xFF22C55E))
            else
              _statChip(Icons.hourglass_empty_rounded, online ? 'Esperando' : 'Sin app', 'pedido', const Color(0xFF6B7280)),
          ]),
          // Mini mapa
          const SizedBox(height: 12),
          _buildMiniMapa(riderId),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _locations.containsKey(riderId) ? () => _abrirMapa(riderId) : null,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir en Google Maps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }

  Widget _buildMiniMapa(String riderId) {
    final loc = _locations[riderId];
    if (loc == null) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_off_rounded, color: Colors.white.withValues(alpha: 0.15), size: 32),
            const SizedBox(height: 8),
            Text('Sin ubicación aún',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13)),
          ]),
        ),
      );
    }
    final lat = (loc['lat'] as num).toDouble();
    final lng = (loc['lng'] as num).toDouble();
    final point = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 150,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fercadi.app',
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 48,
                height: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 3))],
                      ),
                      child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 22),
                    ),
                    CustomPaint(
                      size: const Size(14, 8),
                      painter: _PinTailPainter(_accent),
                    ),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_bike_outlined, size: 64, color: Colors.white.withValues(alpha: 0.1)),
        const SizedBox(height: 16),
        const Text('Sin riders asignados', style: TextStyle(color: Color(0xFF6B7280), fontSize: 16)),
        const SizedBox(height: 8),
        const Text('El administrador de Fercadi\ndebe vincular tus riders.',
            style: TextStyle(color: Color(0xFF4B5563), fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}
