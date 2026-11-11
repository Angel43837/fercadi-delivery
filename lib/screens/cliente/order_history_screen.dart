// order_history_screen.dart
// Pantalla de historial de pedidos del cliente.
// Muestra pedidos anteriores guardados en el teléfono (SharedPreferences).
// Si hay un pedido activo en curso, muestra un banner para volver al tracking.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gogo_core/core/constants.dart';
import 'package:gogo_core/models/product.dart';
import '../../providers/cart_provider.dart';
import '../../services/order_history_service.dart';
import 'package:gogo_core/services/supabase_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<HistoryEntry> _orders = [];
  // Varios pedidos pueden estar en curso a la vez — antes solo se guardaba
  // UN "pedido activo" en un slot local, así que un segundo pedido hecho
  // mientras el primero seguía en curso dejaba de marcarse como activo
  // aquí. Ahora se leen en vivo todos los pedidos activos reales desde la BD.
  List<Map<String, dynamic>> _activeOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Antes un solo Future.wait sin try/catch dejaba el loading pegado para
    // siempre si getMyActiveOrders fallaba (ej. sin internet) — ahora cada
    // parte se resuelve por su cuenta: sin conexión, igual se ve el
    // historial local, solo sin los pedidos activos en vivo.
    var orders = <HistoryEntry>[];
    try {
      orders = await OrderHistoryService.getAll();
    } catch (_) {}
    var activeRaw = <Map<String, dynamic>>[];
    try {
      activeRaw = await SupabaseService.getMyActiveOrders();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _orders = orders;
      // Un pedido de 2 restaurantes crea 2 filas en "orders" — se combinan
      // aquí (mergeGroupedOrders) para que, al tocar la tarjeta de ese
      // pedido, se mande a /tracking el resumen combinado (ambos
      // restaurantes) en vez de solo la info de UNA de las 2 piernas.
      _activeOrders = SupabaseService.mergeGroupedOrders(activeRaw);
      _loading = false;
    });
    await _backfillMissingData(orders);
  }

  // Busca por el id de cualquiera de las 2 piernas de un pedido combinado —
  // el historial local (HistoryEntry.orderId) siempre guarda el id del
  // PRIMER restaurante creado (ver checkout_screen.dart), que podría quedar
  // como la "pierna hermana" dentro de la entrada ya combinada.
  Map<String, dynamic>? _activeOrderFor(String orderId) {
    for (final o in _activeOrders) {
      if (o['id'] == orderId) return o;
      final sibling = o['group_sibling'] as Map<String, dynamic>?;
      if (sibling != null && sibling['id'] == orderId) return o;
    }
    return null;
  }

  // Pedidos guardados antes de que existiera el logo/resumen de productos
  // se completan una vez desde Supabase, para no quedarse mostrando el
  // ícono genérico y el nombre del restaurante para siempre.
  Future<void> _backfillMissingData(List<HistoryEntry> orders) async {
    final pending = orders.where((o) => o.restaurantImageUrl == null || o.itemsSummary == null);
    var changed = false;
    for (final o in pending) {
      try {
        final order = await SupabaseService.getOrderById(o.orderId);
        if (order == null) continue;
        final restaurant = order['restaurants'] as Map<String, dynamic>?;
        final imageUrl = restaurant?['image_url'] as String?;
        final items = (order['order_items'] as List?) ?? [];
        final summary = items
            .map((it) {
              final p = (it as Map<String, dynamic>)['products'] as Map<String, dynamic>?;
              final qty = (it['quantity'] as num?)?.toInt() ?? 1;
              return p == null ? null : '${qty}x ${p['name']}';
            })
            .whereType<String>()
            .join(', ');
        await OrderHistoryService.backfill(
          o.orderId,
          restaurantImageUrl: imageUrl,
          itemsSummary: summary.isEmpty ? null : summary,
        );
        changed = true;
      } catch (_) {}
    }
    if (changed && mounted) {
      final fresh = await OrderHistoryService.getAll();
      setState(() => _orders = fresh);
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1)    return 'Ayer';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _confirmReorder(HistoryEntry o) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.primaryColor,
        title: const Text('¿Volver a pedir?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(o.itemsSummary ?? o.restaurantName,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, volver a pedir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final order = await SupabaseService.getOrderById(o.orderId);
      final restaurantId = order?['restaurant_id'] as String?;
      final items = (order?['order_items'] as List?) ?? [];
      if (order == null || restaurantId == null || items.isEmpty) {
        throw Exception('Ya no se encuentra ese pedido');
      }
      final restaurantName =
          (order['restaurants'] as Map<String, dynamic>?)?['name'] as String? ?? o.restaurantName;

      final cart = context.read<CartProvider>();
      cart.clear();
      for (final it in items) {
        final productJson = (it as Map<String, dynamic>)['products'] as Map<String, dynamic>?;
        if (productJson == null) continue;
        final product = Product.fromJson(productJson);
        if (!product.isAvailable) continue;
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        for (var k = 0; k < qty; k++) {
          cart.addProduct(product, restaurantId, restaurantName);
        }
      }
      if (cart.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Esos productos ya no están disponibles.'),
            backgroundColor: Colors.redAccent,
          ));
        }
        return;
      }
      if (mounted) context.push('/checkout');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo volver a pedir: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reportarProblema(HistoryEntry o) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.primaryColor,
        title: const Text('Reportar un problema',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o.itemsSummary ?? o.restaurantName,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cuéntanos qué pasó (faltante, error, calidad...)',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      await SupabaseService.requestOrderRefund(o.orderId, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Listo, tu reporte ya quedó registrado. Te avisamos cuando lo revisemos.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo enviar tu reporte: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.primaryColor,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mis pedidos', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 72, color: Colors.white.withValues(alpha: 0.35)),
                      const SizedBox(height: 16),
                      Text('Aún no has hecho pedidos',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final o = _orders[i];
                    final activeOrder = _activeOrderFor(o.orderId);
                    final isActive = activeOrder != null;
                    return GestureDetector(
                      onTap: isActive
                          ? () => context.go('/tracking', extra: SupabaseService.orderToTrackingExtra(activeOrder))
                          : () => _confirmReorder(o),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: isActive
                              ? Border.all(
                                  color: AppConstants.primaryColor, width: 1.5)
                              : null,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
                        ),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: (o.restaurantImageUrl != null && o.restaurantImageUrl!.isNotEmpty)
                                ? Image.network(
                                    o.restaurantImageUrl!,
                                    width: 42, height: 42, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _OrderIconFallback(isActive: isActive),
                                  )
                                : _OrderIconFallback(isActive: isActive),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.itemsSummary ?? o.restaurantName,
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                Text(o.itemsSummary != null ? o.restaurantName : o.address,
                                    style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                if (isActive)
                                  const Text('En curso — toca para rastrear',
                                      style: TextStyle(
                                          color: AppConstants.primaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600))
                                else
                                  Text(_formatDate(o.date),
                                      style: const TextStyle(
                                          color: Colors.black38,
                                          fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('\$${o.total.toStringAsFixed(0)} MXN',
                                  style: const TextStyle(
                                      color: AppConstants.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              if (!isActive)
                                GestureDetector(
                                  onTap: () => _reportarProblema(o),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('Reportar problema',
                                        style: TextStyle(
                                            color: Colors.black38,
                                            fontSize: 10,
                                            decoration: TextDecoration.underline)),
                                  ),
                                ),
                            ],
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

class _OrderIconFallback extends StatelessWidget {
  final bool isActive;
  const _OrderIconFallback({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42, height: 42,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isActive ? Icons.delivery_dining : Icons.storefront_outlined,
        color: AppConstants.primaryColor,
        size: 22,
      ),
    );
  }
}
