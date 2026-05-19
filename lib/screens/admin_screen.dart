import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/app_data_provider.dart';

// Info estática de restaurantes
const _restInfo = [
  (id: '1', name: 'McDonalds',  icon: '🍔', address: 'Av. Principal #123, Maravatío'),
  (id: '2', name: 'Starbucks',  icon: '☕', address: 'Centro Histórico, Maravatío'),
  (id: '3', name: 'Sushi Roll', icon: '🍣', address: 'Plaza Comercial, Maravatío'),
];

// ── Pantalla principal ───────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;
  AppOrderStatus? _filterStatus;

  @override
  Widget build(BuildContext context) {
    final appData = context.watch<AppDataProvider>();
    final orders  = appData.allOrders;
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildDashboard(appData, orders),
              _buildPedidos(appData, orders),
              _buildRestaurantes(appData, orders),
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
            onPressed: () => context.go('/login'),
          ),
        ]),
      ),
    );
  }

  // ── Dashboard ────────────────────────────────────────────────────────────────

  Widget _buildDashboard(AppDataProvider appData, List<AppOrder> orders) {
    final ventasHoy  = orders.where((o) => o.status == AppOrderStatus.entregado).fold<double>(0, (s, o) => s + o.total);
    final pedidosHoy = orders.length;
    final entregados = orders.where((o) => o.status == AppOrderStatus.entregado).length;

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
            _StatCard(label: 'Ventas hoy',   value: '\$${ventasHoy.toStringAsFixed(0)}', suffix: 'MXN',        icon: Icons.attach_money,       color: Colors.green),
            _StatCard(label: 'Pedidos hoy',  value: '$pedidosHoy',                        suffix: 'total',       icon: Icons.receipt_long,       color: AppConstants.primaryColor),
            _StatCard(label: 'Entregados',   value: '$entregados',                        suffix: 'completados', icon: Icons.check_circle_outline, color: const Color(0xFF00BFA5)),
            _StatCard(label: 'Repartidores', value: '2',                                  suffix: 'activos',     icon: Icons.delivery_dining,    color: const Color(0xFFFFB300)),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estado de pedidos hoy',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 14),
            _StatusBar(orders: orders),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _StatusLegend('Pendiente', const Color(0xFFFFB300),   orders.where((o) => o.status == AppOrderStatus.pendiente).length),
              _StatusLegend('En camino', AppConstants.primaryColor, orders.where((o) => o.status == AppOrderStatus.enCamino).length),
              _StatusLegend('Entregado', Colors.green,              orders.where((o) => o.status == AppOrderStatus.entregado).length),
              _StatusLegend('Cancelado', Colors.red,                orders.where((o) => o.status == AppOrderStatus.cancelado).length),
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
        ...orders.take(4).map((o) => _OrderRow(order: o)),
      ],
    );
  }

  // ── Pedidos ──────────────────────────────────────────────────────────────────

  Widget _buildPedidos(AppDataProvider appData, List<AppOrder> orders) {
    final filtered = _filterStatus == null
        ? orders
        : orders.where((o) => o.status == _filterStatus).toList();

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
                itemBuilder: (_, i) => _OrderCard(order: filtered[i]),
              ),
      ),
    ]);
  }

  // ── Restaurantes ─────────────────────────────────────────────────────────────

  Widget _buildRestaurantes(AppDataProvider appData, List<AppOrder> orders) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _restInfo.length,
      itemBuilder: (_, i) {
        final r          = _restInfo[i];
        final isOpen     = appData.isRestaurantOpen(r.id);
        final likes      = appData.getLikes(r.id);
        final ordersToday = orders.where((o) => o.restaurantId == r.id).length;

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
              Text(r.icon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(r.address, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                ]),
              ),
              GestureDetector(
                onTap: () => appData.setRestaurantOpen(r.id, !isOpen),
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
          _NavItem(icon: Icons.dashboard_outlined,    label: 'Resumen',      index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.receipt_long_outlined,  label: 'Pedidos',      index: 1, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.storefront_outlined,    label: 'Restaurantes', index: 2, current: _tab, onTap: (i) => setState(() => _tab = i)),
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

class _StatusBar extends StatelessWidget {
  final List<AppOrder> orders;
  const _StatusBar({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox();
    final pending  = orders.where((o) => o.status == AppOrderStatus.pendiente).length;
    final transit  = orders.where((o) => o.status == AppOrderStatus.enCamino).length;
    final done     = orders.where((o) => o.status == AppOrderStatus.entregado).length;
    final canceled = orders.where((o) => o.status == AppOrderStatus.cancelado).length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(children: [
        if (pending  > 0) Expanded(flex: pending,  child: Container(height: 10, color: const Color(0xFFFFB300))),
        if (transit  > 0) Expanded(flex: transit,  child: Container(height: 10, color: AppConstants.primaryColor)),
        if (done     > 0) Expanded(flex: done,     child: Container(height: 10, color: Colors.green)),
        if (canceled > 0) Expanded(flex: canceled, child: Container(height: 10, color: Colors.red)),
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

class _OrderRow extends StatelessWidget {
  final AppOrder order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final st = appOrderStatusStyle(order.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Text(order.restaurantIcon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.restaurantName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(order.customer, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${order.total.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(st.label, style: TextStyle(color: st.color, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final AppOrder order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final st = appOrderStatusStyle(order.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: st.color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Text(order.restaurantIcon, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('#${order.id}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
              const SizedBox(width: 6),
              Text(order.time, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ]),
            const SizedBox(height: 2),
            Text(order.restaurantName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            Text('${order.customer}  •  ${order.itemsCount} producto${order.itemsCount != 1 ? 's' : ''}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${order.total.toStringAsFixed(0)} MXN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(st.label, style: TextStyle(color: st.color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
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
