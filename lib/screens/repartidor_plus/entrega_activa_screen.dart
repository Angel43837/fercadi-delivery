// entrega_activa_screen.dart
// Pantalla de entrega activa para GOGO Riders (repartidor_plus).
// Muestra el mapa con ruta al restaurante y luego al cliente, y transmite
// la ubicación GPS del repartidor a Supabase para que el cliente lo siga
// en tiempo real desde tracking_screen.dart.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../rating_dialog.dart';

const _defaultRestaurantPos = LatLng(19.8969, -100.4447); // Centro Maravatío

// Mismos colores que la pantalla de entrega de Motos Flota
// (repartidor_screen.dart) para que ambas se vean igual.
const _bg   = AppConstants.primaryColor;
const _card = AppConstants.surfaceColor;

class EntregaActivaScreen extends StatefulWidget {
  final String orderId;
  final String restaurantName;
  final String customerName;
  final String? customerId;
  final String customerPhone;
  final String address;
  final LatLng? customerPos;
  final double total;
  final List<String> items;

  const EntregaActivaScreen({
    super.key,
    required this.orderId,
    required this.restaurantName,
    required this.customerName,
    this.customerId,
    required this.customerPhone,
    required this.address,
    required this.customerPos,
    required this.total,
    required this.items,
  });

  @override
  State<EntregaActivaScreen> createState() => _EntregaActivaScreenState();
}

class _EntregaActivaScreenState extends State<EntregaActivaScreen> with WidgetsBindingObserver {
  int _step = 0; // 0: ve al restaurante, 1: recoge, 2: en camino al cliente

  Position? _myPos;
  StreamSubscription<Position>? _gpsSub;
  Timer? _broadcastTimer;
  Timer? _gpsStuckTimer;
  bool _gpsSeemsStuck = false;
  final _mapCtrl = MapController();
  // Controla el panel deslizable directo desde la manija — sin esto, cuando
  // el contenido de adentro ya está hasta arriba de su propio scroll,
  // arrastrar para ABRIR el panel a veces no respondía (sí para cerrarlo).
  final _sheetController = DraggableScrollableController();

  LatLng? _geocodedCustomerPos;
  bool _geocodeFailed = false;
  String? _customerProfileName;
  String? _customerAvatarUrl;

  List<LatLng> _routePoints = [];
  Color _routeColor = const Color(0xFFFFB300);

  // Secuencia de colores pedida: amarillo → naranja → azul → verde
  // (verde queda reservado para "completado", ver _buildStepper).
  static const _steps = [
    (icon: Icons.store,           label: 'Ve al restaurante',    color: Color(0xFFFFD600)),
    (icon: Icons.shopping_bag,    label: 'Recoge el pedido',     color: AppConstants.primaryColor),
    (icon: Icons.delivery_dining, label: 'En camino al cliente', color: Color(0xFF2196F3)),
    (icon: Icons.check_circle,    label: '¡Pedido entregado!',   color: Colors.green),
  ];

  static const _stepActions = [
    'Ya estoy en el restaurante',
    'Pedido recogido — ¡En camino!',
    'Marcar como entregado',
    'Ver más pedidos',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SupabaseService.startLocationBroadcast(widget.orderId);
    _geocodedCustomerPos = widget.customerPos;
    if (widget.customerPos == null) _geocodeCustomer(widget.address);
    _initGPS();
    _loadCustomerProfile();
  }

