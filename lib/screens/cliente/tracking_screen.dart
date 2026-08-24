// tracking_screen.dart
// Pantalla de seguimiento del pedido en tiempo real.
// El cliente ve el mapa con flutter_map (OpenStreetMap) mostrando:
//   - La posición del restaurante y la dirección de entrega
//   - La posición actual del repartidor (se actualiza cada 4 segundos)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/rider_achievements.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_history_service.dart';
import '../../services/supabase_service.dart';
import '../rating_dialog.dart';

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
  final String? restaurantImageUrl;

  const TrackingScreen({
    super.key,
    required this.restaurantName,
    required this.address,
    required this.total,
    this.orderId = 'o1',
    this.lat,
    this.lng,
    this.restaurantImageUrl,
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
  String? _repartidorId;
  String? _repartidorName;
  String? _repartidorAvatarUrl;
  bool _repartidorAvatarFailed = false;
  bool _restaurantLogoFailed = false;
  int _repartidorRepartos = 0;
  int _repartidorNivel = 1;
  List<ll.LatLng> _routePoints = [];

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

  // Mismo patrón OSRM que usa el repartidor en entrega_activa_screen.dart —
  // se calcula una sola vez al pasar a "en camino", no en cada sondeo, para
  // no saturar la API pública de rutas.
  Future<void> _fetchRoute(ll.LatLng from, ll.LatLng to) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url, headers: {'User-Agent': 'GOGOFood/1.0'})
          .timeout(const Duration(seconds: 10));
      if (!mounted || res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final coords = routes[0]['geometry']['coordinates'] as List;
      setState(() {
        _routePoints = coords
            .map((c) => ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _pollLocation() async {
    final loc = await SupabaseService.getRepartidorLocation(widget.orderId);
    if (!mounted || loc == null) return;
    final pos = ll.LatLng(loc.lat, loc.lng);
    setState(() => _motoPos = pos);
    if (_step >= 1) _mapCtrl.move(pos, 15.5);
    _pushWidgetData();
  }

  Future<void> _geocodeAddress() async {
    if (widget.lat != null && widget.lng != null) {
      setState(() => _customerPos = ll.LatLng(widget.lat!, widget.lng!));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapCtrl.move(_customerPos, 15.0);
      });
      _pushWidgetData();
      return;
    }
    if (widget.address.trim().isEmpty) return;
    final result = await LocationService.geocodeAddress(widget.address);
    if (!mounted) return;
    if (result == null) {
      setState(() => _geocodeFailed = true);
      _pushWidgetData();
      return;
    }
    setState(() {
      _customerPos = ll.LatLng(result.lat, result.lng);
      _geocodeFailed = false;
    });
    _mapCtrl.move(_customerPos, 15.0);
    _pushWidgetData();
  }

  Future<void> _pollStatus() async {
    try {
      final s = await SupabaseService.getOrderStatus(widget.orderId) ?? 'pending';
      if (!mounted) return;
      if (s != _orderStatus) {
        if (s == 'accepted') {
          NotificationService.pedidoAceptado();
          setState(() => _routePoints = []);
          _fetchRoute(_motoPos, _kRestaurantPos);
        }
        if (s == 'delivering') {
          NotificationService.repartidorEnCamino();
          setState(() => _routePoints = []);
          _fetchRoute(_motoPos, _customerPos);
        }
        if (s == 'delivered')  NotificationService.pedidoEntregado();
        setState(() => _orderStatus = s);
        if (s == 'delivered' || s == 'cancelled') {
          _pollTimer?.cancel();
          _pollTimer = null;
          setState(() => _routePoints = []);
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
      }
      // Una vez aceptado el pedido ya hay repartidor asignado — se busca su
      // nombre/foto solo una vez (no en cada sondeo) para mostrarlos arriba.
      if (_repartidorId == null && s != 'pending' && s != 'cancelled') {
        _loadRepartidorProfile();
      }
      // Se manda en cada sondeo (no solo cuando cambia) para que el widget de
      // pantalla de inicio siempre tenga la posición del repartidor y el
      // estado más recientes mientras la app está abierta.
      _pushWidgetData();
    } catch (_) {}
  }

  void _reportAvatarLoadError(Object err) {
    if (!mounted || _repartidorAvatarFailed) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('DEBUG avatar error: $_repartidorAvatarUrl -> $err'),
      duration: const Duration(seconds: 20),
      backgroundColor: Colors.black,
    ));
    setState(() => _repartidorAvatarFailed = true);
  }

  Future<void> _loadRepartidorProfile() async {
    final riderId = await SupabaseService.getOrderRepartidorId(widget.orderId);
    if (!mounted || riderId == null) return;
    setState(() => _repartidorId = riderId);
    final profile = await SupabaseService.getOrderCounterpartProfile(widget.orderId, riderId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('DEBUG avatar: ${profile == null ? "profile es null (falló la llamada)" : profile.toString()}'),
        duration: const Duration(seconds: 20),
        backgroundColor: Colors.black,
      ));
    }
    if (!mounted || profile == null) return;
    setState(() {
      _repartidorName = profile['name'] as String?;
      _repartidorAvatarUrl = profile['avatarUrl'] as String?;
      _repartidorRepartos = profile['repartos'] as int? ?? 0;
      _repartidorNivel = profile['nivel'] as int? ?? 1;
    });
  }

  void _showRepartidorDetail() {
    final earned = kRiderAchievements.where((a) => _repartidorRepartos >= a.repartos).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.15),
              backgroundImage: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty && !_repartidorAvatarFailed)
                  ? NetworkImage(_repartidorAvatarUrl!)
                  : null,
              onBackgroundImageError: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty)
                  ? (err, __) => _reportAvatarLoadError(err)
                  : null,
              child: (_repartidorAvatarUrl == null || _repartidorAvatarUrl!.isEmpty || _repartidorAvatarFailed)
                  ? const Icon(Icons.delivery_dining_rounded, color: AppConstants.primaryColor, size: 26)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_repartidorName ?? 'Tu repartidor',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 2),
                Text('Nivel $_repartidorNivel · $_repartidorRepartos entregas',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Medallas', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (earned.isEmpty)
            Text('Todavía no tiene medallas — apenas está empezando.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: earned.map((a) => Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(a.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(a.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ]),
              )).toList(),
            ),
        ]),
      ),
    );
  }

  // Comparte el pedido activo con el widget de pantalla de inicio (WidgetKit)
  // vía el App Group — así se puede ver el estado sin abrir la app. El widget
  // también se refresca solo cada ~15 min consultando Supabase directamente
  // (con el orderId/authToken guardados aquí), por si la app está cerrada.
  Future<void> _pushWidgetData() async {
    try {
      final active = !_isCancelled && _step < 3;
      final label  = _isCancelled ? 'Pedido cancelado' : _statusData[_step].label;
      await HomeWidget.saveWidgetData<String>('orderId', widget.orderId);
      await HomeWidget.saveWidgetData<String>(
          'authToken', Supabase.instance.client.auth.currentSession?.accessToken ?? '');
      await HomeWidget.saveWidgetData<String>('restaurantName', widget.restaurantName);
      await HomeWidget.saveWidgetData<String>(
          'restaurantImageUrl', widget.restaurantImageUrl ?? '');
      await HomeWidget.saveWidgetData<String>('address', widget.address);
      await HomeWidget.saveWidgetData<double>('total', widget.total);
      await HomeWidget.saveWidgetData<double>('restaurantLat', _kRestaurantPos.latitude);
      await HomeWidget.saveWidgetData<double>('restaurantLng', _kRestaurantPos.longitude);
      await HomeWidget.saveWidgetData<double>('customerLat', _customerPos.latitude);
      await HomeWidget.saveWidgetData<double>('customerLng', _customerPos.longitude);
      await HomeWidget.saveWidgetData<double>('motoLat', _motoPos.latitude);
      await HomeWidget.saveWidgetData<double>('motoLng', _motoPos.longitude);
      await HomeWidget.saveWidgetData<bool>('hasActiveOrder', active);
      await HomeWidget.saveWidgetData<String>('statusText', label);
      await HomeWidget.saveWidgetData<int>('stepIndex', _step);
      await HomeWidget.updateWidget(iOSName: 'GOGOTrackingWidget');
      await HomeWidget.updateWidget(iOSName: 'GOGOTrackingStepsWidget');
    } catch (_) {}
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
            // Línea de ruta: repartidor → restaurante (paso 1) y luego
            // repartidor → cliente (paso 2). Se recalcula al cambiar de
            // tramo (_fetchRoute en _pollStatus); no se muestra ya
            // entregado/cancelado.
            if (_routePoints.isNotEmpty && _step >= 1 && _step < 3)
              PolylineLayer(polylines: [
                Polyline(
                  points: _routePoints,
                  strokeWidth: 5.0,
                  color: const Color(0xFF2196F3),
                  borderColor: Colors.white.withValues(alpha: 0.6),
                  borderStrokeWidth: 2.0,
                ),
              ]),
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
              // Nunca se muestra ya entregado/cancelado — si no, un pedido
              // viejo reabierto desde el historial se ve con al repartidor
              // "parado" en su última posición real, aunque ya haya terminado.
              if (_step >= 1 && _step < 3)
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
            child: Column(children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Salir del mapa sin cancelar el pedido — vuelve a
                  // restaurantes, donde el banner "Seguimiento" deja regresar.
                  GestureDetector(
                    onTap: () => context.go('/restaurants'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceColor.withValues(alpha: 0.96),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
                ],
              ),
            ]),
          ),
        ),

        // ── Panel inferior ────────────────────────────────────────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Tarjeta del repartidor — propia, arriba del panel del pedido.
            // Al tocarla muestra su nivel, entregas y medallas.
            if (_repartidorId != null && _step >= 1 && _step < 3)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _showRepartidorDetail,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceColor,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 16),
                        ],
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.12),
                          backgroundImage: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty && !_repartidorAvatarFailed)
                              ? NetworkImage(_repartidorAvatarUrl!)
                              : null,
                          onBackgroundImageError: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty)
                              ? (err, __) => _reportAvatarLoadError(err)
                              : null,
                          child: (_repartidorAvatarUrl == null || _repartidorAvatarUrl!.isEmpty || _repartidorAvatarFailed)
                              ? const Icon(Icons.delivery_dining_rounded, color: AppConstants.primaryColor, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _repartidorName ?? 'Tu repartidor',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
            Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              // Mismo naranja que el widget de pantalla de inicio
              // (GOGOTrackingWidget.swift) — a propósito el mismo look.
              color: AppConstants.primaryColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 40, height: 40,
                    color: Colors.white.withValues(alpha: 0.18),
                    child: (widget.restaurantImageUrl != null &&
                            widget.restaurantImageUrl!.isNotEmpty &&
                            !_restaurantLogoFailed)
                        ? Image.network(
                            widget.restaurantImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _restaurantLogoFailed = true);
                              });
                              return const Icon(Icons.storefront_rounded, color: Colors.white, size: 22);
                            },
                          )
                        : const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                  ),
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
                              color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text('\$${widget.total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _step / 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(_statusData.length, (i) {
                  final done   = i < _step;
                  final active = i == _step;
                  final sd     = _statusData[i];
                  final color  = done ? Colors.blue : active ? sd.color : Colors.white.withValues(alpha: 0.4);
                  return Expanded(
                    child: Column(children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: (done || active)
                              ? color.withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: (done || active) ? Colors.white.withValues(alpha: 0.6) : Colors.transparent,
                              width: 1.5),
                        ),
                        child: Icon(done ? Icons.check : sd.icon,
                            color: (done || active) ? Colors.white : color, size: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i == 0 ? 'Recibido' : i == 1 ? 'Preparando' : i == 2 ? 'En camino' : 'Entregado',
                        style: TextStyle(
                            fontSize: 9,
                            color: (done || active)
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5)),
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
                      backgroundColor: Colors.white,
                      foregroundColor: AppConstants.primaryColor,
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
          ]),
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
