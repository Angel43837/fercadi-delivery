import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/location_service.dart';
import '../services/order_history_service.dart';
import '../services/supabase_service.dart';

// Coordenadas mock dentro de Maravatío, Mich.
const _kRestaurantPos = LatLng(19.9020, -100.4510);
const _kCustomerPos   = LatLng(19.8900, -100.4370);
const _kCenter        = LatLng(19.8960, -100.4440);

class TrackingScreen extends StatefulWidget {
  final String restaurantName;
  final String address;
  final double total;
  final String orderId;
  final double? lat;
  final double? lng;

  const TrackingScreen({
    super.key,
    required this.restaurantName,
    required this.address,
    required this.total,
    this.orderId = 'o1',
    this.lat,
    this.lng,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final MapController _mapCtrl = MapController();
  Timer? _pollTimer;

  LatLng _motoPos = _kRestaurantPos;
  LatLng _customerPos = _kCustomerPos;
  RealtimeChannel? _realtimeChannel;

  // Estado real del pedido: pending, accepted, delivering, delivered
  String _orderStatus = 'pending';

  // 0=Preparando, 1=Repartidor viene, 2=En camino, 3=Entregado
  int get _step {
    switch (_orderStatus) {
      case 'accepted':   return 1;
      case 'delivering': return 2;
      case 'delivered':  return 3;
      default:           return 0;
    }
  }

  static final _statusData = [
    (icon: Icons.hourglass_top_rounded, label: 'Pedido recibido',           color: const Color(0xFFFFB300)),
    (icon: Icons.restaurant_outlined,   label: 'Repartidor va al restaurante', color: AppConstants.primaryColor),
    (icon: Icons.delivery_dining,       label: 'Repartidor en camino',      color: const Color(0xFF2196F3)),
    (icon: Icons.check_circle_rounded,  label: '¡Pedido entregado!',        color: Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    _realtimeChannel = SupabaseService.subscribeToLocation(
      widget.orderId,
      (lat, lng) {
        if (!mounted) return;
        setState(() => _motoPos = LatLng(lat, lng));
        try { _mapCtrl.move(_motoPos, 15.0); } catch (_) {}
      },
    );
    _pollStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
    _geocodeAddress();
  }

  Future<void> _geocodeAddress() async {
    if (widget.lat != null && widget.lng != null) {
      setState(() => _customerPos = LatLng(widget.lat!, widget.lng!));
      try { _mapCtrl.move(_customerPos, 15.0); } catch (_) {}
      return;
    }
    if (widget.address.trim().isEmpty) return;
    final result = await LocationService.geocodeAddress(widget.address);
    if (!mounted || result == null) return;
    setState(() => _customerPos = LatLng(result.lat, result.lng));
    try { _mapCtrl.move(_customerPos, 15.0); } catch (_) {}
  }

  Future<void> _pollStatus() async {
    try {
      final s = await SupabaseService.getOrderStatus(widget.orderId) ?? 'pending';
      if (!mounted || s == _orderStatus) return;
      setState(() => _orderStatus = s);
      if (s == 'delivered') {
        await OrderHistoryService.clearActiveOrder();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _confirmarCancelacion() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cancelar pedido?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Tu pedido aún está siendo preparado.\n¿Seguro que quieres cancelarlo?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('No, mantener',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.go('/restaurants');
            },
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String get _eta {
    switch (_step) {
      case 0: return 'Esperando confirmación';
      case 1: return 'El repartidor va al restaurante';
      case 2: return 'En camino a tu domicilio';
      default: return 'Entregado';
    }
  }

  List<Marker> get _markers {
    final ms = <Marker>[
      Marker(
        point: _kRestaurantPos,
        width: 48,
        height: 48,
        child: _MapPin(icon: Icons.storefront, color: AppConstants.primaryColor),
      ),
      Marker(
        point: _customerPos,
        width: 48,
        height: 48,
        child: _MapPin(icon: Icons.home, color: const Color(0xFF2196F3)),
      ),
    ];
    if (_step >= 1) {
      ms.add(Marker(
        point: _motoPos,
        width: 52,
        height: 52,
        child: _MapPin(icon: Icons.delivery_dining, color: const Color(0xFFFF6D00)),
      ));
    }
    return ms;
  }

  @override
  Widget build(BuildContext context) {
    final sd = _statusData[_step];

    return Scaffold(
      body: Stack(children: [
        // ── Mapa OpenStreetMap (CartoDB Dark Matter) ─────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: const MapOptions(
            initialCenter: _kCenter,
            initialZoom: 14.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.landing_test',
            ),
            MarkerLayer(markers: _markers),
          ],
        ),

        // ── Tarjeta de estado (arriba) ───────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14),
                ],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sd.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(sd.icon, color: sd.color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(sd.label,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(_eta,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    ],
                  ),
                ),
                if (_step == 1) _PulsingDot(color: sd.color),
              ]),
            ),
          ),
        ),

        // ── Tarjeta del pedido (abajo) ───────────────────────────────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            decoration: BoxDecoration(
              color: AppConstants.surfaceColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.storefront_outlined,
                        color: AppConstants.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.restaurantName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(widget.address,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text('\$${widget.total.toStringAsFixed(0)} MXN',
                      style: const TextStyle(
                          color: AppConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ]),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _step / 3,
                    backgroundColor: AppConstants.surface2Color,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _step == 3 ? Colors.green : AppConstants.primaryColor,
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: List.generate(_statusData.length, (i) {
                    final done   = i < _step;
                    final active = i == _step;
                    final sd     = _statusData[i];
                    final color  = done ? Colors.green : active ? sd.color : Colors.white.withValues(alpha: 0.2);
                    return Expanded(
                      child: Column(children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: (done || active) ? color.withValues(alpha: 0.15) : AppConstants.surface2Color,
                            shape: BoxShape.circle,
                            border: Border.all(color: (done || active) ? color : Colors.transparent, width: 1.5),
                          ),
                          child: Icon(done ? Icons.check : sd.icon, color: color, size: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i == 0 ? 'Recibido' : i == 1 ? 'Preparando' : i == 2 ? 'En camino' : 'Entregado',
                          style: TextStyle(
                              fontSize: 9,
                              color: (done || active) ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.2)),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                if (_step == 0) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmarCancelacion(),
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                      label: const Text('Cancelar pedido',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (_step == 3) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go('/restaurants'),
                      icon: const Icon(Icons.storefront),
                      label: const Text('Pedir de nuevo',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Pin del mapa ─────────────────────────────────────────────────────────────
class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        CustomPaint(size: const Size(12, 7), painter: _PinTailPainter(color)),
      ],
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
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}

// ── Punto pulsante (en tránsito) ─────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
