import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/app_data_provider.dart';
import '../services/supabase_service.dart';

class _Product {
  final String id;
  String name;
  String description;
  double price;
  bool isAvailable;
  final String categoryId;
  String? imagePath;

  _Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    required this.categoryId,
    this.imagePath,
  });
}

class _Category {
  final String id;
  final String name;
  final String emoji;
  const _Category({required this.id, required this.name, required this.emoji});
}

class DuenoScreen extends StatefulWidget {
  const DuenoScreen({super.key});

  @override
  State<DuenoScreen> createState() => _DuenoScreenState();
}

class _DuenoScreenState extends State<DuenoScreen> {
  int _tab = 0;
  AppOrderStatus? _filterStatus;

  final List<_Category> _categories = const [
    _Category(id: 'c1',  name: 'Hamburguesas', emoji: '🍔'),
    _Category(id: 'c2',  name: 'Papas',        emoji: '🍟'),
    _Category(id: 'c3',  name: 'Bebidas',       emoji: '🥤'),
    _Category(id: 'c10', name: 'Postres',       emoji: '🍦'),
    _Category(id: 'c11', name: 'Ensaladas',     emoji: '🥗'),
    _Category(id: 'c12', name: 'Desayunos',     emoji: '🥞'),
  ];

  final List<_Product> _products = [
    _Product(id: 'p1', name: 'Big Mac',         description: 'Dos carnes, lechuga, queso, cebolla y salsa especial', price: 89,  isAvailable: true,  categoryId: 'c1'),
    _Product(id: 'p2', name: 'Quarter Pounder', description: 'Carne 100% res, queso americano, cebolla y mostaza',   price: 95,  isAvailable: true,  categoryId: 'c1'),
    _Product(id: 'p3', name: 'McPollo Crispy',  description: 'Pollo crujiente, lechuga y mayonesa en pan tostado',   price: 79,  isAvailable: false, categoryId: 'c1'),
    _Product(id: 'p4', name: 'Papas Medianas',  description: 'Papas fritas crujientes con sal',                      price: 35,  isAvailable: true,  categoryId: 'c2'),
    _Product(id: 'p5', name: 'Papas Grandes',   description: 'Porción grande de papas fritas',                       price: 45,  isAvailable: true,  categoryId: 'c2'),
    _Product(id: 'p6', name: 'Coca-Cola 500ml', description: 'Refresco frío en vaso',                                price: 30,  isAvailable: true,  categoryId: 'c3'),
    _Product(id: 'p7', name: 'Café Americano',  description: 'Café negro recién preparado',                          price: 40,  isAvailable: true,  categoryId: 'c3'),
    _Product(id: 'p8', name: 'McFlurry Oreo',   description: 'Helado suave con trozos de galleta Oreo',              price: 55,  isAvailable: true,  categoryId: 'c10'),
  ];

