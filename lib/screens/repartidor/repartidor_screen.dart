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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../providers/theme_provider.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/gogo_rider_3d.dart';
import '../../services/auth_service.dart';
import '../chat_screen.dart';
import '../rating_dialog.dart';

const _defaultClientPos     = LatLng(19.8900, -100.4370);
const _defaultRestaurantPos = LatLng(19.8969, -100.4447); // Centro Maravatío

class _Order {
  final String id;
  final String restaurantName;
  final String restaurantIcon;
  final LatLng restaurantPos;
  final bool hasExactRestaurantCoords;
  final String customerName;
  final String? customerId;
  final String customerPhone;
  final String address;
  final LatLng customerPos;
  final bool hasExactCoords;
  final List<String> items;
  final double total;
  final double deliveryFee;
  final String? groupId;

  // Segunda pierna de un pedido de 2 restaurantes (ver
  // 20261031000000_multi_restaurant_orders.sql) — nulo para un pedido
  // normal de un solo restaurante. Cuando no es nulo, esta _Order ya
  // representa el viaje COMBINADO completo (ver mergedWith): sus propios
  // campos (restaurantName, restaurantPos, total, items...) siguen siendo
  // los del PRIMER restaurante SIN sumar (cada pierna se queda con su
  // propio valor, a propósito, para poder reconstruir cualquiera de las 2
  // por separado si una carrera de reclamo solo logra tomar una — ver
  // firstLegSolo/secondLegSolo), y secondXxx son los del segundo.
  final String? secondOrderId;
  final String? secondRestaurantName;
  final LatLng? secondRestaurantPos;
  final List<String>? secondItems;
  final double? secondTotal;
  final double? secondDeliveryFee;

  bool get isGrouped => secondOrderId != null;

  // Total combinado de las 2 piernas, solo para mostrar en la UI — cada
  // pedido en la BD se queda con su propio `total` real, esto nunca se
  // manda a ningún lado, es puramente de presentación.
  double get combinedTotal => total + (secondTotal ?? 0);

  // Reconstruye cada pierna como un pedido solo normal — usado cuando
  // claim_group_order solo logra reclamar UNA de las 2 (la otra ya se la
  // llevó otro repartidor justo antes).
  _Order get firstLegSolo => _Order(
        id: id,
        restaurantName: restaurantName,
        restaurantIcon: restaurantIcon,
        restaurantPos: restaurantPos,
        hasExactRestaurantCoords: hasExactRestaurantCoords,
        customerName: customerName,
        customerId: customerId,
        customerPhone: customerPhone,
        address: address,
        customerPos: customerPos,
        hasExactCoords: hasExactCoords,
        items: items,
        total: total,
        deliveryFee: deliveryFee,
      );

  _Order get secondLegSolo => _Order(
        id: secondOrderId!,
        restaurantName: secondRestaurantName ?? 'Restaurante',
        restaurantIcon: restaurantIcon,
        restaurantPos: secondRestaurantPos ?? restaurantPos,
        hasExactRestaurantCoords: secondRestaurantPos != null,
        customerName: customerName,
        customerId: customerId,
        customerPhone: customerPhone,
        address: address,
        customerPos: customerPos,
        hasExactCoords: hasExactCoords,
        items: secondItems ?? const [],
        total: secondTotal ?? 0,
        deliveryFee: secondDeliveryFee ?? 0,
      );

  _Order({
    required this.id,
    required this.restaurantName,
    required this.restaurantIcon,
    required this.restaurantPos,
    required this.hasExactRestaurantCoords,
    required this.customerName,
    this.customerId,
    required this.customerPhone,
    required this.address,
    required this.customerPos,
    required this.hasExactCoords,
    required this.items,
    required this.total,
    required this.deliveryFee,
    this.groupId,
    this.secondOrderId,
    this.secondRestaurantName,
    this.secondRestaurantPos,
    this.secondItems,
    this.secondTotal,
    this.secondDeliveryFee,
  });

  // Combina esta _Order (restaurante A) con la de su pareja de grupo
  // (restaurante B) en una sola _Order "de viaje combinado" — los datos del
  // cliente/dirección son los mismos para las 2 (un solo cliente, una sola
  // entrega), solo cambia qué restaurante hay que recoger primero. `total`/
  // `deliveryFee` de ESTA pierna NO se tocan (se quedan como su propio
  // valor real) — usar combinedTotal para mostrar la suma.
  _Order mergedWith(_Order other) {
    return _Order(
      id: id,
      restaurantName: restaurantName,
      restaurantIcon: restaurantIcon,
      restaurantPos: restaurantPos,
      hasExactRestaurantCoords: hasExactRestaurantCoords,
      customerName: customerName,
      customerId: customerId,
      customerPhone: customerPhone,
      address: address,
      customerPos: customerPos,
      hasExactCoords: hasExactCoords,
      items: items,
      total: total,
      deliveryFee: deliveryFee,
      groupId: groupId,
      secondOrderId: other.id,
      secondRestaurantName: other.restaurantName,
      secondRestaurantPos: other.restaurantPos,
      secondItems: other.items,
      secondTotal: other.total,
      secondDeliveryFee: other.deliveryFee,
    );
  }

