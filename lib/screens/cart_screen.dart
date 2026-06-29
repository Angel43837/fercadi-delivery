// cart_screen.dart
// Pantalla del carrito de compras del cliente.
// Muestra los ítems agregados, sus cantidades y el total.
// Permite modificar cantidades o eliminar productos.
// El botón "Pedir" lleva a la pantalla de checkout para confirmar el pedido.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/cart_item.dart';
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
                      return _CartItemTile(item: item, isDark: isDark, cardBg: cardBg, cardText: cardText, cardSub: cardSub);
                    },
                  ),
                ),
                _OrderSummary(cart: cart),
              ],
            ),
    );
  }
}

class _CartItemTile extends StatefulWidget {
  final CartItem item;
  final bool isDark;
  final Color cardBg;
  final Color cardText;
  final Color cardSub;
  const _CartItemTile({required this.item, required this.isDark, required this.cardBg, required this.cardText, required this.cardSub});

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  bool _expanded = false;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppConstants.primaryColor;
    final item = widget.item;
    final isDark = widget.isDark;
    final cardBg = widget.cardBg;
    final cardText = widget.cardText;
    final cardSub = widget.cardSub;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // fila principal
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // imagen izquierda
                  SizedBox(
                    width: 90,
                    child: item.product.imageUrl != null && item.product.imageUrl!.isNotEmpty
                        ? Image.network(item.product.imageUrl!, fit: BoxFit.cover,
                            width: 90, height: 80,
                            errorBuilder: (_, _, _) => Container(
                              color: isDark ? AppConstants.surface2Color : Colors.grey.shade200,
                              child: const Icon(Icons.fastfood, color: accent),
                            ))
                        : Container(
                            color: isDark ? AppConstants.surface2Color : Colors.grey.shade200,
                            child: const Icon(Icons.fastfood, color: accent),
                          ),
                  ),
                  // info centro
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item.product.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.bold, color: cardText, fontSize: 14)),
                          if (item.product.description != null && item.product.description!.isNotEmpty)
                            Text(item.product.description!,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cardSub, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('\$${(item.product.price * item.quantity).toStringAsFixed(0)} MXN',
                              style: const TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  // selector cantidad
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _QtyButton(
                          icon: Icons.remove,
                          onTap: () => context.read<CartProvider>()
                              .updateQuantity(item.product.id, item.quantity - 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('${item.quantity}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cardText)),
                        ),
                        _QtyButton(
                          icon: Icons.add, primary: true,
                          onTap: () => context.read<CartProvider>()
                              .updateQuantity(item.product.id, item.quantity + 1),
                        ),
                      ],
                    ),
                  ),
                  // flecha expandir naranja
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      width: 72,
                      color: accent,
                      child: Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.white, size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // sección expandida — instrucciones especiales
            if (_expanded)
              Container(
                color: isDark ? AppConstants.surface2Color : const Color(0xFFF5F5F5),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: cardText),
                  decoration: InputDecoration(
                    hintText: 'Indicaciones especiales (ej: sin cebolla, sin jitomate...)',
                    hintStyle: TextStyle(color: cardSub, fontSize: 12),
                    filled: true,
                    fillColor: isDark ? AppConstants.surfaceColor : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                  onChanged: (val) => context.read<CartProvider>().updateNotes(item.product.id, val),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _QtyButton({required this.icon, required this.onTap, this.primary = false});

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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      color: AppConstants.primaryColor,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${cart.count} producto${cart.count != 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
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
                  backgroundColor: const Color(0xFF0C98F5),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: const Color(0xFF0C98F5).withValues(alpha: 0.5),
                  shape: const StadiumBorder(),
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