  // Nombre/foto reales de la cuenta del cliente (como en Uber) — solo se
  // puede consultar ya como repartidor asignado a este pedido.
  Future<void> _loadCustomerProfile() async {
    if (widget.customerId == null) return;
    final profile = await SupabaseService.getOrderCounterpartProfile(widget.orderId, widget.customerId!);
    if (!mounted || profile == null) return;
    setState(() {
      _customerProfileName = profile['name'] as String?;
      _customerAvatarUrl = profile['avatarUrl'] as String?;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsSub?.cancel();
    _broadcastTimer?.cancel();
    _gpsStuckTimer?.cancel();
    SupabaseService.stopLocationBroadcast();
    _mapCtrl.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Igual que en repartidor_plus_screen: si fue a activar el permiso en
    // Ajustes y regresa, hay que reintentar en vez de dejarlo sin GPS.
    if (state == AppLifecycleState.resumed && _gpsSub == null) {
      _initGPS();
    }
  }

  Future<void> _initGPS() async {
    try {
      if (!mounted) return;
      final granted = await LocationService.ensureLocationPermission(context);
      if (!granted) return;
      // El stream (abajo) puede tardar mucho en entregar su primer punto en
      // frío — antes eso dejaba "Buscando tu ubicación..." pegado hasta que
      // el usuario abría Google Maps (que "despierta" el GPS del sistema) y
      // regresaba. Pedir una posición puntual de una vez tiene el mismo
      // efecto sin depender de salir de la app.
      _seedGpsPosition();
      _gpsStuckTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && _myPos == null) setState(() => _gpsSeemsStuck = true);
      });
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((pos) {
        if (!mounted) return;
        _gpsStuckTimer?.cancel();
        setState(() { _myPos = pos; _gpsSeemsStuck = false; });
        SupabaseService.broadcastLocation(pos.latitude, pos.longitude);
        try { _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.5); } catch (_) {}
        if (_routePoints.isEmpty && _step < 2) {
          _fetchRoute(LatLng(pos.latitude, pos.longitude), _defaultRestaurantPos,
              color: const Color(0xFFFFB300));
        }
      });
    } catch (_) {}
  }

  Future<void> _seedGpsPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted || _myPos != null) return;
      setState(() { _myPos = pos; _gpsSeemsStuck = false; });
      try { _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.5); } catch (_) {}
    } catch (_) {
      // Se queda esperando al stream o al botón "Reintentar" — no es un
      // error que haya que mostrar aparte, solo que este primer intento no dio.
    }
  }

  void _retryGps() {
    _gpsStuckTimer?.cancel();
    setState(() => _gpsSeemsStuck = false);
    _gpsSub?.cancel();
    _gpsSub = null;
    _initGPS();
  }

  Future<void> _geocodeCustomer(String address) async {
    // Reintenta antes de mostrar el aviso de "no encontrada": un solo fallo
    // suele ser un hiccup pasajero de la API de geocoding, no que la
    // dirección de verdad no exista.
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await LocationService.geocodeAddress(address);
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _geocodedCustomerPos = LatLng(result.lat, result.lng);
          _geocodeFailed = false;
        });
        return;
      }
      if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) setState(() => _geocodeFailed = true);
  }

  Future<void> _fetchRoute(LatLng from, LatLng to, {required Color color}) async {
    _routeColor = color;
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
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _avanzarStep() async {
    if (_step < 2) {
      setState(() => _step++);
      if (_step == 2) {
        await SupabaseService.updateOrderStatus(widget.orderId, 'delivering');
        _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_myPos != null) {
            SupabaseService.broadcastLocation(_myPos!.latitude, _myPos!.longitude);
          }
        });
        final clientPos = _geocodedCustomerPos ?? _defaultRestaurantPos;
        final from = _myPos != null
            ? LatLng(_myPos!.latitude, _myPos!.longitude)
            : _defaultRestaurantPos;
        setState(() => _routePoints = []);
        _fetchRoute(from, clientPos, color: const Color(0xFF2196F3));
      }
    } else {
      _broadcastTimer?.cancel();
      await SupabaseService.updateOrderStatus(widget.orderId, 'delivered');
      SupabaseService.stopLocationBroadcast();
      NotificationService.entregaCompletada(widget.total * 0.15);
      if (!mounted) return;
      await showRatingDialog(context, orderId: widget.orderId, isDriver: true);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _confirmarCancelarEntrega() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cancelar esta entrega?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'El pedido de ${widget.restaurantName} volverá a estar disponible para otro repartidor.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('No, seguir', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              _broadcastTimer?.cancel();
              SupabaseService.stopLocationBroadcast();
              await SupabaseService.releaseOrderFromRider(widget.orderId);
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sd = _steps[_step];
    final myLatLng = _myPos != null ? LatLng(_myPos!.latitude, _myPos!.longitude) : null;
    final clientPos = _geocodedCustomerPos ?? _defaultRestaurantPos;
    final showClientPos = _step >= 2;
    final mapCenter = myLatLng ?? _defaultRestaurantPos;

    // Bloquea el gesto de deslizar/botón de regreso del sistema — con el
    // pedido ya aceptado, la única salida es cancelar la entrega.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmarCancelarEntrega();
      },
      child: Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        // ── Mapa: ahora ocupa toda la pantalla; el panel deslizable de
        // abajo decide cuánto se alcanza a ver ─────────────────────────
        Positioned.fill(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: mapCenter, initialZoom: 14.0),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fercadi.app',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: _routeColor,
                      borderColor: Colors.white.withValues(alpha: 0.6),
                      borderStrokeWidth: 2.0,
                    ),
                  ]),
                MarkerLayer(markers: [
                  Marker(
                    point: _defaultRestaurantPos,
                    width: 44, height: 44,
                    child: _Pin(icon: Icons.storefront, color: AppConstants.primaryColor),
                  ),
                  if (showClientPos)
                    Marker(
                      point: clientPos,
                      width: 44, height: 44,
                      child: _Pin(icon: Icons.home, color: const Color(0xFF2196F3)),
                    ),
                  if (myLatLng != null)
                    Marker(
                      point: myLatLng,
                      width: 44, height: 44,
                      child: _Pin(icon: Icons.delivery_dining, color: const Color(0xFFFF6D00)),
                    ),
                ]),
              ],
            ),
            // Debajo de la fila de arriba (paso + "Cómo llegar"), no encima —
            // antes las dos se dibujaban en la misma franja y se encimaban.
            if (_step == 2)
              Positioned(
                top: 56, left: 0, right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.gps_fixed, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('Transmitiendo ubicación en vivo',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ),
              ),
            // Avisos de abajo en una sola columna — antes "buscando ubicación"
            // y "dirección no encontrada" usaban la misma posición y podían
            // quedar una encima de la otra si las dos aplicaban a la vez.
            if (myLatLng == null || _geocodeFailed)
              Positioned(
                bottom: 8, left: 8, right: 8,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Mientras no llega el primer GPS real, avisa que sigue
                  // buscando en vez de dejar el mapa sin el ícono del
                  // repartidor como si algo estuviera roto — a veces tarda.
                  if (myLatLng == null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceColor.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        const Text('Buscando tu ubicación...',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        // Si tarda más de 12s, se ofrece reintentar en vez de
                        // dejarlo esperando sin salida (antes solo se
                        // arreglaba abriendo Google Maps y regresando).
                        if (_gpsSeemsStuck) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _retryGps,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Reintentar',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  if (myLatLng == null && _geocodeFailed) const SizedBox(height: 8),
                  if (_geocodeFailed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_off_outlined, color: Colors.black87, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Dirección no encontrada en el mapa. Usa el texto de la dirección.',
                            style: TextStyle(color: Colors.black87, fontSize: 11),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  // Igual que en Motos Flota: sin botón de cerrar aparte — con
                  // el pedido aceptado no se puede simplemente salir, solo con
                  // el botón "Cancelar pedido" de abajo (o el gesto de
                  // regreso, que muestra la misma confirmación).
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _card.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(sd.icon, color: sd.color, size: 18),
                        const SizedBox(width: 8),
                        Text(sd.label,
                            style: TextStyle(color: sd.color, fontWeight: FontWeight.bold, fontSize: 13)),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () {
                        final dest = _step >= 2 ? clientPos : _defaultRestaurantPos;
                        final url = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving',
                        );
                        launchUrl(url, mode: LaunchMode.externalApplication);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.navigation, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('Cómo llegar',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),

        // ── Panel deslizable: el repartidor decide cuánto mapa quiere ver ──
        // Arriba del todo → más info del pedido. Abajo → más mapa visible.
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.42,
          minChildSize: 0.16,
          maxChildSize: 0.85,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16),
              ],
            ),
            child: Column(children: [
              const SizedBox(height: 10),
              // La manija tiene su propio gesto de arrastre, en vez de
              // depender de que el drag "burbujee" desde el contenido de
              // adentro — antes, con el scroll interno ya hasta arriba,
              // arrastrar para ABRIR el panel no siempre respondía (para
              // cerrarlo sí, porque ahí el scroll interno no estorba).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final screenHeight = MediaQuery.of(context).size.height;
                  final delta = details.delta.dy / screenHeight;
                  final target = (_sheetController.size - delta).clamp(0.16, 0.85);
                  _sheetController.jumpTo(target);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.transparent,
                  child: Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildStepper(),
              const SizedBox(height: 20),
              const Text('Datos del cliente',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.15),
                      backgroundImage: (_customerAvatarUrl != null && _customerAvatarUrl!.isNotEmpty)
                          ? NetworkImage(_customerAvatarUrl!)
                          : null,
                      child: (_customerAvatarUrl == null || _customerAvatarUrl!.isEmpty)
                          ? const Icon(Icons.person, color: AppConstants.primaryColor, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _customerProfileName ?? widget.customerName,
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _InfoRow(Icons.phone_outlined, widget.customerPhone),
                  const SizedBox(height: 8),
                  _InfoRow(Icons.location_on_outlined, widget.address),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Productos (${widget.restaurantName})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: widget.items.asMap().entries.map((e) {
                    final isLast = e.key == widget.items.length - 1;
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          const Icon(Icons.fastfood, color: AppConstants.primaryColor, size: 16),
                          const SizedBox(width: 10),
                          Expanded(child: Text(e.value, style: const TextStyle(color: Colors.black87, fontSize: 14))),
                        ]),
                      ),
                      if (!isLast) Divider(height: 1, color: Colors.black12),
                    ]);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total del pedido',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                Text('\$${widget.total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 20),
                  ]),
                ),
              ),

              // ── Botón de acción — fijo, siempre visible sin importar
              // dónde quede el scroll de arriba ──────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SafeArea(
                  top: false,
                  child: Column(children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _avanzarStep,
                        icon: const Icon(Icons.check, size: 20),
                        label: Text(_stepActions[_step],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _steps[_step].color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _confirmarCancelarEntrega,
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                        label: const Text('Cancelar pedido',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
      ),
    );
  }

  Widget _buildStepper() {
    return Row(
      children: List.generate(_steps.length, (i) {
        final done = i < _step;
        final active = i == _step;
        final sd = _steps[i];
        // Mismo esquema que tracking_screen.dart (cliente): un paso ya
        // completado siempre se ve azul, sin importar su color propio —
        // solo el paso activo usa el color propio de sd.
        final color = done ? Colors.blue : active ? sd.color : Colors.white.withValues(alpha: 0.2);
        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: done || active
                        ? color.withValues(alpha: done ? 0.3 : 0.15)
                        : AppConstants.surface2Color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done || active ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    done ? Icons.check : sd.icon,
                    color: done || active ? color : Colors.white.withValues(alpha: 0.2),
                    size: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sd.label.split(' ').first,
                  style: TextStyle(
                    fontSize: 9,
                    color: done || active
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
            if (i < _steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: i < _step ? Colors.black : AppConstants.surface2Color,
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _Pin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Pin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppConstants.primaryColor, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13))),
    ]);
  }
}
