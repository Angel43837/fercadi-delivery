// cart_provider.dart
// Maneja el estado del carrito de compras usando Provider (ChangeNotifier).
// Solo permite ítems de UN restaurante a la vez — si el usuario agrega de otro,
// el carrito se limpia automáticamente para evitar pedidos de múltiples lugares.
// Se accede desde cualquier pantalla con: context.read<CartProvider>()

import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _restaurantId;    // ID del restaurante del carrito actual
  String? _restaurantName;  // Nombre del restaurante (para mostrarlo en el carrito)

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);
  double get total => _items.fold(0.0, (sum, item) => sum + item.total);
  String? get restaurantId => _restaurantId;
  String? get restaurantName => _restaurantName;

  // Agrega un producto al carrito. Si es de otro restaurante, limpia primero el carrito.
  void addProduct(Product product, String restaurantId, String restaurantName) {
    if (_restaurantId != null && _restaurantId != restaurantId) {
      _items.clear();
    }
    _restaurantId = restaurantId;
    _restaurantName = restaurantName;

    final existing = _items.where((i) => i.product.id == product.id);
    if (existing.isNotEmpty) {
      existing.first.quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    if (_items.isEmpty) _restaurantId = null;
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final item = _items.firstWhere((i) => i.product.id == productId);
    item.quantity = quantity;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _restaurantId = null;
    _restaurantName = null;
    notifyListeners();
  }
}
