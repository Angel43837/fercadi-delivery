import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/promotion_claim.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  final Map<String, String> _restaurantNames = {}; // restaurantId → name

  // Promoción elegida para el checkout actual. _promoValidation es la
  // respuesta cruda de validate_promotion_for_order (el servidor) — el
  // descuento que se muestra y se cobra SIEMPRE sale de aquí, nunca de un
  // cálculo hecho en esta clase.
  PromotionClaim? _selectedPromoClaim;
  Map<String, dynamic>? _promoValidation;

  PromotionClaim? get selectedPromoClaim => _selectedPromoClaim;
  Map<String, dynamic>? get promoValidation => _promoValidation;
  double get promoDiscount =>
      (_promoValidation?['discount_amount'] as num?)?.toDouble() ?? 0;
  bool get promoAppliesToShipping => _promoValidation?['applies_to_shipping'] == true;
  bool get hasValidPromo => _promoValidation?['valid'] == true;

  void selectPromo(PromotionClaim claim) {
    _selectedPromoClaim = claim;
    _promoValidation = null;
    notifyListeners();
  }

  void setPromoValidation(Map<String, dynamic> result) {
    _promoValidation = result;
    notifyListeners();
  }

  void clearPromo() {
    _selectedPromoClaim = null;
    _promoValidation = null;
    notifyListeners();
  }

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
    // El carrito cambió — el descuento ya validado podía depender de qué
    // había antes (compra mínima, cantidades del 2x1, etc.), así que se
    // limpia y hay que volver a validar antes de mostrarlo de nuevo. No se
    // quita la promoción elegida en sí, solo el resultado ya calculado.
    _promoValidation = null;
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    final activeIds = _items.map((i) => i.restaurantId).toSet();
    _restaurantNames.removeWhere((id, _) => !activeIds.contains(id));
    _promoValidation = null;
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
    _promoValidation = null;
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
    _selectedPromoClaim = null;
    _promoValidation = null;
    notifyListeners();
  }
}
