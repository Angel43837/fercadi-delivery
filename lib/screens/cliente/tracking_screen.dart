// tracking_screen.dart
// Pantalla de seguimiento del pedido en tiempo real.
// El cliente ve el mapa con flutter_map (OpenStreetMap) mostrando:
//   - La posición del restaurante y la dirección de entrega
//   - La posición actual del repartidor (se actualiza cada 4 segundos)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import '../chat_screen.dart';
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
  // Todos los restaurantes del pedido (si el carrito tenía varios a la vez)
  // — se manda al widget nativo para que muestre el logo de cada uno, no
  // solo el de "restaurantName"/"restaurantImageUrl" (que se queda como
  // "Varios restaurantes" sin logo cuando hay más de uno).
  final List<Map<String, String>>? restaurants;

  const TrackingScreen({
    super.key,
    required this.restaurantName,
    required this.address,
    required this.total,
    this.orderId = 'o1',
    this.lat,
    this.lng,
    this.restaurantImageUrl,
    this.restaurants,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _mapCtrl = MapController();
  // Panel inferior: el cliente arrastra la manija para achicar o agrandar
  // SOLO la tarjeta naranja (el panel se queda pegado abajo, no se mueve
  // como bloque) — antes la tarjeta ya "parecía" un sheet (traía su propia
  // manija dibujada) pero estaba fija, sin gesto real de arrastre.
  double _panelHeightFraction = 0.32;
  Timer? _pollTimer;
  // No hay ETA real del backend todavía — se muestra el tiempo transcurrido
  // desde que se abrió esta pantalla (se refresca solo con cada sondeo de
  // 4s, sin Timer aparte).
  final DateTime _startedAt = DateTime.now();

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
      case 'restaurant_accepted': return 1;
      case 'accepted':   return 1;
      case 'delivering': return 2;
      case 'delivered':  return 3;
      case 'cancelled':  return 0;
      default:           return 0;
    }
  }

  bool get _isCancelled => _orderStatus == 'cancelled';

  static final _statusData = [
    (iconAsset: 'assets/images/step_recibido.svg' as String?,   icon: null as IconData?, label: 'Pedido recibido',              color: const Color(0xFFFFB300)),
    (iconAsset: 'assets/images/step_preparando.svg' as String?, icon: null as IconData?, label: 'Repartidor va al restaurante', color: AppConstants.primaryColor),
    (iconAsset: 'assets/images/step_en_camino.svg' as String?,  icon: null as IconData?, label: 'Repartidor en camino',         color: const Color(0xFF2196F3)),
    (iconAsset: 'assets/images/step_entregado.svg' as String?,  icon: null as IconData?, label: '¡Pedido entregado!',           color: Colors.green),
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
        if (s == 'restaurant_accepted') {
          // El restaurante ya confirmó el pedido — todavía no hay repartidor
          // asignado, así que no hay posición de moto para trazar ruta.
          NotificationService.pedidoAceptado();
        }
        if (s == 'accepted') {
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
      // Ya hay repartidor asignado (después de 'restaurant_accepted', cuando
      // alguien reclama el pedido) — se busca su nombre/foto solo una vez
      // (no en cada sondeo) para mostrarlos arriba. 'restaurant_accepted' NO
      // cuenta todavía: el restaurante ya confirmó pero aún no hay repartidor.
      if (_repartidorId == null && s != 'pending' && s != 'restaurant_accepted' && s != 'cancelled') {
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
    // Diagnóstico de por qué la foto del repartidor no cargó — solo en la
    // consola de desarrollo, nunca en pantalla (antes se mostraba en un
    // SnackBar visible para el cliente).
    debugPrint('tracking_screen: avatar del repartidor no cargó ($_repartidorAvatarUrl) -> $err');
    setState(() => _repartidorAvatarFailed = true);
  }

  Future<void> _loadRepartidorProfile() async {
    final riderId = await SupabaseService.getOrderRepartidorId(widget.orderId);
    if (!mounted || riderId == null) return;
    setState(() => _repartidorId = riderId);
    final profile = await SupabaseService.getOrderCounterpartProfile(widget.orderId, riderId);
    // Mismo motivo que arriba: esto se queda solo en la consola.
    debugPrint('tracking_screen: perfil del repartidor -> ${profile ?? "null (falló la llamada)"}');
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
      // Lista de todos los restaurantes del pedido (uno o varios) — el
      // widget nativo la usa para mostrar un logo por cada restaurante en
      // vez de solo el nombre genérico "Varios restaurantes" sin logo.
      final restaurantsForWidget = (widget.restaurants != null && widget.restaurants!.isNotEmpty)
          ? widget.restaurants!
          : [{'name': widget.restaurantName, 'imageUrl': widget.restaurantImageUrl ?? ''}];
      await HomeWidget.saveWidgetData<String>('restaurantsJson', jsonEncode(restaurantsForWidget));
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
      // Nombre/foto del repartidor — vacíos hasta que _loadRepartidorProfile
      // los resuelve (una vez aceptado el pedido); el widget nativo solo
      // muestra la tarjeta blanca de "repartidor confirmado" cuando
      // riderName no está vacío.
      await HomeWidget.saveWidgetData<String>('riderName', _repartidorName ?? '');
      await HomeWidget.saveWidgetData<String>('riderAvatarUrl', _repartidorAvatarUrl ?? '');
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

  String get _elapsedLabel {
    final d = DateTime.now().difference(_startedAt);
    final mm = d.inMinutes;
    final ss = d.inSeconds % 60;
    return '$mm:${ss.toString().padLeft(2, '0')} MIN';
  }

  @override
  Widget build(BuildContext context) {
    final sd = _isCancelled
        ? (iconAsset: null as String?, icon: Icons.cancel_outlined as IconData?, label: 'Pedido cancelado', color: Colors.redAccent)
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
                  width: 72,
                  height: 72,
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
              SizedBox(
                height: 68,
                child: Stack(children: [
                  // Rectángulo de fondo, detrás del botón de regresar y de
                  // la píldora azul.
                  Container(
                    width: 460,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4510C),
                      borderRadius: BorderRadius.circular(47),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0x6E / 255),
                          offset: const Offset(0, 1),
                          blurRadius: 3.8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Salir del mapa sin cancelar el pedido — vuelve a
                    // restaurantes, donde el banner "Seguimiento" deja
                    // regresar.
                    SizedBox(
                      width: 88,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => context.go('/restaurants'),
                          child: Image.asset('assets/images/back_arrow.png', width: 54, height: 54, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA3D8),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(34)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0x6E / 255),
                              offset: const Offset(0, 1),
                              blurRadius: 3.8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Container(
                                width: 32, height: 32,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: sd.iconAsset != null
                                    ? Padding(
                                        padding: const EdgeInsets.all(7),
                                        child: SvgPicture.asset(
                                          sd.iconAsset!,
                                          colorFilter: const ColorFilter.mode(Color(0xFF0EA3D8), BlendMode.srcIn),
                                        ),
                                      )
                                    : Icon(sd.icon, color: const Color(0xFF0EA3D8), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (_step + 1) / 4,
                                    backgroundColor: const Color(0xFFC9B79C),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    minHeight: 6,
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(sd.label.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                              const Spacer(),
                              // Tiempo transcurrido desde que se abrió el
                              // seguimiento (no hay ETA real del backend
                              // todavía) — se actualiza solo cada 4s con el
                              // sondeo normal de la pantalla.
                              Text(_elapsedLabel,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11)),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ]),
              ),
            ]),
          ),
        ),

        // ── Panel inferior ────────────────────────────────────────────────────
        // El cliente arrastra la manija para achicar o agrandar SOLO la
        // tarjeta naranja (su alto cambia con _panelHeightFraction) — el
        // panel en sí no se mueve, sigue pegado abajo con Align.
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Tarjeta del repartidor — propia, arriba del panel del pedido.
            // Al tocarla muestra su nivel, entregas y medallas.
            if (_repartidorId != null && _step >= 1 && _step < 3)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _showRepartidorDetail,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty && !_repartidorAvatarFailed)
                              ? NetworkImage(_repartidorAvatarUrl!)
                              : null,
                          onBackgroundImageError: (_repartidorAvatarUrl != null && _repartidorAvatarUrl!.isNotEmpty)
                              ? (err, __) => _reportAvatarLoadError(err)
                              : null,
                          child: (_repartidorAvatarUrl == null || _repartidorAvatarUrl!.isEmpty || _repartidorAvatarFailed)
                              ? const Icon(Icons.delivery_dining_rounded, color: AppConstants.primaryColor, size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            (_repartidorName ?? 'Tu repartidor').toUpperCase(),
                            style: const TextStyle(
                                color: AppConstants.primaryColor, fontWeight: FontWeight.w800, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_rounded, color: AppConstants.primaryColor, size: 30),
                          tooltip: 'Mensajes',
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              orderId: widget.orderId,
                              counterpartName: _repartidorName ?? 'Tu repartidor',
                              counterpartPhoto: _repartidorAvatarUrl,
                              locked: _orderStatus == 'delivered' || _orderStatus == 'cancelled',
                            ),
                          )),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            Container(
            height: MediaQuery.of(context).size.height * _panelHeightFraction,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            // El recorte por tamaño se hace aquí, a la forma redondeada de la
            // tarjeta (no con un ClipRect adentro) — así el contenido que no
            // cabe se corta contra las esquinas curvas y no contra un
            // rectángulo recto, que además cortaba en seco la sombra del
            // botón "Cancelar pedido" (se veía cuadrada). La sombra de la
            // tarjeta en sí (más abajo) se pinta afuera de este recorte, sin
            // que Container la corte.
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Mismo naranja que el widget de pantalla de inicio
              // (GOGOTrackingWidget.swift) — a propósito el mismo look, ahora
              // calcado también aquí (header GOGOFOOD, precio grande, riel
              // conectando los 4 pasos, texto "Rastrea tu pedido").
              color: AppConstants.primaryColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20),
              ],
            ),
            child: Column(children: [
              // La manija tiene su propio gesto de arrastre (en vez de
              // depender de que el drag "burbujee" desde el contenido de
              // adentro) — mismo arreglo ya aplicado en
              // entrega_activa_screen.dart: sin esto, arrastrar para ABRIR
              // el panel no siempre respondía.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final screenHeight = MediaQuery.of(context).size.height;
                  final delta = details.delta.dy / screenHeight;
                  setState(() {
                    // Tope arriba = su tamaño de reposo (0.42): el card se
                    // puede achicar para ver más mapa, pero nunca crecer más
                    // alto de como se ve normalmente ni "subir" tapando la
                    // pantalla.
                    _panelHeightFraction = (_panelHeightFraction - delta).clamp(0.16, 0.32);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 60, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
              Image.asset('assets/images/gogofood_wordmark.png', width: 93, height: 11),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipOval(
                  child: Container(
                    width: 44, height: 44,
                    color: Colors.white.withValues(alpha: 0.75),
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
                              return Icon(Icons.storefront_rounded, color: AppConstants.primaryColor, size: 22);
                            },
                          )
                        : Icon(Icons.storefront_rounded, color: AppConstants.primaryColor, size: 22),
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
                              fontSize: 16)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.location_on, size: 13, color: Colors.white.withValues(alpha: 0.75)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(widget.address,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('\$${widget.total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 36,
                          height: 1)),
                  Text('MXN',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ]),
              ]),
              const SizedBox(height: 10),
              // Riel conectando los 4 pasos a la altura del centro de las
              // bolitas — mismo look que GOGOTrackingWidget.swift. El inset
              // izq/der se calcula del ancho real (ancho/8 = centro del
              // primer/último círculo dentro de su celda de Expanded) para
              // que la línea nunca sobresalga de los círculos de las puntas
              // sin importar el ancho de la tarjeta. El tramo ya recorrido
              // se pinta azul y más grueso; el que falta, blanco y delgado.
              SizedBox(
                height: 58,
                child: LayoutBuilder(builder: (context, constraints) {
                  final inset = constraints.maxWidth / 8;
                  return Stack(alignment: Alignment.topCenter, children: [
                    Positioned(
                      top: 13,
                      left: inset, right: inset,
                      child: SizedBox(
                        height: 8,
                        child: Row(children: List.generate(3, (i) {
                          final filled = i < _step;
                          return Expanded(
                            child: Center(
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: filled ? Colors.blue : Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          );
                        })),
                      ),
                    ),
                  Row(
                    children: List.generate(4, (i) {
                      final done   = i < _step;
                      final active = i == _step;
                      final on     = done || active;
                      const iconAssets = [
                        'assets/images/step_recibido.svg',
                        'assets/images/step_preparando.svg',
                        'assets/images/step_en_camino.svg',
                        'assets/images/step_entregado.svg',
                      ];
                      return Expanded(
                        child: Column(children: [
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: on ? Colors.blue : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: SvgPicture.asset(
                                iconAssets[i],
                                colorFilter: ColorFilter.mode(
                                  on ? Colors.white : AppConstants.primaryColor,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            i == 0 ? 'RECIBIDO' : i == 1 ? 'PREPARANDO' : i == 2 ? 'EN CAMINO' : 'ENTREGADO',
                            style: const TextStyle(
                                fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      );
                    }),
                  ),
                  ]);
                }),
              ),
              const SizedBox(height: 4),
              const Text('Rastrea Tu Pedido en Tiempo Real',
                  style: TextStyle(
                      color: Color(0xFF0CB6F4), fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              if (_isCancelled) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/restaurants'),
                    icon: const Icon(Icons.storefront),
                    label: const Text('Pedir de nuevo',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppConstants.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),
              ] else if (_step == 0) ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF4510C), Color(0xFFB53F0E)],
                        stops: [0.4327, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0x70 / 255),
                          offset: const Offset(0, 3),
                          blurRadius: 6.4,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _confirmarCancelacion,
                        child: const Center(
                          child: Text('Cancelar pedido',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (!_isCancelled && _step == 3) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/restaurants'),
                    icon: const Icon(Icons.storefront),
                    label: const Text('Pedir de nuevo',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
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
      child: Image.asset('assets/images/moto_repartidor.png', width: 72, height: 72),
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