  factory _Order.fromMap(Map<String, dynamic> m) {
    final restaurantData = m['restaurants'] as Map<String, dynamic>?;
    final restaurantName = restaurantData?['name'] as String? ?? 'Restaurante';

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

    final rawRLat = restaurantData?['lat'];
    final rawRLng = restaurantData?['lng'];
    final hasRestaurantCoords = rawRLat != null && rawRLng != null;
    final restaurantPos = hasRestaurantCoords
        ? LatLng((rawRLat as num).toDouble(), (rawRLng as num).toDouble())
        : _defaultRestaurantPos;

    return _Order(
      id: m['id'] as String,
      restaurantName: restaurantName,
      restaurantIcon: '🍽️',
      restaurantPos: restaurantPos,
      hasExactRestaurantCoords: hasRestaurantCoords,
      customerName: delivery['name'] as String? ?? 'Cliente',
      customerId: m['customer_id'] as String?,
      customerPhone: delivery['phone'] as String? ?? '',
      address: delivery['address'] as String? ?? 'Dirección no especificada',
      customerPos: customerPos,
      hasExactCoords: hasCoords,
      items: itemStrings.isEmpty ? ['Pedido #${m['id'].toString().substring(0, 6)}'] : itemStrings,
      total: (m['total'] as num).toDouble(),
      // rider_delivery_fee es el envío nominal, antes de descuentos de
      // promoción (ver 20261015000000_rider_delivery_fee.sql) — lo que de
      // verdad se le paga al repartidor, nunca lo que el cliente pagó con
      // descuento.
      deliveryFee: ((m['rider_delivery_fee'] ?? m['delivery_fee']) as num?)?.toDouble() ?? 0.0,
      groupId: m['group_id'] as String?,
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
  String  _displayName  = 'Repartidor';
  String? _photoPath;

  // GPS
  Position? _myPos;
  StreamSubscription<Position>? _gpsSub;
  Timer? _broadcastTimer;
  final _mapCtrl = MapController();

  final List<_Order> _pendingOrders = [];
  String? _customerProfileName;
  String? _customerAvatarUrl;
  final Set<String> _notifiedOrderIds = {};
  final Set<String> _rejectedOrderIds = {};
  bool _initialOrdersLoaded = false;
  bool _loadingOrders = true;
  RealtimeChannel? _ordersChannel;
  Timer? _pollTimer;
  LatLng? _geocodedCustomerPos;
  bool _geocodeFailed = false;

  // Llamadas de un dueño desde la app de escritorio (botón azul) — se ven
  // como una tarjeta más en la lista de pedidos (Aceptar/No puedo), no como
  // un popup aparte.
  List<Map<String, dynamic>> _pendingRiderCalls = [];
  final Set<String> _dismissedCallIds = {};
  RealtimeChannel? _callChannel;
  Timer? _callPollTimer;

  // Llamadas que este rider ya aceptó y sigue en curso — antes esta
  // pantalla (a diferencia de repartidor_plus_screen.dart) no tenía NINGÚN
  // rastro de esto: en cuanto se aceptaba, la tarjeta desaparecía y el rider
  // se quedaba sin dirección, sin botón de "Cómo llegar" y sin forma de
  // cerrar el ciclo (nunca contaba el envío a ningún lado).
  List<Map<String, dynamic>> _myAcceptedCalls = [];
  final Set<String> _marcandoEntregadoIds = {};

  // Ruta azul/amarilla en el mapa
  List<LatLng> _routePoints = [];
  Color _routeColor = const Color(0xFFFFB300);
  LatLng? _lastRouteFetchPos;

  @override
  void initState() {
    super.initState();
    _initGPS();
    _loadOrders();
    _ordersChannel = SupabaseService.subscribeToOrders(_loadOrders);
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadOrders());
    AuthService.getDisplayName().then((n) { if (mounted) setState(() => _displayName = n); });
    AuthService.getProfilePhoto().then((p) { if (mounted) setState(() => _photoPath = p); });
    _loadRiderCalls();
    _callChannel = SupabaseService.subscribeToRiderCalls(_loadRiderCalls);
    _callPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadRiderCalls());
  }

