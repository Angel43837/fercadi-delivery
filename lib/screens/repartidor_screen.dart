// repartidor_screen.dart
// Panel del repartidor.
// Muestra los pedidos pendientes de entregar y el mapa con su posición GPS en tiempo real.
// El repartidor puede:
//   - Ver pedidos disponibles (status: pending, accepted)
//   - Aceptar un pedido para entregarlo
//   - Rechazar un pedido (lo oculta localmente)
//   - Marcar el pedido como "entregado"
//   - Ver la dirección del cliente en Google Maps
//   - Alternar modo claro/oscuro desde el header
// El GPS del repartidor se transmite a Supabase cada vez que se mueve
// para que el cliente pueda seguirlo en la pantalla de tracking.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../providers/theme_provider.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';

// Posiciones fijas por restaurante
const _restaurantInfo = {
  '1': (name: 'McDonalds',  icon: '🍔', pos: LatLng(19.9020, -100.4510)),
  '2': (name: 'Starbucks',  icon: '☕', pos: LatLng(19.8980, -100.4460)),
  '3': (name: 'Sushi Roll', icon: '🍣', pos: LatLng(19.8950, -100.4500)),
};
const _defaultClientPos = LatLng(19.8900, -100.4370);

class _Order {
  final String id;
  final String restaurantName;
  final String restaurantIcon;
  final LatLng restaurantPos;
  final String customerName;
  final String customerPhone;
  final String address;
  final LatLng customerPos;
  final bool hasExactCoords;
  final List<String> items;
  final double total;

  _Order({
    required this.id,
    required this.restaurantName,
    required this.restaurantIcon,
    required this.restaurantPos,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.customerPos,
    required this.hasExactCoords,
    required this.items,
    required this.total,
  });

