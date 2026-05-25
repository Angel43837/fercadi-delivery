import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants.dart';
import '../services/order_history_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<HistoryEntry> _orders = [];
  Map<String, dynamic>? _activeOrder;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      OrderHistoryService.getAll(),
      OrderHistoryService.getActiveOrder(),
    ]);
    if (!mounted) return;
    setState(() {
      _orders = results[0] as List<HistoryEntry>;
      _activeOrder = results[1] as Map<String, dynamic>?;
      _loading = false;
    });
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1)    return 'Ayer';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mis pedidos', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 72, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text('Aún no has hecho pedidos',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
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
                    final isActive = _activeOrder != null &&
                        _activeOrder!['orderId'] == o.orderId;
                    return GestureDetector(
                      onTap: isActive
                          ? () => context.go('/tracking', extra: _activeOrder!)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: isActive
                              ? Border.all(
                                  color: AppConstants.primaryColor, width: 1.5)
                              : null,
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isActive
                                  ? Icons.delivery_dining
                                  : Icons.storefront_outlined,
                              color: AppConstants.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.restaurantName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 3),
                                Text(o.address,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 3),
                                if (isActive)
                                  Text('En curso — toca para rastrear',
                                      style: TextStyle(
                                          color: AppConstants.primaryColor
                                              .withValues(alpha: 0.85),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600))
                                else
                                  Text(_formatDate(o.date),
                                      style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('\$${o.total.toStringAsFixed(0)} MXN',
                              style: const TextStyle(
                                  color: AppConstants.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
