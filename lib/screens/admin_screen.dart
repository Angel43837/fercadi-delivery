// admin_screen.dart
// Panel del administrador de la plataforma Grupo Fercadi.
// Solo accesible con rol "admin" (email: admin@fercadi.com).
// Permite ver todos los pedidos de todos los restaurantes,
// gestionar restaurantes, usuarios y configuración general de la plataforma.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/app_data_provider.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

// ── Pantalla principal ───────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;
  AppOrderStatus? _filterStatus;
  List<Map<String, dynamic>> _realOrders = [];
  List<Map<String, dynamic>> _restaurants = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _loadRestaurants();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOrders();
      _loadRestaurants();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    try {
      final data = await SupabaseService.getActiveOrders();
      if (mounted) setState(() => _realOrders = data);
    } catch (_) {}
  }

  Future<void> _loadRestaurants() async {
    try {
      final data = await SupabaseService.getRestaurantsAdmin();
      if (mounted) setState(() => _restaurants = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final appData = context.watch<AppDataProvider>();
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildDashboard(appData),
              _buildPedidos(),
              _buildRestaurantes(appData),
              _buildUsuarios(),
            ],
          ),
        ),
        _buildBottomNav(),
      ]),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: AppConstants.surfaceColor,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.admin_panel_settings,
                color: AppConstants.primaryColor, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Panel de Administrador',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Grupo Fercadi • Maravatío',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('En línea', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white.withValues(alpha: 0.5), size: 20),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final router = GoRouter.of(context);
              await AuthService.clearSession();
              router.go('/login');
            },
          ),
        ]),
      ),
    );
  }

  // ── Dashboard ────────────────────────────────────────────────────────────────

  Widget _buildDashboard(AppDataProvider appData) {
    final ventasHoy  = _realOrders.where((o) => o['status'] == 'delivered').fold<double>(0, (s, o) => s + ((o['total'] as num?)?.toDouble() ?? 0));
    final pedidosHoy = _realOrders.length;
    final entregados = _realOrders.where((o) => o['status'] == 'delivered').length;
    final pendientes = _realOrders.where((o) => o['status'] == 'pending').length;
    final enCamino   = _realOrders.where((o) => o['status'] == 'delivering' || o['status'] == 'accepted').length;
    final cancelados = _realOrders.where((o) => o['status'] == 'cancelled').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard(label: 'Ventas hoy',   value: '\$${ventasHoy.toStringAsFixed(0)}', suffix: 'MXN',        icon: Icons.attach_money,        color: Colors.green),
            _StatCard(label: 'Pedidos hoy',  value: '$pedidosHoy',                        suffix: 'total',       icon: Icons.receipt_long,        color: AppConstants.primaryColor),
            _StatCard(label: 'Entregados',   value: '$entregados',                        suffix: 'completados', icon: Icons.check_circle_outline, color: const Color(0xFF00BFA5)),
            _StatCard(label: 'Restaurantes', value: '${_restaurants.length}',             suffix: 'registrados', icon: Icons.storefront,           color: const Color(0xFFFFB300)),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estado de pedidos',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 14),
            if (pedidosHoy > 0) ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(children: [
                if (pendientes > 0) Expanded(flex: pendientes, child: Container(height: 10, color: const Color(0xFFFFB300))),
                if (enCamino   > 0) Expanded(flex: enCamino,   child: Container(height: 10, color: AppConstants.primaryColor)),
                if (entregados > 0) Expanded(flex: entregados, child: Container(height: 10, color: Colors.green)),
                if (cancelados > 0) Expanded(flex: cancelados, child: Container(height: 10, color: Colors.red)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _StatusLegend('Pendiente', const Color(0xFFFFB300),   pendientes),
              _StatusLegend('En camino', AppConstants.primaryColor, enCamino),
              _StatusLegend('Entregado', Colors.green,              entregados),
              _StatusLegend('Cancelado', Colors.red,                cancelados),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Últimos pedidos',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          TextButton(
            onPressed: () => setState(() => _tab = 1),
            child: const Text('Ver todos', style: TextStyle(color: AppConstants.primaryColor, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        ..._realOrders.take(4).map((o) => _RealOrderMiniRow(order: o)),
      ],
    );
  }

  // ── Pedidos ──────────────────────────────────────────────────────────────────

  Widget _buildPedidos() {
    final filtered = _filterStatus == null
        ? _realOrders
        : _realOrders.where((o) {
            final s = o['status'] as String? ?? '';
            switch (_filterStatus) {
              case AppOrderStatus.pendiente: return s == 'pending';
              case AppOrderStatus.enCamino:  return s == 'delivering' || s == 'accepted';
              case AppOrderStatus.entregado: return s == 'delivered';
              case AppOrderStatus.cancelado: return s == 'cancelled';
              default: return true;
            }
          }).toList();

    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          _FilterChip('Todos',     null,                        _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Pendiente', AppOrderStatus.pendiente,   _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('En camino', AppOrderStatus.enCamino,    _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Entregado', AppOrderStatus.entregado,   _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Cancelado', AppOrderStatus.cancelado,   _filterStatus, (v) => setState(() => _filterStatus = v)),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('Sin pedidos', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _RealOrderCard(order: filtered[i]),
              ),
      ),
    ]);
  }

  // ── Restaurantes ─────────────────────────────────────────────────────────────

  Widget _buildRestaurantes(AppDataProvider appData) {
    if (_restaurants.isEmpty) {
      return Center(
        child: Text('Sin restaurantes registrados',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _restaurants.length,
      itemBuilder: (_, i) {
        final r           = _restaurants[i];
        final id          = r['id']         as String? ?? '';
        final icon        = r['emoji_icon'] as String? ?? '🍽️';
        final name        = r['name']       as String? ?? 'Restaurante';
        final address     = r['address']    as String? ?? '';
        final isOpen      = appData.isRestaurantOpen(id);
        final likes       = appData.getLikes(id);
        final ordersToday = _realOrders.where((o) => o['restaurant_id'] == id).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppConstants.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: isOpen ? Border.all(color: Colors.green.withValues(alpha: 0.3)) : null,
          ),
          child: Column(children: [
            Row(children: [
              Text(icon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(address, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                ]),
              ),
              GestureDetector(
                onTap: () => appData.setRestaurantOpen(id, !isOpen),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOpen ? Colors.green.withValues(alpha: 0.12) : AppConstants.surface2Color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOpen ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    isOpen ? 'Abierto' : 'Cerrado',
                    style: TextStyle(
                      color: isOpen ? Colors.green : Colors.white.withValues(alpha: 0.35),
                      fontSize: 12, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _MiniStat(label: 'Pedidos hoy', value: '$ordersToday', icon: Icons.receipt_long_outlined, color: AppConstants.primaryColor),
              _MiniStat(label: 'Likes',        value: '$likes',       icon: Icons.thumb_up,              color: AppConstants.primaryColor),
              _MiniStat(label: 'Estado',       value: isOpen ? 'Activo' : 'Inactivo', icon: Icons.circle, color: isOpen ? Colors.green : Colors.red),
            ]),
          ]),
        );
      },
    );
  }

  // ── Usuarios ─────────────────────────────────────────────────────────────────

  static const _mockRepartidores = [
    (name: 'Carlos Mendoza',  moto: 'Honda CB125 • MV-123-AB', entregas: 42, color: Color(0xFF00BFA5)),
    (name: 'Luis Hernández',  moto: 'Yamaha FZ150 • MV-456-CD', entregas: 31, color: Color(0xFF7C4DFF)),
    (name: 'Miguel Torres',   moto: 'Italika DS125 • MV-789-EF', entregas: 18, color: Color(0xFFFF6D00)),
  ];

  Widget _buildUsuarios() {
    // Extraer clientes únicos de los pedidos reales
    final Map<String, Map<String, dynamic>> clientMap = {};
    for (final o in _realOrders) {
      Map<String, dynamic> delivery = {};
      try { delivery = jsonDecode(o['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}
      final phone = delivery['phone'] as String? ?? '—';
      if (!clientMap.containsKey(phone)) {
        clientMap[phone] = {
          'name':   delivery['name']    as String? ?? 'Cliente',
          'phone':  phone,
          'orders': 0,
          'total':  0.0,
        };
      }
      clientMap[phone]!['orders'] = (clientMap[phone]!['orders'] as int) + 1;
      clientMap[phone]!['total']  = (clientMap[phone]!['total'] as double) + ((o['total'] as num?)?.toDouble() ?? 0);
    }
    final clients = clientMap.values.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Clientes
        _SectionTitle(icon: Icons.people_outline, label: 'Clientes registrados (${clients.length})'),
        const SizedBox(height: 10),
        if (clients.isEmpty)
          _EmptyHint('Sin pedidos registrados aún')
        else
          ...clients.map((c) => _UserTile(
            name:     c['name'] as String,
            subtitle: c['phone'] as String,
            trailing: '${c['orders']} pedido${(c['orders'] as int) != 1 ? 's' : ''} • \$${(c['total'] as double).toStringAsFixed(0)}',
            color:    AppConstants.primaryColor,
            icon:     Icons.person_outline,
          )),
        const SizedBox(height: 24),

        // Repartidores
        _SectionTitle(icon: Icons.delivery_dining, label: 'Repartidores (${_mockRepartidores.length})'),
        const SizedBox(height: 10),
        ..._mockRepartidores.map((r) => _UserTile(
          name:     r.name,
          subtitle: r.moto,
          trailing: '${r.entregas} entregas',
          color:    r.color,
          icon:     Icons.delivery_dining,
        )),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          _NavItem(icon: Icons.dashboard_outlined,   label: 'Resumen',      index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.receipt_long_outlined, label: 'Pedidos',      index: 1, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.storefront_outlined,   label: 'Restaurantes', index: 2, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.people_outline,        label: 'Usuarios',     index: 3, current: _tab, onTap: (i) => setState(() => _tab = i)),
        ]),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value, suffix;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.suffix, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const Spacer(),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
      ]),
    );
  }
}

