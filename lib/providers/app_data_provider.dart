// app_data_provider.dart
// Provider global que maneja datos compartidos entre pantallas:
//   - Likes de restaurantes y platillos (en tiempo real con Supabase Realtime)
//   - Estado abierto/cerrado de restaurantes
//   - Disponibilidad de productos (el dueño puede activar/desactivar)
//   - Productos extra agregados por el dueño
//   - Lista de pedidos (pedidos mock para la vista de administrador/dueño)
//
// Se accede desde cualquier pantalla con: context.read<AppDataProvider>()
// Los likes usan "optimistic update" — se actualiza la UI antes de confirmar con la BD.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';

// Estados posibles de un pedido en la app
enum AppOrderStatus { pendiente, enCamino, entregado, cancelado }

({Color color, String label}) appOrderStatusStyle(AppOrderStatus s) => switch (s) {
  AppOrderStatus.pendiente => (color: const Color(0xFFFFB300), label: 'Pendiente'),
  AppOrderStatus.enCamino  => (color: const Color(0xFFE91E8C), label: 'En camino'),
  AppOrderStatus.entregado => (color: Colors.green,            label: 'Entregado'),
  AppOrderStatus.cancelado => (color: Colors.red,              label: 'Cancelado'),
};

class SharedProduct {
  final String id;
  String name;
  String description;
  double price;
  bool isAvailable;
  final List<String> categoryIds;
  final String restaurantId;
  String? imagePath;

  SharedProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    required this.categoryIds,
    required this.restaurantId,
    this.imagePath,
  });
}

class AppDataProvider extends ChangeNotifier {
  // ── Likes de restaurantes (realtime Supabase) ────────────────────────────────
  final Map<String, int> _likes = {};
  final Set<String> _likedByUser = {};
  RealtimeChannel? _restaurantLikesChannel;

  int getLikes(String restaurantId) => _likes[restaurantId] ?? 0;
  bool isLikedByUser(String restaurantId) => _likedByUser.contains(restaurantId);

  Future<void> initRestaurantLikes() async {
    try {
      final counts = await SupabaseService.getRestaurantLikeCounts();
      final liked  = await SupabaseService.getUserLikedRestaurants(_userId);
      _likes
        ..clear()
        ..addAll(counts);
      _likedByUser
        ..clear()
        ..addAll(liked);
      notifyListeners();
      _restaurantLikesChannel?.unsubscribe();
      _restaurantLikesChannel = SupabaseService.subscribeToRestaurantLikes(_refreshRestaurantLikes);
    } catch (_) {}
  }

  Future<void> _refreshRestaurantLikes() async {
    try {
      final counts = await SupabaseService.getRestaurantLikeCounts();
      final liked  = await SupabaseService.getUserLikedRestaurants(_userId);
      _likes
        ..clear()
        ..addAll(counts);
      _likedByUser
        ..clear()
        ..addAll(liked);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleLike(String restaurantId) async {
    final wasLiked = _likedByUser.contains(restaurantId);
    if (wasLiked) {
      _likedByUser.remove(restaurantId);
      _likes[restaurantId] = ((_likes[restaurantId] ?? 1) - 1).clamp(0, 9999);
    } else {
      _likedByUser.add(restaurantId);
      _likes[restaurantId] = (_likes[restaurantId] ?? 0) + 1;
    }
    notifyListeners();
    await SupabaseService.toggleRestaurantLike(restaurantId, _userId);
  }

  // ── Likes de platillos (realtime Supabase) ───────────────────────────────────
  final Map<String, int> _productLikes      = {};
  final Set<String>      _productLikedByUser = {};
  RealtimeChannel?       _likesChannel;
  // UID de Supabase (no email — una cuenta de solo-teléfono no tiene).
  String                 _userId = '';

  int  getProductLikes(String productId)    => _productLikes[productId] ?? 0;
  bool isProductLikedByUser(String productId) => _productLikedByUser.contains(productId);

  Future<void> initProductLikes() async {
    try {
      final session = await AuthService.getSession();
      _userId = session?.uid ?? '';

      // Todas las queries en paralelo
      final results = await Future.wait([
        SupabaseService.getProductLikeCounts(),
        SupabaseService.getUserLikedProducts(_userId),
        SupabaseService.getRestaurantLikeCounts(),
        SupabaseService.getUserLikedRestaurants(_userId),
      ]);

      _productLikes..clear()..addAll(results[0] as Map<String, int>);
      _productLikedByUser..clear()..addAll(results[1] as Set<String>);
      _likes..clear()..addAll(results[2] as Map<String, int>);
      _likedByUser..clear()..addAll(results[3] as Set<String>);
      notifyListeners();

      _likesChannel?.unsubscribe();
      _likesChannel = SupabaseService.subscribeToProductLikes(_refreshLikes);
      _restaurantLikesChannel?.unsubscribe();
      _restaurantLikesChannel = SupabaseService.subscribeToRestaurantLikes(_refreshRestaurantLikes);
    } catch (_) {}
  }

  Future<void> _refreshLikes() async {
    try {
      final counts = await SupabaseService.getProductLikeCounts();
      final liked  = await SupabaseService.getUserLikedProducts(_userId);
      _productLikes
        ..clear()
        ..addAll(counts);
      _productLikedByUser
        ..clear()
        ..addAll(liked);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleProductLike(String productId) async {
    // Optimistic update
    final wasLiked = _productLikedByUser.contains(productId);
    if (wasLiked) {
      _productLikedByUser.remove(productId);
      _productLikes[productId] = ((_productLikes[productId] ?? 1) - 1).clamp(0, 9999);
    } else {
      _productLikedByUser.add(productId);
      _productLikes[productId] = (_productLikes[productId] ?? 0) + 1;
    }
    notifyListeners();

    // Persistir en Supabase (el realtime actualizará todos los dispositivos)
    await SupabaseService.toggleProductLike(productId, _userId);
  }

  @override
  void dispose() {
    _likesChannel?.unsubscribe();
    _restaurantLikesChannel?.unsubscribe();
    super.dispose();
  }

  // ── isOpen ───────────────────────────────────────────────────────────────────
  final Map<String, bool> _isOpen = {'1': true, '2': true, '3': false};

  bool isRestaurantOpen(String restaurantId) => _isOpen[restaurantId] ?? true;

  Future<void> setRestaurantOpen(String restaurantId, bool open) async {
    _isOpen[restaurantId] = open;
    notifyListeners();
    try {
      await SupabaseService.setRestaurantOpen(restaurantId, open);
    } catch (_) {}
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
              p.restaurantId == restaurantId && p.categoryIds.contains(categoryId))
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

}