  Future<void> _loadRiderCalls() async {
    try {
      final calls = await SupabaseService.getPendingRiderCalls();
      if (mounted) {
        setState(() {
          _pendingRiderCalls = calls.where((c) => !_dismissedCallIds.contains(c['id'])).toList();
        });
      }
      final mine = await SupabaseService.getMyAcceptedRiderCalls();
      if (mounted) setState(() => _myAcceptedCalls = mine);
    } catch (_) {}
    SupabaseService.expireOldRiderCalls();
  }

  Future<void> _marcarEntregado(String callId) async {
    if (_marcandoEntregadoIds.contains(callId)) return;
    _marcandoEntregadoIds.add(callId);
    try {
      await SupabaseService.markRiderCallDelivered(callId);
      if (!mounted) return;
      setState(() => _myAcceptedCalls.removeWhere((c) => c['id'] == callId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('¡Listo! Ya se sumó a tu saldo.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo marcar como entregado. Intenta de nuevo.'),
          backgroundColor: Color(0xFFE53935),
        ));
      }
    } finally {
      _marcandoEntregadoIds.remove(callId);
    }
  }

  Future<void> _responderLlamada(String callId, bool accept) async {
    setState(() {
      _dismissedCallIds.add(callId);
      _pendingRiderCalls.removeWhere((c) => c['id'] == callId);
    });
    final ganaste = await SupabaseService.respondRiderCall(callId, accept);
    if (!accept || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ganaste ? '¡Listo! Ve por el pedido.' : 'Ya se lo llevó otro repartidor.'),
      backgroundColor: ganaste ? Colors.green : Colors.orange,
    ));
  }

  Widget _buildRiderCallCard(Map<String, dynamic> call, bool isDark) {
    final cardBg = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain = isDark ? Colors.white : Colors.black87;
    final textSub = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black54;
    final restaurantName = call['restaurant_name'] as String? ?? 'Un restaurante';
    final id = call['id'] as String;
    final restaurantAddress = (call['restaurants'] as Map<String, dynamic>?)?['address'] as String?;
    const callBlue = Color(0xFF2196F3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: callBlue.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.delivery_dining_rounded, color: callBlue, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('¡Te están llamando!',
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('$restaurantName necesita un repartidor ahora mismo',
                    style: TextStyle(color: textSub, fontSize: 12)),
                if (restaurantAddress != null && restaurantAddress.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(restaurantAddress, style: TextStyle(color: textSub, fontSize: 11)),
                  ),
              ]),
            ),
          ]),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
          child: Row(children: [
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _responderLlamada(id, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: isDark ? AppConstants.surface2Color : Colors.grey.shade200,
                  child: Center(
                    child: Text('NO PUEDO',
                        style: TextStyle(
                            color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5)),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: () => _responderLlamada(id, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: callBlue,
                  child: const Center(
                    child: Text('ACEPTAR',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildAcceptedCallCard(Map<String, dynamic> call, bool isDark) {
    final cardBg = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain = isDark ? Colors.white : Colors.black87;
    final textSub = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black54;
    final restaurantName = call['restaurant_name'] as String? ?? 'Un restaurante';
    final id = call['id'] as String;
    final envio = (call['amount_envio'] as num?)?.toDouble() ?? 35;
    final marcando = _marcandoEntregadoIds.contains(id);
    final restaurantData = call['restaurants'] as Map<String, dynamic>?;
    final restaurantAddress = restaurantData?['address'] as String?;
    final restLat = restaurantData?['lat'];
    final restLng = restaurantData?['lng'];
    final restaurantPos = (restLat != null && restLng != null)
        ? LatLng((restLat as num).toDouble(), (restLng as num).toDouble())
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.storefront_rounded, color: Colors.green, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ve por el pedido a $restaurantName',
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Cuando entregues, marca como entregado — ganas \$${envio.toStringAsFixed(0)}',
                    style: TextStyle(color: textSub, fontSize: 12)),
                if (restaurantAddress != null && restaurantAddress.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(restaurantAddress, style: TextStyle(color: textSub, fontSize: 11)),
                  ),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(children: [
            if (restaurantPos != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final url = Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=${restaurantPos.latitude},${restaurantPos.longitude}&travelmode=driving',
                    );
                    launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Cómo llegar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: restaurantPos != null ? 1 : 2,
              child: ElevatedButton.icon(
                onPressed: marcando ? null : () => _marcarEntregado(id),
                icon: marcando
                    ? const SizedBox(
                        height: 14, width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('ENTREGADO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // Combina pares de pedidos que compartan group_id (pedido de 2
  // restaurantes) en una sola _Order de "viaje combinado" — un pedido
  // huérfano (su pareja todavía no aparece aquí, p. ej. el restaurante de
  // esa pareja no ha confirmado, o ya se la llevó otro rider) se deja tal
  // cual, como un pedido normal de un solo restaurante.
  List<_Order> _mergeGrouped(List<_Order> orders) {
    final byGroup = <String, List<_Order>>{};
    final result = <_Order>[];
    for (final o in orders) {
      if (o.groupId == null) {
        result.add(o);
      } else {
        byGroup.putIfAbsent(o.groupId!, () => []).add(o);
      }
    }
    for (final pair in byGroup.values) {
      if (pair.length == 2) {
        result.add(pair[0].mergedWith(pair[1]));
      } else {
        result.addAll(pair);
      }
    }
    return result;
  }

  Future<void> _loadOrders() async {
    try {
      final data = await SupabaseService.getOrdersForRepartidor();
      if (!mounted) return;
      final rawOrders = data.map(_Order.fromMap).toList();
      final orders = _mergeGrouped(rawOrders)
          .where((o) => o.id != _activeOrder?.id &&
              !_rejectedOrderIds.contains(o.id) &&
              (o.secondOrderId == null || !_rejectedOrderIds.contains(o.secondOrderId)))
          .toList();
      if (!_initialOrdersLoaded) {
        _initialOrdersLoaded = true;
        _notifiedOrderIds.addAll(orders.map((o) => o.id));
      } else {
        for (final o in orders) {
          if (!_notifiedOrderIds.contains(o.id)) {
            _notifiedOrderIds.add(o.id);
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
        // El stream puede tardar mucho en entregar su primer punto en frío
        // (antes solo se arreglaba abriendo Google Maps y regresando, que
        // "despierta" el GPS del sistema) — pedir una posición puntual de
        // una vez tiene el mismo efecto sin salir de la app.
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).then((pos) {
          if (!mounted || _myPos != null) return;
          setState(() => _myPos = pos);
          SupabaseService.broadcastRiderPresence(pos.latitude, pos.longitude);
        }).catchError((_) {});
        _gpsSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
        ).listen((pos) {
          if (!mounted) return;
          setState(() => _myPos = pos);
          // Transmite presencia al jefe de flota siempre que el GPS esté activo
          SupabaseService.broadcastRiderPresence(pos.latitude, pos.longitude);
          if (_activeOrder != null) {
            final current = LatLng(pos.latitude, pos.longitude);
            try { _mapCtrl.move(current, 15.5); } catch (_) {}
            SupabaseService.broadcastLocation(pos.latitude, pos.longitude);
            // Re-trazar ruta cada 200 m de movimiento
            final prevPos = _lastRouteFetchPos;
            final moved = prevPos == null ||
                const Distance()(prevPos, current) > 200;
            if (moved) {
              _lastRouteFetchPos = current;
              final clientPos = _geocodedCustomerPos ?? _activeOrder!.customerPos;
              final dest = _destForStep(_activeOrder!, _step, clientPos);
              final color = _colorForStep(_activeOrder!, _step);
              _fetchRoute(current, dest, color: color);
            }
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
    _callPollTimer?.cancel();
    _callChannel?.unsubscribe();
    SupabaseService.stopLocationBroadcast();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _aceptarPedido(_Order order) async {
    setState(() {
      _activeOrder = order;
      _geocodedCustomerPos = order.hasExactCoords ? order.customerPos : null;
      _geocodeFailed = false;
      _customerProfileName = null;
      _customerAvatarUrl = null;
      _pendingOrders.removeWhere((o) => o.id == order.id);
      _step = 0;
      _routePoints = [];
      _lastRouteFetchPos = null;
    });
    if (!order.hasExactCoords) _geocodeCustomer(order.address);
    final from = _myPos != null
        ? LatLng(_myPos!.latitude, _myPos!.longitude)
        : order.restaurantPos;
    _fetchRoute(from, order.restaurantPos, color: const Color(0xFFFFB300));

    // Reclama con claim_group_order también el pedido de un solo
    // restaurante — antes ese caso hacía un update "a ciegas" sin esperar
    // respuesta: si otro repartidor lo tomó primero, la pantalla se quedaba
    // con un pedido que no era suyo y transmitía su GPS sobre él.
    // Pedido de 2 restaurantes: reclama AMBAS piernas en una sola
    // transacción — si entre que se cargó la lista y este tap otro
    // repartidor ya se adelantó con una de las 2, se sigue solo con la que
    // sí se logró reclamar (nunca es un error, mientras se haya reclamado al
    // menos una).
    try {
      final claimed = await SupabaseService.claimGroupOrder(order.id);
      if (!mounted || _activeOrder?.id != order.id) return;
      _Order effective = order;
      if (order.isGrouped && claimed.length < 2) {
        final gotFirst = claimed.contains(order.id);
        effective = gotFirst ? order.firstLegSolo : order.secondLegSolo;
        setState(() {
          _activeOrder = effective;
          _geocodedCustomerPos = effective.hasExactCoords ? effective.customerPos : null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El otro restaurante de este pedido ya se lo llevó otro repartidor — sigues solo con este.'),
          backgroundColor: Colors.orange,
        ));
        final f = _myPos != null ? LatLng(_myPos!.latitude, _myPos!.longitude) : effective.restaurantPos;
        _fetchRoute(f, effective.restaurantPos, color: const Color(0xFFFFB300));
      }
      SupabaseService.startLocationBroadcast(effective.id);
      _loadCustomerProfile(effective);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeOrder = null;
        _step = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ya se lo llevó otro repartidor.'),
        backgroundColor: Colors.orange,
      ));
      _loadOrders();
    }
  }

  // Nombre/foto reales de la cuenta del cliente (como en Uber) — solo se
  // pueden consultar una vez aceptado el pedido, cuando ya se es su
  // repartidor asignado (la Edge Function lo exige por seguridad).
  Future<void> _loadCustomerProfile(_Order order) async {
    if (order.customerId == null) return;
    final profile = await SupabaseService.getOrderCounterpartProfile(order.id, order.customerId!);
    if (!mounted || _activeOrder?.id != order.id || profile == null) return;
    setState(() {
      _customerProfileName = profile['name'] as String?;
      _customerAvatarUrl = profile['avatarUrl'] as String?;
    });
  }

  void _rechazarPedido(_Order order) {
    setState(() {
      _rejectedOrderIds.add(order.id);
      if (order.secondOrderId != null) _rejectedOrderIds.add(order.secondOrderId!);
      _pendingOrders.removeWhere((o) => o.id == order.id);
    });
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

  Future<void> _geocodeCustomer(String address) async {
    final result = await LocationService.geocodeAddress(address);
    if (!mounted) return;
    if (result == null) {
      setState(() => _geocodeFailed = true);
      return;
    }
    setState(() {
      _geocodedCustomerPos = LatLng(result.lat, result.lng);
      _geocodeFailed = false;
    });
    try { _mapCtrl.move(_geocodedCustomerPos!, 15.0); } catch (_) {}
  }

  // Evita el doble toque: un segundo toque durante el await saltaba el paso
  // "en camino" y marcaba el pedido como entregado.
  bool _avanzando = false;

  Future<void> _avanzarStep() async {
    if (_avanzando) return;
    setState(() => _avanzando = true);
    try {
      await _avanzarStepInner();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el pedido. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _avanzando = false);
    }
  }

  Future<void> _avanzarStepInner() async {
    final order = _activeOrder!;
    final finalizeIndex = _finalizeIndexFor(order);
    if (_step < finalizeIndex) {
      if (_step + 1 == finalizeIndex) {
        // Pedido de 1 o 2 restaurantes: a partir de aquí se considera
        // "delivering" para TODAS sus piernas (cada fila de "orders" avanza
        // su propio status, pero desde la perspectiva del rider es un solo
        // viaje continuo). Primero el servidor, después la UI.
        await SupabaseService.updateOrderStatus(order.id, 'delivering');
        if (order.secondOrderId != null) {
          await SupabaseService.updateOrderStatus(order.secondOrderId!, 'delivering');
        }
      }
      setState(() => _step++);
      // En un pedido de 2 restaurantes, pasar de "recoge en A" a "ve a B"
      // (step 1→2) también necesita una ruta nueva (destino cambia de
      // restaurante A a restaurante B) aunque todavía no sea el tramo
      // final — antes (pedido de un solo restaurante) esto solo pasaba en
      // la transición final, porque solo había un restaurante de por medio.
      if (_step != finalizeIndex) {
        final clientPos = _geocodedCustomerPos ?? order.customerPos;
        final dest = _destForStep(order, _step, clientPos);
        final color = _colorForStep(order, _step);
        final from = _myPos != null ? LatLng(_myPos!.latitude, _myPos!.longitude) : dest;
        setState(() { _routePoints = []; _lastRouteFetchPos = null; });
        _fetchRoute(from, dest, color: color);
      }
      if (_step == finalizeIndex) {
        _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_myPos != null) {
            SupabaseService.broadcastLocation(_myPos!.latitude, _myPos!.longitude);
          }
        });
        final clientPos = _geocodedCustomerPos ?? order.customerPos;
        final from = _myPos != null
            ? LatLng(_myPos!.latitude, _myPos!.longitude)
            : _destForStep(order, _step - 1, clientPos);
        setState(() { _routePoints = []; _lastRouteFetchPos = null; });
        _fetchRoute(from, clientPos, color: const Color(0xFF2196F3));
      }
    } else {
      final orderId = order.id;
      // Antes usaba combinedTotal*0.15 (15% del total del pedido, sin
      // relación con lo que de verdad cobra un repartidor) — ahora el mismo
      // cálculo que ya se usa para la estimación en la lista (línea ~1087):
      // el envío real menos la comisión de la plataforma.
      final ganancia = (order.deliveryFee + (order.secondDeliveryFee ?? 0)) *
          (1 - LocationService.comisionRepartidorPct / 100);
      await SupabaseService.updateOrderStatus(orderId, 'delivered');
      if (order.secondOrderId != null) {
        await SupabaseService.updateOrderStatus(order.secondOrderId!, 'delivered');
      }
      _broadcastTimer?.cancel();
      _broadcastTimer = null;
      SupabaseService.stopLocationBroadcast();
      NotificationService.entregaCompletada(ganancia);
      setState(() {
        _activeOrder = null;
        _step = 0;
        _routePoints = [];
        _lastRouteFetchPos = null;
      });
      _loadOrders();
      if (mounted) {
        await showRatingDialog(context, orderId: orderId, isDriver: true);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Con un pedido ya aceptado, solo se puede salir cancelando la entrega.
    return PopScope(
      canPop: _activeOrder == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmarCancelarEntrega();
      },
      child: Scaffold(
        backgroundColor: isDark ? AppConstants.bgColor : AppConstants.primaryColor,
        body: _activeOrder == null ? _buildOrderList(isDark) : _buildActiveOrder(isDark),
      ),
    );
  }

  // ── Lista de pedidos ──────────────────────────────────────────────────────────

  Widget _buildOrderList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: AppConstants.primaryColor,
      child: CustomScrollView(
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

        // Nota: esta pantalla es siempre para repartidores de flota — sus
        // ganancias/entregas las administra su jefe de flota desde su
        // propio panel, por eso aquí nunca se muestra esa tarjeta.

        // Llamadas de un dueño desde la app de escritorio — se ven como
        // una tarjeta de pedido más (Aceptar/No puedo), no como un popup
        // aparte, para que se sienta igual que aceptar cualquier pedido.
        if (_pendingRiderCalls.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildRiderCallCard(_pendingRiderCalls[i], isDark),
                childCount: _pendingRiderCalls.length,
              ),
            ),
          ),

        // Llamadas ya aceptadas por este rider — antes desaparecían sin
        // dejar rastro al aceptarlas (ver nota en _myAcceptedCalls arriba).
        if (_myAcceptedCalls.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildAcceptedCallCard(_myAcceptedCalls[i], isDark),
                childCount: _myAcceptedCalls.length,
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
                // Moto GOGO en 3D (antes un ícono plano de Material).
                const GogoRider3D(height: 220),
                const SizedBox(height: 8),
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
      ),
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
                          : kIsWeb ? const Icon(Icons.delivery_dining, color: AppConstants.primaryColor, size: 26)
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
            IconButton(
              icon: Icon(Icons.headset_mic_outlined, color: iconColor, size: 20),
              tooltip: 'Soporte',
              onPressed: () => context.push('/soporte'),
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

    // Lo que va a ganar el repartidor por ENTREGAR este pedido (no el total
    // del pedido, que incluye la comida) — cuenta la distancia desde donde
    // está parado ahorita hasta el restaurante y de ahí a la casa del
    // cliente, ya con la comisión de la plataforma descontada. Para un
    // pedido de 2 restaurantes se usa la estimación "en vivo" GPS solo si
    // hay una, y si no, la suma de las 2 tarifas nominales ya con comisión
    // — estimar la ruta en vivo rider→A→B→cliente es un cálculo mucho más
    // grande que no se justifica solo para un número aproximado en la
    // lista (alcance reducido a propósito, ver CLAUDE.md).
    double montoAMostrar = (order.deliveryFee + (order.secondDeliveryFee ?? 0)) *
        (1 - LocationService.comisionRepartidorPct / 100);
    if (!order.isGrouped && _myPos != null && order.hasExactRestaurantCoords && order.hasExactCoords) {
      montoAMostrar = LocationService.estimarGananciaRepartidor(
        riderLat: _myPos!.latitude,
        riderLng: _myPos!.longitude,
        restaurantLat: order.restaurantPos.latitude,
        restaurantLng: order.restaurantPos.longitude,
        customerLat: order.customerPos.latitude,
        customerLng: order.customerPos.longitude,
      );
    }
    final cardRestaurantName =
        order.isGrouped ? '${order.restaurantName} + ${order.secondRestaurantName}' : order.restaurantName;
    final cardItemCount = order.items.length + (order.secondItems?.length ?? 0);

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
                  Text(cardRestaurantName,
                      style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('$cardItemCount producto${cardItemCount != 1 ? 's' : ''}'
                      '${order.isGrouped ? ' — 2 restaurantes' : ''}',
                      style: TextStyle(color: textSub, fontSize: 12)),
                ]),
              ),
              Text('\$${montoAMostrar.toStringAsFixed(0)} MXN',
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

  // Secuencia de colores pedida: amarillo → naranja → azul → verde
  // (verde queda reservado para "completado", ver _buildStepper).
  static const _steps = [
    (icon: Icons.store,          label: 'Ve al restaurante',       color: Color(0xFFFFD600)),
    (icon: Icons.shopping_bag,   label: 'Recoge el pedido',        color: AppConstants.primaryColor),
    (icon: Icons.delivery_dining,label: 'En camino al cliente',    color: Color(0xFF2196F3)),
    (icon: Icons.check_circle,   label: '¡Pedido entregado!',      color: Colors.green),
  ];

  static const _stepActions = [
    'Ya estoy en el restaurante',
    'Pedido recogido — ¡En camino!',
    'Marcar como entregado',
    'Ver más pedidos',
  ];

  // Pedido de 2 restaurantes: 2 paradas de recogida en vez de 1 — 6 "pasos"
  // en vez de 4 (ve a A, recoge en A, ve a B, recoge en B, en camino al
  // cliente, entregado). El patrón de siempre (finalizar = steps.length-2)
  // se mantiene igual para los 2 casos.
  List<({IconData icon, String label, Color color})> _stepsFor(_Order order) {
    if (!order.isGrouped) return _steps;
    return [
      (icon: Icons.store, label: 'Ve a ${order.restaurantName}', color: const Color(0xFFFFD600)),
      (icon: Icons.shopping_bag, label: 'Recoge en ${order.restaurantName}', color: AppConstants.primaryColor),
      (icon: Icons.store, label: 'Ve a ${order.secondRestaurantName}', color: Colors.deepOrange),
      (icon: Icons.shopping_bag, label: 'Recoge en ${order.secondRestaurantName}', color: Colors.deepOrangeAccent),
      (icon: Icons.delivery_dining, label: 'En camino al cliente', color: const Color(0xFF2196F3)),
      (icon: Icons.check_circle, label: '¡Pedido entregado!', color: Colors.green),
    ];
  }

  List<String> _stepActionsFor(_Order order) {
    if (!order.isGrouped) return _stepActions;
    return [
      'Ya estoy en ${order.restaurantName}',
      'Pedido recogido — ir al 2º restaurante',
      'Ya estoy en ${order.secondRestaurantName}',
      'Pedido recogido — ¡en camino al cliente!',
      'Marcar como entregado',
      'Ver más pedidos',
    ];
  }

  // Destino de navegación/ruta para el "step" actual — centraliza lo que
  // antes era un ternario repetido en varios lados (GPS en vivo, "Cómo
  // llegar", mapa) y que ahora tiene 3 posibles destinos (restaurante A,
  // restaurante B, cliente) en vez de solo 2.
  LatLng _destForStep(_Order order, int step, LatLng clientPos) {
    if (!order.isGrouped) return step >= 2 ? clientPos : order.restaurantPos;
    if (step < 2) return order.restaurantPos;
    if (step < 4) return order.secondRestaurantPos ?? order.restaurantPos;
    return clientPos;
  }

  Color _colorForStep(_Order order, int step) {
    if (!order.isGrouped) return step >= 2 ? const Color(0xFF2196F3) : const Color(0xFFFFB300);
    if (step < 2) return const Color(0xFFFFD600);
    if (step < 4) return Colors.deepOrange;
    return const Color(0xFF2196F3);
  }

  // El último paso antes de "entregado" — donde se dispara 'delivering' y
  // se empieza a transmitir ubicación al cliente. Para un pedido solo es el
  // índice 2 (como siempre); para uno de 2 restaurantes, el 4.
  int _finalizeIndexFor(_Order order) => _stepsFor(order).length - 2;

  Widget _buildActiveOrder(bool isDark) {
    final order = _activeOrder!;
    final steps = _stepsFor(order);
    final stepActions = _stepActionsFor(order);
    final finalizeIndex = _finalizeIndexFor(order);
    final sd = steps[_step];
    final myLatLng = _myPos != null
        ? LatLng(_myPos!.latitude, _myPos!.longitude)
        : null;

    final clientPos = _geocodedCustomerPos ?? order.customerPos;
    final showClientPos = _step >= finalizeIndex;
    final currentDest = _destForStep(order, _step, clientPos);
    final mapCenter = myLatLng ?? currentDest;

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
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Resplandor: varias líneas iguales, cada vez más anchas
                    // y transparentes, apiladas detrás de la línea nítida.
                    Polyline(points: _routePoints, strokeWidth: 22.0, color: _routeColor.withValues(alpha: 0.08)),
                    Polyline(points: _routePoints, strokeWidth: 14.0, color: _routeColor.withValues(alpha: 0.18)),
                    Polyline(points: _routePoints, strokeWidth: 9.0, color: _routeColor.withValues(alpha: 0.35)),
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: _routeColor,
                      borderColor: Colors.white.withValues(alpha: 0.6),
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: [
                Marker(
                  point: order.restaurantPos,
                  width: 44, height: 44,
                  child: _Pin(icon: Icons.storefront, color: AppConstants.primaryColor),
                ),
                if (order.isGrouped && order.secondRestaurantPos != null)
                  Marker(
                    point: order.secondRestaurantPos!,
                    width: 44, height: 44,
                    child: _Pin(icon: Icons.storefront, color: Colors.deepOrange),
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
                    width: 72, height: 72,
                    child: Image.asset('assets/images/moto_repartidor.png', width: 72, height: 72),
                  ),
              ]),
            ],
          ),
          // Debajo de la fila de arriba (paso + "Cómo llegar"), no encima —
          // antes las dos se dibujaban en la misma franja y se encimaban.
          if (_step == finalizeIndex)
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
          if (_geocodeFailed)
            Positioned(
              bottom: 8, left: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.location_off_outlined, color: Colors.black87, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dirección no encontrada en el mapa. Usa el texto de la dirección.',
                      style: const TextStyle(color: Colors.black87, fontSize: 11),
                    ),
                  ),
                ]),
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
                      final dest = _destForStep(order, _step, clientPos);
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
              _buildStepper(steps),
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
                  Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.15),
                      backgroundImage: (_customerAvatarUrl != null && _customerAvatarUrl!.isNotEmpty)
                          ? NetworkImage(_customerAvatarUrl!)
                          : null,
                      child: (_customerAvatarUrl == null || _customerAvatarUrl!.isEmpty)
                          ? Icon(Icons.person, color: AppConstants.primaryColor, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _customerProfileName ?? order.customerName,
                        style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppConstants.primaryColor, size: 20),
                      tooltip: 'Mensajes',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          orderId: order.id,
                          counterpartName: _customerProfileName ?? order.customerName,
                          counterpartPhoto: _customerAvatarUrl,
                        ),
                      )),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // El cliente ya no captura teléfono en el checkout — solo
                  // se muestra si su cuenta ya tiene uno asociado. Para
                  // contactarlo siempre está el botón de mensajes de arriba.
                  if (order.customerPhone.isNotEmpty) ...[
                    _InfoRow(Icons.phone_outlined, order.customerPhone, textColor: textMain),
                    const SizedBox(height: 8),
                  ],
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
              if (order.isGrouped) ...[
                const SizedBox(height: 16),
                _SectionLabel('Productos (${order.secondRestaurantName})', textColor: Colors.white),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: (order.secondItems ?? const []).asMap().entries.map((e) {
                      final isLast = e.key == (order.secondItems?.length ?? 1) - 1;
                      return Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            const Icon(Icons.fastfood, color: Colors.deepOrange, size: 16),
                            const SizedBox(width: 10),
                            Text(e.value, style: TextStyle(color: textMain, fontSize: 14)),
                          ]),
                        ),
                        if (!isLast) Divider(height: 1, color: divider),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total del pedido', style: TextStyle(color: textSub, fontSize: 13)),
                Text('\$${order.combinedTotal.toStringAsFixed(0)} MXN',
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),

      // ── Botón de acción flotante ───────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        color: Colors.transparent,
        child: SafeArea(
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _avanzando ? null : _avanzarStep,
                icon: Icon(_step == steps.length - 1 ? Icons.arrow_forward : Icons.check, size: 20),
                label: Text(stepActions[_step],
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: steps[_step].color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            if (_step < steps.length - 1) ...[
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
            ],
          ]),
        ),
      ),
    ]);
  }

  void _confirmarCancelarEntrega() {
    final order = _activeOrder;
    if (order == null) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cancelar esta entrega?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          order.isGrouped
              ? 'El pedido de ${order.restaurantName} y ${order.secondRestaurantName} volverá a estar disponible para otro repartidor.'
              : 'El pedido de ${order.restaurantName} volverá a estar disponible para otro repartidor.',
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
              _broadcastTimer = null;
              SupabaseService.stopLocationBroadcast();
              await SupabaseService.releaseOrderFromRider(order.id);
              if (order.secondOrderId != null) {
                await SupabaseService.releaseOrderFromRider(order.secondOrderId!);
              }
              if (!mounted) return;
              setState(() {
                _activeOrder = null;
                _step = 0;
                _routePoints = [];
                _lastRouteFetchPos = null;
              });
              _loadOrders();
            },
            child: const Text('Sí, cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(List<({IconData icon, String label, Color color})> steps) {
    return Row(
      children: List.generate(steps.length, (i) {
        final done = i < _step;
        final active = i == _step;
        final sd = steps[i];
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
            if (i < steps.length - 1)
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