  factory _Order.fromMap(Map<String, dynamic> m) {
    final rid = m['restaurant_id'] as String? ?? '1';
    final info = _restaurantInfo[rid] ?? _restaurantInfo['1']!;

    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(m['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}

    final orderItems = (m['order_items'] as List<dynamic>? ?? []);
    final itemStrings = orderItems.map((i) {
      final qty = i['quantity'] as int? ?? 1;
      final product = i['products'] as Map<String, dynamic>?;
      final name = product?['name'] as String? ?? 'Producto';
      return '$qty× $name';
    }).toList();

    final rawLat = delivery['lat'];
    final rawLng = delivery['lng'];
    final hasCoords = rawLat != null && rawLng != null;
    final customerPos = hasCoords
        ? LatLng((rawLat as num).toDouble(), (rawLng as num).toDouble())
        : _defaultClientPos;

    return _Order(
      id: m['id'] as String,
      restaurantName: info.name,
      restaurantIcon: info.icon,
      restaurantPos: info.pos,
      customerName: delivery['name'] as String? ?? 'Cliente',
      customerPhone: delivery['phone'] as String? ?? '—',
      address: delivery['address'] as String? ?? 'Dirección no especificada',
      customerPos: customerPos,
      hasExactCoords: hasCoords,
      items: itemStrings.isEmpty ? ['Pedido #${m['id'].toString().substring(0, 6)}'] : itemStrings,
      total: (m['total'] as num).toDouble(),
    );
  }
}

class RepartidorScreen extends StatefulWidget {
  const RepartidorScreen({super.key});

  @override
  State<RepartidorScreen> createState() => _RepartidorScreenState();
}

class _RepartidorScreenState extends State<RepartidorScreen> {
  bool    _disponible   = true;
  _Order? _activeOrder;
  int     _step         = 0;
  int     _entregasHoy  = 0;
  double  _gananciaHoy  = 0;
  String  _displayName  = 'Repartidor';
  String? _photoPath;

  // GPS
  Position? _myPos;
  StreamSubscription<Position>? _gpsSub;
  Timer? _broadcastTimer;
  final _mapCtrl = MapController();

  final List<_Order> _pendingOrders = [];
  final Set<String> _notifiedOrderIds = {};
  final Set<String> _rejectedOrderIds = {};
  bool _loadingOrders = true;
  RealtimeChannel? _ordersChannel;
  Timer? _pollTimer;
  LatLng? _geocodedCustomerPos;

  @override
  void initState() {
    super.initState();
    _initGPS();
    _loadOrders();
    _ordersChannel = SupabaseService.subscribeToOrders(_loadOrders);
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadOrders());
    AuthService.getDisplayName().then((n) { if (mounted) setState(() => _displayName = n); });
    AuthService.getProfilePhoto().then((p) { if (mounted) setState(() => _photoPath = p); });
  }

  Future<void> _loadOrders() async {
    try {
      final data = await SupabaseService.getOrdersForRepartidor();
      if (!mounted) return;
      final orders = data
          .map(_Order.fromMap)
          .where((o) => o.id != _activeOrder?.id && !_rejectedOrderIds.contains(o.id))
          .toList();
      for (final o in orders) {
        if (!_notifiedOrderIds.contains(o.id)) {
          _notifiedOrderIds.add(o.id);
          if (_notifiedOrderIds.length > 1) {
            NotificationService.pedidoDisponible(o.restaurantName, o.total);
          }
        }
      }
      setState(() {
        _pendingOrders..clear()..addAll(orders);
        _loadingOrders = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _initGPS() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        _gpsSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _myPos = pos);
          if (_activeOrder != null) {
            try { _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.5); } catch (_) {}
            SupabaseService.broadcastLocation(pos.latitude, pos.longitude);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _broadcastTimer?.cancel();
    _pollTimer?.cancel();
    _ordersChannel?.unsubscribe();
    SupabaseService.stopLocationBroadcast();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _aceptarPedido(_Order order) {
    setState(() {
      _activeOrder = order;
      _geocodedCustomerPos = order.hasExactCoords ? order.customerPos : null;
      _pendingOrders.removeWhere((o) => o.id == order.id);
      _step = 0;
    });
    SupabaseService.updateOrderStatus(order.id, 'accepted');
    SupabaseService.startLocationBroadcast(order.id);
    if (!order.hasExactCoords) _geocodeCustomer(order.address);
  }

  void _rechazarPedido(_Order order) {
    setState(() {
      _rejectedOrderIds.add(order.id);
      _pendingOrders.removeWhere((o) => o.id == order.id);
    });
  }

  Future<void> _geocodeCustomer(String address) async {
    final result = await LocationService.geocodeAddress(address);
    if (!mounted || result == null) return;
    setState(() => _geocodedCustomerPos = LatLng(result.lat, result.lng));
    try { _mapCtrl.move(_geocodedCustomerPos!, 15.0); } catch (_) {}
  }

  void _avanzarStep() {
    if (_step < 2) {
      setState(() => _step++);
      if (_step == 2) {
        SupabaseService.updateOrderStatus(_activeOrder!.id, 'delivering');
        _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_myPos != null) {
            SupabaseService.broadcastLocation(_myPos!.latitude, _myPos!.longitude);
          }
        });
      }
    } else {
      _broadcastTimer?.cancel();
      _broadcastTimer = null;
      SupabaseService.updateOrderStatus(_activeOrder!.id, 'delivered');
      SupabaseService.stopLocationBroadcast();
      setState(() {
        _entregasHoy++;
        _gananciaHoy += _activeOrder!.total * 0.15;
        _activeOrder = null;
        _step = 0;
      });
      _loadOrders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('¡Pedido entregado! Excelente trabajo 🎉'),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppConstants.bgColor : AppConstants.primaryColor,
      body: _activeOrder == null ? _buildOrderList(isDark) : _buildActiveOrder(isDark),
    );
  }

  // ── Lista de pedidos ──────────────────────────────────────────────────────────

  Widget _buildOrderList(bool isDark) {
    final cardBg = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain = isDark ? Colors.white : Colors.black87;
    final textSub  = isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black54;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(isDark)),

        SliverToBoxAdapter(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppConstants.bgColor : AppConstants.primaryColor,
              border: Border(
                bottom: BorderSide(color: AppConstants.primaryColor.withValues(alpha: 0.25), width: 1),
              ),
            ),
          ),
        ),

        // Ganancias del día
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Expanded(
                  child: _StatBox(
                    label: 'Ganancias hoy',
                    value: '\$${_gananciaHoy.toStringAsFixed(0)} MXN',
                    icon: Icons.attach_money,
                    color: Colors.green,
                    textColor: textMain,
                    subColor: textSub,
                  ),
                ),
                Container(width: 1, height: 40, color: isDark ? AppConstants.surface2Color : Colors.black12),
                Expanded(
                  child: _StatBox(
                    label: 'Entregas',
                    value: '$_entregasHoy',
                    icon: Icons.check_circle_outline,
                    color: AppConstants.primaryColor,
                    textColor: textMain,
                    subColor: textSub,
                  ),
                ),
              ]),
            ),
          ),
        ),

        // Título lista
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _loadingOrders
                ? const LinearProgressIndicator()
                : Text(
                    _pendingOrders.isEmpty
                        ? 'Sin pedidos pendientes'
                        : 'Pedidos disponibles (${_pendingOrders.length})',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ),

        // Lista de pedidos
        if (_pendingOrders.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.delivery_dining,
                    size: 80, color: Colors.white.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                Text('No hay pedidos por ahora',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5), fontSize: 15)),
                const SizedBox(height: 8),
                Text('Cuando llegue un pedido aparecerá aquí',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildOrderCard(_pendingOrders[i], isDark),
                childCount: _pendingOrders.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(bool isDark) {
    final headerBg   = isDark ? AppConstants.surfaceColor : Colors.white.withValues(alpha: 0.15);
    final textMain   = Colors.white;
    final textSub    = Colors.white.withValues(alpha: 0.55);
    final iconColor  = Colors.white.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(color: headerBg),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          const SizedBox(height: 8),
          Row(children: [
            // Avatar
            GestureDetector(
              onTap: () async {
                await context.push('/profile');
                final n = await AuthService.getDisplayName();
                final p = await AuthService.getProfilePhoto();
                if (mounted) setState(() { _displayName = n; _photoPath = p; });
              },
              child: Stack(alignment: Alignment.bottomRight, children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppConstants.primaryColor.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: _photoPath != null
                      ? ClipOval(child: _photoPath!.startsWith('http')
                          ? Image.network(_photoPath!, fit: BoxFit.cover, width: 48, height: 48,
                              errorBuilder: (_, e, s) => const Icon(Icons.delivery_dining, color: AppConstants.primaryColor, size: 26))
                          : Image.file(File(_photoPath!), fit: BoxFit.cover, width: 48, height: 48,
                              errorBuilder: (_, e, s) => const Icon(Icons.delivery_dining, color: AppConstants.primaryColor, size: 26)))
                      : const Icon(Icons.delivery_dining, color: AppConstants.primaryColor, size: 26),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 10),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            // Nombre
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hola, $_displayName',
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 17)),
                Text('Maravatío, Mich.',
                    style: TextStyle(color: textSub, fontSize: 13)),
              ]),
            ),
            // Toggle modo oscuro/claro
            Consumer<ThemeProvider>(
              builder: (_, tp, _) => IconButton(
                icon: Icon(
                  tp.isDark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: iconColor,
                  size: 20,
                ),
                tooltip: tp.isDark ? 'Modo claro' : 'Modo oscuro',
                onPressed: tp.toggle,
              ),
            ),
            // Toggle disponible
            GestureDetector(
              onTap: () => setState(() => _disponible = !_disponible),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _disponible
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _disponible ? 'Disponible' : 'No disponible',
                    style: TextStyle(
                      color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildOrderCard(_Order order, bool isDark) {
    final cardBg  = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain = isDark ? Colors.white : Colors.black87;
    final textSub  = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black54;
    final divider  = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(order.restaurantIcon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(order.restaurantName,
                      style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${order.items.length} producto${order.items.length != 1 ? 's' : ''}',
                      style: TextStyle(color: textSub, fontSize: 12)),
                ]),
              ),
              Text('\$${order.total.toStringAsFixed(0)} MXN',
                  style: const TextStyle(
                      color: AppConstants.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            Divider(height: 1, color: divider),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.location_on_outlined, color: textSub, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(order.address,
                    style: TextStyle(color: textSub, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.person_outline, color: textSub, size: 16),
              const SizedBox(width: 6),
              Text(order.customerName,
                  style: TextStyle(color: textSub, fontSize: 12)),
            ]),
          ]),
        ),
        // Botones: RECHAZAR + ACEPTAR
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
          child: Row(children: [
            // Rechazar
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _rechazarPedido(order),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: isDark ? AppConstants.surface2Color : Colors.grey.shade200,
                  child: Center(
                    child: Text(
                      'RECHAZAR',
                      style: TextStyle(
                        color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Aceptar
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: _disponible ? () => _aceptarPedido(order) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: _disponible ? AppConstants.primaryColor : Colors.grey.shade400,
                  child: Center(
                    child: Text(
                      _disponible ? 'ACEPTAR PEDIDO' : 'NO DISPONIBLE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Pedido activo ─────────────────────────────────────────────────────────────

  static const _steps = [
    (icon: Icons.store,          label: 'Ve al restaurante',       color: Color(0xFFFFB300)),
    (icon: Icons.shopping_bag,   label: 'Recoge el pedido',        color: Color(0xFF7C4DFF)),
    (icon: Icons.delivery_dining,label: 'En camino al cliente',    color: AppConstants.primaryColor),
    (icon: Icons.check_circle,   label: '¡Pedido entregado!',      color: Colors.green),
  ];

  static const _stepActions = [
    'Ya estoy en el restaurante',
    'Pedido recogido — ¡En camino!',
    'Marcar como entregado',
    'Ver más pedidos',
  ];

  Widget _buildActiveOrder(bool isDark) {
    final order = _activeOrder!;
    final sd = _steps[_step];
    final myLatLng = _myPos != null
        ? LatLng(_myPos!.latitude, _myPos!.longitude)
        : null;

    final clientPos = _geocodedCustomerPos ?? order.customerPos;
    final showClientPos = _step >= 2;
    final mapCenter = myLatLng ?? (showClientPos
        ? LatLng(
            (order.restaurantPos.latitude + clientPos.latitude) / 2,
            (order.restaurantPos.longitude + clientPos.longitude) / 2,
          )
        : order.restaurantPos);

    final bgColor      = isDark ? AppConstants.bgColor : AppConstants.primaryColor;
    final cardBg       = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain     = isDark ? Colors.white : Colors.black87;
    final textSub      = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54;
    final divider      = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black12;

    return Column(children: [
      // ── Mapa ──────────────────────────────────────────────────────────────
      SizedBox(
        height: 260,
        child: Stack(children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(initialCenter: mapCenter, initialZoom: 14.0),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.landing_test',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: order.restaurantPos,
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
          if (_step == 2)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.surfaceColor.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(sd.icon, color: sd.color, size: 18),
                      const SizedBox(width: 8),
                      Text(sd.label,
                          style: TextStyle(
                              color: sd.color, fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                  ),
                  GestureDetector(
                    onTap: () {
                      final dest = _step >= 2 ? clientPos : order.restaurantPos;
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

      // ── Detalle del pedido ─────────────────────────────────────────────────
      Expanded(
        child: Container(
          color: bgColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildStepper(),
              const SizedBox(height: 20),

              _SectionLabel('Datos del cliente', textColor: Colors.white),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  _InfoRow(Icons.person_outline,    order.customerName,  textColor: textMain),
                  const SizedBox(height: 8),
                  _InfoRow(Icons.phone_outlined,    order.customerPhone, textColor: textMain),
                  const SizedBox(height: 8),
                  _InfoRow(Icons.location_on_outlined, order.address,   textColor: textMain),
                ]),
              ),
              const SizedBox(height: 16),

              _SectionLabel('Productos (${order.restaurantName})', textColor: Colors.white),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: order.items.asMap().entries.map((e) {
                    final isLast = e.key == order.items.length - 1;
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          const Icon(Icons.fastfood, color: AppConstants.primaryColor, size: 16),
                          const SizedBox(width: 10),
                          Text(e.value, style: TextStyle(color: textMain, fontSize: 14)),
                        ]),
                      ),
                      if (!isLast) Divider(height: 1, color: divider),
                    ]);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total del pedido', style: TextStyle(color: textSub, fontSize: 13)),
                Text('\$${order.total.toStringAsFixed(0)} MXN',
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),

      // ── Botón de acción ────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
          color: isDark ? AppConstants.surfaceColor : Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, -3))
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _avanzarStep,
              icon: Icon(_step == 3 ? Icons.arrow_forward : Icons.check, size: 20),
              label: Text(_stepActions[_step],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _steps[_step].color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildStepper() {
    return Row(
      children: List.generate(_steps.length, (i) {
        final done = i < _step;
        final active = i == _step;
        final sd = _steps[i];
        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: done || active
                        ? sd.color.withValues(alpha: done ? 0.3 : 0.15)
                        : AppConstants.surface2Color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done || active ? sd.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    done ? Icons.check : sd.icon,
                    color: done || active ? sd.color : Colors.white.withValues(alpha: 0.2),
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
                  color: i < _step ? AppConstants.primaryColor : AppConstants.surface2Color,
                ),
              ),
          ]),
        );
      }),
    );
  }
}

// ── Widgets de apoyo ─────────────────────────────────────────────────────────

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

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color textColor;
  final Color subColor;
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: TextStyle(color: subColor, fontSize: 11)),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color textColor;
  const _SectionLabel(this.text, {required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color textColor;
  const _InfoRow(this.icon, this.text, {required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppConstants.primaryColor, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 13))),
    ]);
  }
}
