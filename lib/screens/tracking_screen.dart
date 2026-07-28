// tracking_screen.dart
// Pantalla de seguimiento del pedido en tiempo real.
// El cliente ve el mapa con flutter_map (OpenStreetMap) mostrando:
//   - La posición del restaurante y la dirección de entrega
//   - La posición actual del repartidor (se actualiza cada 4 segundos)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/order_history_service.dart';
import '../services/supabase_service.dart';
import 'rating_dialog.dart';

const _kRestaurantPos = ll.LatLng(19.9020, -100.4510);
const _kCustomerPos   = ll.LatLng(19.8900, -100.4370);
const _kCenter        = ll.LatLng(19.8960, -100.4440);

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
  final _mapCtrl = MapController();
  Timer? _pollTimer;

  ll.LatLng _motoPos     = _kRestaurantPos;
  ll.LatLng _customerPos = _kCustomerPos;
  String _orderStatus = 'pending';
  bool _geocodeFailed = false;

  int get _step {
    switch (_orderStatus) {
      case 'accepted':   return 1;
      case 'delivering': return 2;
      case 'delivered':  return 3;
      case 'cancelled':  return 0;
      default:           return 0;
    }
  }

  bool get _isCancelled => _orderStatus == 'cancelled';

  static final _statusData = [
    (icon: Icons.hourglass_top_rounded, label: 'Pedido recibido',              color: const Color(0xFFFFB300)),
    (icon: Icons.restaurant_outlined,   label: 'Repartidor va al restaurante', color: AppConstants.primaryColor),
    (icon: Icons.delivery_dining,       label: 'Repartidor en camino',         color: const Color(0xFF2196F3)),
    (icon: Icons.check_circle_rounded,  label: '¡Pedido entregado!',           color: Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    _pollStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollStatus();
      _pollLocation();
    });
    _geocodeAddress();
  }

  Future<void> _pollLocation() async {
    final loc = await SupabaseService.getRepartidorLocation(widget.orderId);
    if (!mounted || loc == null) return;
    final pos = ll.LatLng(loc.lat, loc.lng);
    setState(() => _motoPos = pos);
    if (_step >= 1) _mapCtrl.move(pos, 15.5);
  }

  Future<void> _geocodeAddress() async {
    if (widget.lat != null && widget.lng != null) {
      setState(() => _customerPos = ll.LatLng(widget.lat!, widget.lng!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapCtrl.move(_customerPos, 15.0);
      });
      return;
    }
    if (widget.address.trim().isEmpty) return;
    final result = await LocationService.geocodeAddress(widget.address);
    if (!mounted) return;
    if (result == null) {
      setState(() => _geocodeFailed = true);
      return;
    }
    setState(() {
      _customerPos = ll.LatLng(result.lat, result.lng);
      _geocodeFailed = false;
    });
    _mapCtrl.move(_customerPos, 15.0);
  }

  Future<void> _pollStatus() async {
    try {
      final s = await SupabaseService.getOrderStatus(widget.orderId) ?? 'pending';
      if (!mounted) return;
      _updateHomeWidget(s);
      if (s == _orderStatus) return;
      if (s == 'accepted')   NotificationService.pedidoAceptado();
      if (s == 'delivering') NotificationService.repartidorEnCamino();
      if (s == 'delivered')  NotificationService.pedidoEntregado();
      setState(() => _orderStatus = s);
      if (s == 'delivered' || s == 'cancelled') {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
      if (s == 'delivered') {
        await OrderHistoryService.clearActiveOrder();
        if (mounted) {
          await showRatingDialog(context, orderId: widget.orderId, isDriver: false);
        }
      }
      if (s == 'cancelled') {
        await OrderHistoryService.clearActiveOrder();
      }
    } catch (_) {}
  }

  // Guarda el estado del pedido (y coordenadas para el mini-mapa) para el
  // widget de pantalla de inicio (iOS). No espera a que Supabase/Home Widget
  // respondan — no debe frenar el polling.
  void _updateHomeWidget(String status) {
    final active = status != 'delivered' && status != 'cancelled';
    HomeWidget.saveWidgetData<bool>('hasActiveOrder', active);
    // El widget consulta Supabase directo cuando la app está cerrada — necesita
    // el id del pedido y una sesión con la que autenticar esa consulta.
    HomeWidget.saveWidgetData<String>('orderId', widget.orderId);
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) HomeWidget.saveWidgetData<String>('authToken', token);
    if (active) {
      final stepIndex = status == 'accepted' ? 1 : (status == 'delivering' ? 2 : 0);
      HomeWidget.saveWidgetData<String>('restaurantName', widget.restaurantName);
      HomeWidget.saveWidgetData<String>('statusText', _statusData[stepIndex].label);
      HomeWidget.saveWidgetData<String>('address', widget.address);
      HomeWidget.saveWidgetData<double>('total', widget.total);
      // Pasos para la tarjeta de seguimiento: 0=Recibido 1=Preparando 2=En camino 3=Entregado
      final cardStep = status == 'accepted' ? 1 : (status == 'delivering' ? 2 : 0);
      HomeWidget.saveWidgetData<int>('stepIndex', cardStep);
      HomeWidget.saveWidgetData<double>('restaurantLat', _kRestaurantPos.latitude);
      HomeWidget.saveWidgetData<double>('restaurantLng', _kRestaurantPos.longitude);
      HomeWidget.saveWidgetData<double>('customerLat', _customerPos.latitude);
      HomeWidget.saveWidgetData<double>('customerLng', _customerPos.longitude);
      HomeWidget.saveWidgetData<double>('motoLat', _motoPos.latitude);
      HomeWidget.saveWidgetData<double>('motoLng', _motoPos.longitude);
    } else {
      HomeWidget.saveWidgetData<int>('stepIndex', 3);
    }
    HomeWidget.updateWidget(iOSName: 'GOGOTrackingWidget');
    HomeWidget.updateWidget(iOSName: 'GOGOTrackingStepsWidget');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await SupabaseService.updateOrderStatus(widget.orderId, 'cancelled');
              await OrderHistoryService.clearActiveOrder();
              if (mounted) context.go('/restaurants');
            },
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String get _eta {
    if (_isCancelled) return 'El pedido fue cancelado';
    switch (_step) {
      case 0: return 'Esperando confirmación';
      case 1: return 'El repartidor va al restaurante';
      case 2: return 'En camino a tu domicilio';
      default: return 'Entregado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sd = _isCancelled
        ? (icon: Icons.cancel_outlined, label: 'Pedido cancelado', color: Colors.redAccent)
        : _statusData[_step];

    return Scaffold(
      body: Stack(children: [
        // ── Mapa OpenStreetMap (flutter_map — funciona en web y móvil) ──────────
        FlutterMap(
          mapController: _mapCtrl,
          options: const MapOptions(initialCenter: _kCenter, initialZoom: 14.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fercadi.app',
            ),
            MarkerLayer(markers: [
              Marker(
                point: _kRestaurantPos,
                child: const _MapPin(icon: Icons.storefront_rounded, color: AppConstants.primaryColor),
              ),
              // Solo mostrar pin del cliente si tenemos coordenadas exactas
              if (!_geocodeFailed)
                Marker(
                  point: _customerPos,
                  child: const _MapPin(icon: Icons.home_rounded, color: Color(0xFF2196F3)),
                ),
              if (_step >= 1)
                Marker(
                  point: _motoPos,
                  child: _PulsingPin(color: const Color(0xFFFF6D00)),
                ),
            ]),
          ],
        ),

        // ── Aviso dirección sin coordenadas exactas ────────────────────────────
        if (_geocodeFailed)
          Positioned(
            bottom: 210,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10)],
              ),
              child: Row(children: [
                const Icon(Icons.local_shipping_outlined, color: AppConstants.primaryColor, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tu repartidor llevará el pedido usando la dirección que escribiste.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ),

        // ── Tarjeta de estado (arriba) ────────────────────────────────────────
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
                if (_step >= 1 && _step < 3)
                  _PulsingDot(color: sd.color),
              ]),
            ),
          ),
        ),

        // ── Panel inferior ────────────────────────────────────────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: AppConstants.surfaceColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
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
                          color: (done || active)
                              ? color.withValues(alpha: 0.15)
                              : AppConstants.surface2Color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: (done || active) ? color : Colors.transparent,
                              width: 1.5),
                        ),
                        child: Icon(done ? Icons.check : sd.icon, color: color, size: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i == 0 ? 'Recibido' : i == 1 ? 'Preparando' : i == 2 ? 'En camino' : 'Entregado',
                        style: TextStyle(
                            fontSize: 9,
                            color: (done || active)
                                ? Colors.white.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.2)),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  );
                }),
              ),
              const SizedBox(height: 10),
              if (_isCancelled) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/restaurants'),
                    icon: const Icon(Icons.storefront),
                    label: const Text('Pedir de nuevo',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ] else if (_step == 0) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmarCancelacion,
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
              if (!_isCancelled && _step == 3) ...[
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
      ]),
    );
  }
}

// ── Pin del mapa ──────────────────────────────────────────────────────────────
class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

// ── Pin pulsante para el repartidor ──────────────────────────────────────────
class _PulsingPin extends StatefulWidget {
  final Color color;
  const _PulsingPin({required this.color});

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween(begin: 0.85, end: 1.15).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)],
        ),
        child: const Icon(Icons.delivery_dining, color: Colors.white, size: 22),
      ),
    );
  }
}

// ── Punto pulsante (en tránsito) ──────────────────────────────────────────────
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
