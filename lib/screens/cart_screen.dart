import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/cart_provider.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: const Text('Mi Carrito', style: TextStyle(color: Colors.white)),
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 16),
                  Text('Tu carrito está vacío',
                      style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.4))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/restaurants'),
                    child: const Text('Ver restaurantes', style: TextStyle(color: AppConstants.primaryColor)),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    itemBuilder: (context, i) {
                      final item = cart.items[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 60,
                                height: 60,
                                color: AppConstants.surface2Color,
                                child: item.product.imageUrl != null
                                    ? Image.network(item.product.imageUrl!, fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(Icons.fastfood, color: AppConstants.primaryColor))
                                    : const Icon(Icons.fastfood, color: AppConstants.primaryColor),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
                                  Text(
                                    '\$${item.product.price.toStringAsFixed(0)} c/u',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                _SmallButton(
                                  icon: Icons.remove,
                                  onTap: () => context.read<CartProvider>()
                                      .updateQuantity(item.product.id, item.quantity - 1),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('${item.quantity}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                                _SmallButton(
                                  icon: Icons.add,
                                  primary: true,
                                  onTap: () => context.read<CartProvider>()
                                      .updateQuantity(item.product.id, item.quantity + 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _OrderSummary(cart: cart),
              ],
            ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _SmallButton({required this.icon, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: primary ? AppConstants.primaryColor : AppConstants.surface2Color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final CartProvider cart;
  const _OrderSummary({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${cart.count} producto${cart.count != 1 ? 's' : ''}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
                Text(
                  '\$${cart.total.toStringAsFixed(0)} MXN',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/checkout'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('REALIZAR PEDIDO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/tracking', extra: {
                  'restaurantName': 'McDonalds',
                  'address': 'Tu dirección',
                  'total': 0.0,
                  'orderId': 'o1',
                }),
                icon: const Icon(Icons.delivery_dining, size: 20),
                label: const Text('RASTREAR MI PEDIDO', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppConstants.primaryColor),
                  foregroundColor: AppConstants.primaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
