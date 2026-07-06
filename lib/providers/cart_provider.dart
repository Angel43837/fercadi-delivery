import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  final Map<String, String> _restaurantNames = {}; // restaurantId → name

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (sum, item) => sum + item.quantity);
  double get total => _items.fold(0.0, (sum, item) => sum + item.total);

  // Backwards-compat: first restaurant id/name, or null when cart is empty
  String? get restaurantId => _restaurantNames.keys.firstOrNull;
  String? get restaurantName => _restaurantNames.values.firstOrNull;

  Map<String, List<CartItem>> get itemsByRestaurant {
    final Map<String, List<CartItem>> grouped = {};
    for (final item in _items) {
      grouped.putIfAbsent(item.restaurantId, () => []).add(item);
    }
    return grouped;
  }

  void addProduct(Product product, String restaurantId, String restaurantName) {
    _restaurantNames[restaurantId] = restaurantName;

    final existing = _items.where(
      (i) => i.product.id == product.id && i.restaurantId == restaurantId,
    );
    if (existing.isNotEmpty) {
      existing.first.quantity++;
    } else {
      _items.add(CartItem(
        product: product,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
      ));
    }
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    final activeIds = _items.map((i) => i.restaurantId).toSet();
    _restaurantNames.removeWhere((id, _) => !activeIds.contains(id));
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final matches = _items.where((i) => i.product.id == productId);
    if (matches.isEmpty) return;
    matches.first.quantity = quantity;
    notifyListeners();
  }

  void updateNotes(String productId, String notes) {
    final matches = _items.where((i) => i.product.id == productId);
    if (matches.isEmpty) return;
    matches.first.notes = notes;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _restaurantNames.clear();
    notifyListeners();
  }
}
