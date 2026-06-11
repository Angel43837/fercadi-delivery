// cart_screen.dart
// Pantalla del carrito de compras del cliente.
// Muestra los ítems agregados, sus cantidades y el total.
// Permite modificar cantidades o eliminar productos.
// El botón "Pedir" lleva a la pantalla de checkout para confirmar el pedido.

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg  = isDark ? AppConstants.surfaceColor : Colors.white;
    final cardText = isDark ? Colors.white : Colors.black87;
    final cardSub  = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Carrito', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 80,
                      color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('Tu carrito está vacío',
                      style: TextStyle(fontSize: 18,
                          color: Colors.white.withValues(alpha: 0.7))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/restaurants'),
                    child: const Text('Ver restaurantes',
                        style: TextStyle(color: AppConstants.primaryColor)),
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
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 60, height: 60,
                                color: isDark ? AppConstants.surface2Color : Colors.grey.shade100,
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
                                      style: TextStyle(fontWeight: FontWeight.bold, color: cardText, fontSize: 15)),
                                  Text('\$${item.product.price.toStringAsFixed(0)} c/u',
                                      style: TextStyle(color: cardSub, fontSize: 13)),
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
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cardText)),
                                ),
                                _SmallButton(
                                  icon: Icons.add, primary: true,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: primary
              ? AppConstants.primaryColor
              : (isDark ? AppConstants.surface2Color : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16,
            color: primary ? Colors.white : (isDark ? Colors.white : Colors.black87)),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final CartProvider cart;
  const _OrderSummary({required this.cart});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppConstants.surfaceColor : AppConstants.primaryColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${cart.count} producto${cart.count != 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                Text('\$${cart.total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/checkout'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.white,
                  foregroundColor: AppConstants.primaryColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('REALIZAR PEDIDO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