class _RealOrderMiniRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _RealOrderMiniRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}
    final name  = delivery['name'] as String? ?? 'Cliente';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final items = (order['order_items'] as List<dynamic>? ?? []);
    final itemNames = items.map((i) {
      final qty     = i['quantity'] as int? ?? 1;
      final product = i['products'] as Map<String, dynamic>?;
      return '$qty× ${product?['name'] ?? 'Producto'}';
    }).join(', ');

    final (statusLabel, statusColor) = switch (status) {
      'pending'    => ('Pendiente',   const Color(0xFFFFB300)),
      'accepted'   => ('Aceptado',    AppConstants.primaryColor),
      'delivering' => ('En camino',   const Color(0xFF2196F3)),
      'delivered'  => ('Entregado',   Colors.green),
      'cancelled'  => ('Cancelado',   Colors.red),
      _            => ('Desconocido', Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(itemNames.isEmpty ? 'Sin productos' : itemNames,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${total.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _RealOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _RealOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}

    final name    = delivery['name']    as String? ?? 'Cliente';
    final phone   = delivery['phone']   as String? ?? '—';
    final address = delivery['address'] as String? ?? 'Sin dirección';
    final total   = (order['total'] as num?)?.toDouble() ?? 0;
    final items   = (order['order_items'] as List<dynamic>? ?? []);

    final (statusLabel, statusColor) = switch (status) {
      'pending'    => ('Pendiente',   const Color(0xFFFFB300)),
      'accepted'   => ('Aceptado',    AppConstants.primaryColor),
      'delivering' => ('En camino',   const Color(0xFF2196F3)),
      'delivered'  => ('Entregado',   Colors.green),
      'cancelled'  => ('Cancelado',   Colors.red),
      _            => ('Desconocido', Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${(order['id'] as String? ?? '------').substring(0, 6).toUpperCase()}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text(phone,   style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
        const SizedBox(height: 2),
        Text(address, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
        const SizedBox(height: 8),
        ...items.map((i) {
          final qty     = i['quantity'] as int? ?? 1;
          final product = i['products'] as Map<String, dynamic>?;
          final pname   = product?['name'] as String? ?? 'Producto';
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              Icon(Icons.circle, size: 5, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 6),
              Text('$qty× $pname',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
            ]),
          );
        }),
        const SizedBox(height: 10),
        Text('\$${total.toStringAsFixed(0)} MXN',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  const _StatusLegend(this.label, this.color, this.count);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppConstants.primaryColor, size: 18),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
    ]);
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String name, subtitle, trailing;
  final Color color;
  final IconData icon;
  const _UserTile({required this.name, required this.subtitle, required this.trailing, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          ]),
        ),
        Text(trailing, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final AppOrderStatus? value, current;
  final ValueChanged<AppOrderStatus?> onTap;
  const _FilterChip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final color = value == null ? AppConstants.primaryColor : appOrderStatusStyle(value!).color;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : color.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, current;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: active ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.3), size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: active ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}
