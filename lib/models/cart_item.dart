import 'product.dart';

class CartItem {
  final Product product;
  final String restaurantId;
  final String restaurantName;
  int quantity;
  String notes;

  CartItem({
    required this.product,
    required this.restaurantId,
    required this.restaurantName,
    this.quantity = 1,
    this.notes = '',
  });

  double get total => product.price * quantity;
}