  @override
  Widget build(BuildContext context) {
    final appData = context.watch<AppDataProvider>();
    final orders = appData.ordersForRestaurant('1');
    final isOpen = appData.isRestaurantOpen('1');
    final pendingCount = orders.where((o) => o.status == AppOrderStatus.pendiente).length;

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: Column(children: [
        _buildHeader(appData, isOpen),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildDashboard(orders),
              _buildPedidos(appData, orders),
              _buildMenu(appData),
            ],
          ),
        ),
        _buildBottomNav(pendingCount),
      ]),
    );
  }

  Widget _buildHeader(AppDataProvider appData, bool isOpen) {
    return Container(
      color: AppConstants.surfaceColor,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          const Text('🍔', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('McDonalds',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Panel del restaurante',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            ]),
          ),
          GestureDetector(
            onTap: () => appData.setRestaurantOpen('1', !isOpen),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOpen ? Colors.green.withValues(alpha: 0.12) : AppConstants.surface2Color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOpen ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: isOpen ? Colors.green : Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOpen ? 'Abierto' : 'Cerrado',
                  style: TextStyle(
                    color: isOpen ? Colors.green : Colors.white.withValues(alpha: 0.35),
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDashboard(List<AppOrder> orders) {
    final ventasHoy = orders
        .where((o) => o.status == AppOrderStatus.entregado)
        .fold<double>(0, (s, o) => s + o.total);
    final entregados = orders.where((o) => o.status == AppOrderStatus.entregado).length;
    final pendientes = orders.where((o) => o.status == AppOrderStatus.pendiente).length;

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
            _StatCard(label: 'Pedidos hoy',  value: '${orders.length}',                  suffix: 'total',       icon: Icons.receipt_long,        color: AppConstants.primaryColor),
            _StatCard(label: 'Entregados',   value: '$entregados',                        suffix: 'completados', icon: Icons.check_circle_outline, color: const Color(0xFF00BFA5)),
            _StatCard(label: 'Pendientes',   value: '$pendientes',                        suffix: 'en espera',   icon: Icons.hourglass_bottom,    color: const Color(0xFFFFB300)),
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

  Widget _buildPedidos(AppDataProvider appData, List<AppOrder> orders) {
    final filtered = _filterStatus == null
        ? orders
        : orders.where((o) => o.status == _filterStatus).toList();

    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          _FilterChip('Todos',     null,                       _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Pendiente', AppOrderStatus.pendiente,  _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('En camino', AppOrderStatus.enCamino,   _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Entregado', AppOrderStatus.entregado,  _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Cancelado', AppOrderStatus.cancelado,  _filterStatus, (v) => setState(() => _filterStatus = v)),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('Sin pedidos', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _OrderCard(
                  order: filtered[i],
                  onStatusChanged: (newStatus) =>
                      appData.updateOrderStatus(filtered[i].id, newStatus),
                ),
              ),
      ),
    ]);
  }

  Widget _buildMenu(AppDataProvider appData) {
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: _categories.map((cat) {
          final preseeded = _products.where((p) => p.categoryId == cat.id).toList();
          final extra = appData.extraProductsForCategory('1', cat.id);
          if (preseeded.isEmpty && extra.isEmpty) return const SizedBox();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(cat.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  Text('(${preseeded.length + extra.length})',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
                ]),
              ),
              ...preseeded.map((p) {
                final avail = appData.getProductAvailability(p.id, p.isAvailable);
                return _ProductTile(
                  product: p,
                  isAvailable: avail,
                  onToggle: () {
                    appData.setProductAvailability(p.id, !avail);
                    SupabaseService.setProductAvailability(p.id, !avail);
                  },
                  onEdit: () => _showProductForm(p, isExtra: false),
                );
              }),
              ...extra.map((sp) {
                final p = _Product(
                  id: sp.id, name: sp.name, description: sp.description,
                  price: sp.price, isAvailable: sp.isAvailable,
                  categoryId: sp.categoryId, imagePath: sp.imagePath,
                );
                final avail = appData.getProductAvailability(sp.id, sp.isAvailable);
                return _ProductTile(
                  product: p,
                  isAvailable: avail,
                  onToggle: () {
                    appData.setProductAvailability(sp.id, !avail);
                    SupabaseService.setProductAvailability(sp.id, !avail);
                  },
                  onEdit: () => _showProductForm(p, isExtra: true),
                );
              }),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton.extended(
          backgroundColor: AppConstants.primaryColor,
          onPressed: () => _showProductForm(null, isExtra: false),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Nuevo platillo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }

  void _showProductForm(_Product? existing, {bool isExtra = false}) {
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final descCtrl  = TextEditingController(text: existing?.description ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(0) : '');
    String selectedCatId = existing?.categoryId ?? _categories.first.id;
    bool available = existing?.isAvailable ?? true;
    String? pickedImagePath = existing?.imagePath;
    final picker = ImagePicker();

    Future<void> pickImage(ImageSource source, StateSetter setModal) async {
      final xfile = await picker.pickImage(source: source, imageQuality: 80);
      if (xfile != null) setModal(() => pickedImagePath = xfile.path);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              existing == null ? 'Nuevo platillo' : 'Editar platillo',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: ctx,
                backgroundColor: AppConstants.surfaceColor,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 12),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: AppConstants.primaryColor),
                      ),
                      title: const Text('Tomar foto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text('Abre la cámara', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                      onTap: () { Navigator.pop(ctx); pickImage(ImageSource.camera, setModal); },
                    ),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library, color: Color(0xFF2196F3)),
                      ),
                      title: const Text('Elegir de galería', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text('Selecciona una foto', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                      onTap: () { Navigator.pop(ctx); pickImage(ImageSource.gallery, setModal); },
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
              child: Container(
                width: double.infinity, height: 150,
                decoration: BoxDecoration(
                  color: AppConstants.surface2Color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pickedImagePath != null
                        ? AppConstants.primaryColor.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: pickedImagePath != null
                    ? Stack(fit: StackFit.expand, children: [
                        kIsWeb
                            ? Image.network(pickedImagePath!, fit: BoxFit.cover)
                            : Image.file(File(pickedImagePath!), fit: BoxFit.cover),
                        Positioned(
                          bottom: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.edit, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text('Cambiar', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ]),
                          ),
                        ),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined,
                            color: Colors.white.withValues(alpha: 0.3), size: 36),
                        const SizedBox(height: 8),
                        Text('Agregar foto del platillo',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Cámara o galería',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                      ]),
              ),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              initialValue: selectedCatId,
              dropdownColor: AppConstants.surface2Color,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Categoría'),
              items: _categories.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text('${c.emoji} ${c.name}'),
              )).toList(),
              onChanged: (v) => setModal(() => selectedCatId = v!),
            ),
            const SizedBox(height: 12),
            _FormField(controller: nameCtrl,  label: 'Nombre del platillo', icon: Icons.fastfood_outlined),
            const SizedBox(height: 12),
            _FormField(controller: descCtrl,  label: 'Descripción',         icon: Icons.notes, maxLines: 2),
            const SizedBox(height: 12),
            _FormField(controller: priceCtrl, label: 'Precio (MXN)',        icon: Icons.attach_money, keyboardType: TextInputType.number),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: AppConstants.surface2Color, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.storefront_outlined, color: Colors.white.withValues(alpha: 0.5), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Disponible en el menú',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                ),
                Switch(
                  value: available,
                  activeThumbColor: AppConstants.primaryColor,
                  onChanged: (v) => setModal(() => available = v),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                  final appData = context.read<AppDataProvider>();
                  final newId = existing?.id ?? 'ep${DateTime.now().millisecondsSinceEpoch}';
                  final name = nameCtrl.text.trim();
                  final desc = descCtrl.text.trim();
                  final price = double.tryParse(priceCtrl.text.trim()) ?? existing?.price ?? 0;

                  if (existing == null) {
                    appData.addExtraProduct(SharedProduct(
                      id: newId, name: name, description: desc,
                      price: price, isAvailable: available,
                      categoryId: selectedCatId, restaurantId: '1',
                      imagePath: pickedImagePath,
                    ));
                  } else if (isExtra) {
                    appData.updateExtraProduct(SharedProduct(
                      id: existing.id, name: name, description: desc,
                      price: price, isAvailable: available,
                      categoryId: existing.categoryId, restaurantId: '1',
                      imagePath: pickedImagePath,
                    ));
                    appData.setProductAvailability(existing.id, available);
                  } else {
                    setState(() {
                      existing.name = name; existing.description = desc;
                      existing.price = price; existing.isAvailable = available;
                      existing.imagePath = pickedImagePath;
                    });
                    appData.setProductAvailability(existing.id, available);
                  }

                  // Guardar en Supabase
                  SupabaseService.saveProduct(
                    id: newId, name: name, description: desc,
                    price: price, isAvailable: available,
                    categoryId: selectedCatId,
                    restaurantId: '1',
                  );

                  Navigator.pop(ctx);
                },
                child: Text(
                  existing == null ? 'AGREGAR PLATILLO' : 'GUARDAR CAMBIOS',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomNav(int pendingCount) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          _NavItem(icon: Icons.dashboard_outlined,    label: 'Resumen', index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
          _NavItem(icon: Icons.receipt_long_outlined,  label: 'Pedidos', index: 1, current: _tab, onTap: (i) => setState(() => _tab = i), badge: pendingCount),
          _NavItem(icon: Icons.menu_book_outlined,    label: 'Menú',    index: 2, current: _tab, onTap: (i) => setState(() => _tab = i)),
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
    final total = orders.length;
    if (total == 0) return const SizedBox();
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
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.customer, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(order.items.join(', '),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
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
  final ValueChanged<AppOrderStatus> onStatusChanged;
  const _OrderCard({required this.order, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    final st = appOrderStatusStyle(order.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: st.color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${order.id}', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
          const SizedBox(width: 8),
          Text(order.time, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(st.label, style: TextStyle(color: st.color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(order.customer, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        ...order.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            Icon(Icons.circle, size: 5, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 6),
            Text(item, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
          ]),
        )),
        const SizedBox(height: 10),
        Row(children: [
          Text('\$${order.total.toStringAsFixed(0)} MXN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          if (order.status == AppOrderStatus.pendiente)
            _ActionBtn(label: 'Aceptar pedido',   color: AppConstants.primaryColor, onTap: () => onStatusChanged(AppOrderStatus.enCamino)),
          if (order.status == AppOrderStatus.enCamino)
            _ActionBtn(label: 'Marcar entregado', color: Colors.green,              onTap: () => onStatusChanged(AppOrderStatus.entregado)),
        ]),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final _Product product;
  final bool isAvailable;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _ProductTile({required this.product, required this.isAvailable, required this.onToggle, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: isAvailable ? null : Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: product.imagePath != null
              ? (kIsWeb
                  ? Image.network(product.imagePath!, width: 60, height: 60, fit: BoxFit.cover)
                  : Image.file(File(product.imagePath!), width: 60, height: 60, fit: BoxFit.cover))
              : Container(
                  width: 60, height: 60,
                  color: AppConstants.surface2Color,
                  child: Icon(Icons.fastfood_outlined, color: Colors.white.withValues(alpha: 0.2), size: 26),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name,
                style: TextStyle(
                    color: isAvailable ? Colors.white : Colors.white.withValues(alpha: 0.35),
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(product.description,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            const SizedBox(height: 6),
            Text('\$${product.price.toStringAsFixed(0)} MXN',
                style: TextStyle(
                    color: isAvailable ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.25),
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.edit_outlined, color: Colors.white.withValues(alpha: 0.4), size: 20),
          onPressed: onEdit,
        ),
        Switch(
          value: isAvailable,
          activeThumbColor: AppConstants.primaryColor,
          onChanged: (_) => onToggle(),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final AppOrderStatus? value;
  final AppOrderStatus? current;
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
  final int badge;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(children: [
              Icon(icon, color: active ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.3), size: 22),
              if (badge > 0)
                Positioned(
                  right: 0, top: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ]),
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

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  const _FormField({required this.controller, required this.label, required this.icon, this.maxLines = 1, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 20),
        filled: true,
        fillColor: AppConstants.surface2Color,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.primaryColor)),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
  filled: true,
  fillColor: AppConstants.surface2Color,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppConstants.primaryColor)),
);
