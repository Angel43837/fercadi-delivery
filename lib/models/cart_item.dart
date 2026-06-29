// cart_item.dart
// Representa un ítem dentro del carrito de compras.
// Agrupa un Product con la cantidad seleccionada por el usuario.
// El total se calcula automáticamente como precio × cantidad.

import 'product.dart';

class CartItem {
  final Product product;
  int quantity;
  String notes;

  CartItem({required this.product, this.quantity = 1, this.notes = ''});

  double get total => product.price * quantity;
}
