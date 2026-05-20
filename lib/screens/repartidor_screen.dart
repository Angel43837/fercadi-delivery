import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../services/supabase_service.dart';

// Posiciones mock de restaurantes en Maravatío
const _posRestaurant1 = LatLng(19.9020, -100.4510); // McDonalds
const _posRestaurant2 = LatLng(19.8980, -100.4460); // Starbucks
// Posiciones mock de clientes
const _posCliente1 = LatLng(19.8900, -100.4370);
const _posCliente2 = LatLng(19.8860, -100.4420);

// Datos mock de pedidos pendientes
final _mockOrders = [
  _Order(
    id: 'o1',
    restaurantName: 'McDonalds',
    restaurantIcon: '🍔',
    restaurantPos: _posRestaurant1,
    customerName: 'Carlos Pérez',
    customerPhone: '4431234567',
    address: 'Calle Hidalgo #45, Col. Centro',
    customerPos: _posCliente1,
    items: const ['2× Big Mac', '1× Papas Grandes', '1× Coca-Cola'],
    total: 258.0,
    distanceKm: 1.4,
  ),
  _Order(
    id: 'o2',
    restaurantName: 'Starbucks',
    restaurantIcon: '☕',
    restaurantPos: _posRestaurant2,
    customerName: 'María López',
    customerPhone: '4439876543',
    address: 'Av. Morelos #88, Col. San Miguel',
    customerPos: _posCliente2,
    items: const ['1× Frappé Oreo', '1× Café Latte'],
    total: 170.0,
    distanceKm: 2.1,
  ),
];

class _Order {
  final String id;
  final String restaurantName;
  final String restaurantIcon;
  final LatLng restaurantPos;
  final String customerName;
  final String customerPhone;
  final String address;
  final LatLng customerPos;
  final List<String> items;
  final double total;
  final double distanceKm;

  const _Order({
    required this.id,
    required this.restaurantName,
    required this.restaurantIcon,
    required this.restaurantPos,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.customerPos,
    required this.items,
    required this.total,
    required this.distanceKm,
  });
}

class RepartidorScreen extends StatefulWidget {
  const RepartidorScreen({super.key});

  @override
  State<RepartidorScreen> createState() => _RepartidorScreenState();
}

class _RepartidorScreenState extends State<RepartidorScreen> {
  bool _disponible = true;
  _Order? _activeOrder;
  int _step = 0; // 0=ir al restaurante, 1=en restaurante, 2=en camino, 3=entregado
  int _entregasHoy = 0;
  double _gananciaHoy = 0;

  // GPS
  Position? _myPos;
  StreamSubscription<Position>? _gpsSub;
  Timer? _broadcastTimer;
  final _mapCtrl = MapController();

  final _pendingOrders = List<_Order>.from(_mockOrders);

