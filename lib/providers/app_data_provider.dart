import 'package:flutter/material.dart';

enum AppOrderStatus { pendiente, enCamino, entregado, cancelado }

({Color color, String label}) appOrderStatusStyle(AppOrderStatus s) => switch (s) {
  AppOrderStatus.pendiente => (color: const Color(0xFFFFB300), label: 'Pendiente'),
  AppOrderStatus.enCamino  => (color: const Color(0xFFE91E8C), label: 'En camino'),
  AppOrderStatus.entregado => (color: Colors.green,            label: 'Entregado'),
  AppOrderStatus.cancelado => (color: Colors.red,              label: 'Cancelado'),
};

class AppOrder {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantIcon;
  final String customer;
  final double total;
  AppOrderStatus status;
  final String time;
  final List<String> items;
  final int itemsCount;

  AppOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantIcon,
    required this.customer,
    required this.total,
    required this.status,
    required this.time,
    required this.items,
    required this.itemsCount,
  });
}

class SharedProduct {
  final String id;
  String name;
  String description;
  double price;
  bool isAvailable;
  final String categoryId;
  final String restaurantId;
  String? imagePath;

  SharedProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    required this.categoryId,
    required this.restaurantId,
    this.imagePath,
  });
}

class AppDataProvider extends ChangeNotifier {
  // ── Likes ────────────────────────────────────────────────────────────────────
  final Map<String, int> _likes = {'1': 90, '2': 96, '3': 84};
  final Set<String> _likedByUser = {};

  int getLikes(String restaurantId) => _likes[restaurantId] ?? 0;
  bool isLikedByUser(String restaurantId) => _likedByUser.contains(restaurantId);

  void toggleLike(String restaurantId) {
    if (_likedByUser.contains(restaurantId)) {
      _likedByUser.remove(restaurantId);
      _likes[restaurantId] = (_likes[restaurantId] ?? 0) - 1;
    } else {
      _likedByUser.add(restaurantId);
      _likes[restaurantId] = (_likes[restaurantId] ?? 0) + 1;
    }
    notifyListeners();
  }

  // ── isOpen ───────────────────────────────────────────────────────────────────
  final Map<String, bool> _isOpen = {'1': true, '2': true, '3': false};

  bool isRestaurantOpen(String restaurantId) => _isOpen[restaurantId] ?? true;

  void setRestaurantOpen(String restaurantId, bool open) {
    _isOpen[restaurantId] = open;
    notifyListeners();
  }

  // ── Disponibilidad de productos ──────────────────────────────────────────────
  final Map<String, bool> _productAvailability = {};

  bool getProductAvailability(String productId, bool defaultValue) =>
      _productAvailability.containsKey(productId)
          ? _productAvailability[productId]!
          : defaultValue;

  void setProductAvailability(String productId, bool available) {
    _productAvailability[productId] = available;
    notifyListeners();
  }

  // ── Productos extra (agregados por el dueño) ─────────────────────────────────
  final List<SharedProduct> _extraProducts = [];

  List<SharedProduct> extraProductsForCategory(
          String restaurantId, String categoryId) =>
      _extraProducts
          .where((p) =>
              p.restaurantId == restaurantId && p.categoryId == categoryId)
          .toList();

  List<SharedProduct> extraProductsForRestaurant(String restaurantId) =>
      _extraProducts.where((p) => p.restaurantId == restaurantId).toList();

  void addExtraProduct(SharedProduct product) {
    _extraProducts.add(product);
    notifyListeners();
  }

  void updateExtraProduct(SharedProduct updated) {
    final idx = _extraProducts.indexWhere((p) => p.id == updated.id);
    if (idx != -1) {
      _extraProducts[idx] = updated;
      notifyListeners();
    }
  }

  // ── Pedidos compartidos ──────────────────────────────────────────────────────
  final List<AppOrder> _orders = [
    AppOrder(id: '001', restaurantId: '1', restaurantName: 'McDonalds',  restaurantIcon: '🍔', customer: 'Carlos Pérez',   total: 258, status: AppOrderStatus.pendiente,  time: 'hace 2 min',  items: ['Big Mac x2', 'Papas Grandes', 'Coca-Cola'],  itemsCount: 3),
    AppOrder(id: '002', restaurantId: '2', restaurantName: 'Starbucks',  restaurantIcon: '☕', customer: 'María López',    total: 170, status: AppOrderStatus.entregado, time: 'hace 12 min', items: ['Café Latte', 'Croissant'],                    itemsCount: 2),
    AppOrder(id: '003', restaurantId: '3', restaurantName: 'Sushi Roll', restaurantIcon: '🍣', customer: 'Ana García',     total: 320, status: AppOrderStatus.pendiente, time: 'hace 1 min',  items: ['California Roll x2', 'Sopa Miso x2'],       itemsCount: 4),
    AppOrder(id: '004', restaurantId: '1', restaurantName: 'McDonalds',  restaurantIcon: '🍔', customer: 'Luis Martínez', total: 95,  status: AppOrderStatus.enCamino,  time: 'hace 10 min', items: ['Quarter Pounder'],                           itemsCount: 1),
    AppOrder(id: '005', restaurantId: '2', restaurantName: 'Starbucks',  restaurantIcon: '☕', customer: 'Rosa Flores',    total: 140, status: AppOrderStatus.cancelado, time: 'hace 35 min', items: ['Frappuccino x2'],                            itemsCount: 2),
    AppOrder(id: '006', restaurantId: '3', restaurantName: 'Sushi Roll', restaurantIcon: '🍣', customer: 'Jorge Ramírez', total: 265, status: AppOrderStatus.entregado, time: 'hace 41 min', items: ['Sashimi Mix', 'Edamame', 'Sopa Miso'],      itemsCount: 3),
    AppOrder(id: '007', restaurantId: '1', restaurantName: 'McDonalds',  restaurantIcon: '🍔', customer: 'Sofía Torres',  total: 189, status: AppOrderStatus.entregado, time: 'hace 55 min', items: ['Big Mac', 'McFlurry Oreo', 'Coca-Cola'],    itemsCount: 2),
  ];

  List<AppOrder> get allOrders => _orders;

  List<AppOrder> ordersForRestaurant(String restaurantId) =>
      _orders.where((o) => o.restaurantId == restaurantId).toList();

  void updateOrderStatus(String orderId, AppOrderStatus status) {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx != -1) {
      _orders[idx].status = status;
      notifyListeners();
    }
  }
}