  @override
  void initState() {
    super.initState();
    _initGPS();
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
          // Mover cámara cuando está en camino (step 2)
          if (_step == 2) {
            try {
              _mapCtrl.move(LatLng(pos.latitude, pos.longitude), 15.5);
            } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _broadcastTimer?.cancel();
    SupabaseService.stopLocationBroadcast();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _aceptarPedido(_Order order) {
    setState(() {
      _activeOrder = order;
      _pendingOrders.remove(order);
      _step = 0;
    });
    SupabaseService.startLocationBroadcast(order.id);
  }

  void _avanzarStep() {
    if (_step < 3) {
      setState(() => _step++);
      // Step 2 = En camino: empezar a transmitir GPS cada 5 segundos
      if (_step == 2) {
        _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_myPos != null) {
            SupabaseService.broadcastLocation(_myPos!.latitude, _myPos!.longitude);
          }
        });
      }
    } else {
      // Pedido entregado: detener transmisión
      _broadcastTimer?.cancel();
      _broadcastTimer = null;
      SupabaseService.stopLocationBroadcast();
      setState(() {
        _entregasHoy++;
        _gananciaHoy += _activeOrder!.total * 0.15;
        _activeOrder = null;
        _step = 0;
      });
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
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: _activeOrder == null ? _buildOrderList() : _buildActiveOrder(),
    );
  }

  // ── Lista de pedidos ──────────────────────────────────────────────────────────

  Widget _buildOrderList() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(child: _buildHeader()),

        // Ganancias del día
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Expanded(
                  child: _StatBox(
                    label: 'Ganancias hoy',
                    value: '\$${_gananciaHoy.toStringAsFixed(0)} MXN',
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                ),
                Container(width: 1, height: 40, color: AppConstants.surface2Color),
                Expanded(
                  child: _StatBox(
                    label: 'Entregas',
                    value: '$_entregasHoy',
                    icon: Icons.check_circle_outline,
                    color: AppConstants.primaryColor,
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
            child: Text(
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
                    size: 80, color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text('No hay pedidos por ahora',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35), fontSize: 15)),
                const SizedBox(height: 8),
                Text('Cuando llegue un pedido aparecerá aquí',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2), fontSize: 13)),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildOrderCard(_pendingOrders[i]),
                childCount: _pendingOrders.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: const BoxDecoration(color: AppConstants.surfaceColor),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delivery_dining,
                  color: AppConstants.primaryColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Hola, Repartidor',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                Text('Maravatío, Mich.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
              ]),
            ),
            IconButton(
              icon: Icon(Icons.logout, color: Colors.white.withValues(alpha: 0.6), size: 20),
              onPressed: () => context.go('/login'),
              tooltip: 'Salir',
            ),
            // Toggle disponible
            GestureDetector(
              onTap: () => setState(() => _disponible = !_disponible),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _disponible
                      ? Colors.green.withValues(alpha: 0.15)
                      : AppConstants.surface2Color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _disponible ? 'Disponible' : 'No disponible',
                    style: TextStyle(
                      color: _disponible ? Colors.green : Colors.white.withValues(alpha: 0.4),
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

  Widget _buildOrderCard(_Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Restaurant row
            Row(children: [
              Text(order.restaurantIcon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(order.restaurantName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${order.items.length} producto${order.items.length != 1 ? 's' : ''}  •  ${order.distanceKm} km',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                ]),
              ),
              Text('\$${order.total.toStringAsFixed(0)} MXN',
                  style: const TextStyle(
                      color: AppConstants.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            const SizedBox(height: 10),
            // Customer
            Row(children: [
              Icon(Icons.location_on_outlined,
                  color: Colors.white.withValues(alpha: 0.4), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(order.address,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.person_outline,
                  color: Colors.white.withValues(alpha: 0.4), size: 16),
              const SizedBox(width: 6),
              Text(order.customerName,
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
            ]),
          ]),
        ),
        // Botón aceptar
        InkWell(
          onTap: _disponible ? () => _aceptarPedido(order) : null,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _disponible
                  ? AppConstants.primaryColor
                  : AppConstants.surface2Color,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Center(
              child: Text(
                _disponible ? 'ACEPTAR PEDIDO' : 'NO DISPONIBLE',
                style: TextStyle(
                  color: _disponible ? Colors.white : Colors.white.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
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

  Widget _buildActiveOrder() {
    final order = _activeOrder!;
    final sd = _steps[_step];
    final myLatLng = _myPos != null
        ? LatLng(_myPos!.latitude, _myPos!.longitude)
        : null;

    final mapCenter = LatLng(
      (order.restaurantPos.latitude + order.customerPos.latitude) / 2,
      (order.restaurantPos.longitude + order.customerPos.longitude) / 2,
    );

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
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.landing_test',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: order.restaurantPos,
                  width: 44, height: 44,
                  child: _Pin(icon: Icons.storefront, color: AppConstants.primaryColor),
                ),
                Marker(
                  point: order.customerPos,
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
          // Badge GPS transmitiendo (solo en step 2)
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
          // Status badge sobre el mapa
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
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
            ),
          ),
        ]),
      ),

      // ── Detalle del pedido ─────────────────────────────────────────────────
      Expanded(
        child: Container(
          color: AppConstants.bgColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Stepper
              _buildStepper(),
              const SizedBox(height: 20),

              // Cliente
              _SectionLabel('Datos del cliente'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppConstants.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  _InfoRow(Icons.person_outline, order.customerName),
                  const SizedBox(height: 8),
                  _InfoRow(Icons.phone_outlined, order.customerPhone),
                  const SizedBox(height: 8),
                  _InfoRow(Icons.location_on_outlined, order.address),
                ]),
              ),
              const SizedBox(height: 16),

              // Productos
              _SectionLabel('Productos (${order.restaurantName})'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppConstants.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: order.items.asMap().entries.map((e) {
                    final isLast = e.key == order.items.length - 1;
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          const Icon(Icons.fastfood,
                              color: AppConstants.primaryColor, size: 16),
                          const SizedBox(width: 10),
                          Text(e.value,
                              style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ]),
                      ),
                      if (!isLast)
                        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    ]);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total del pedido',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                Text('\$${order.total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
          color: AppConstants.surfaceColor,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
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
                  width: 36,
                  height: 36,
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
  const _StatBox({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppConstants.primaryColor, size: 18),
      const SizedBox(width: 10),
      Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 13))),
    ]);
  }
}
