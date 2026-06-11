// cart_item.dart
// Representa un ítem dentro del carrito de compras.
// Agrupa un Product con la cantidad seleccionada por el usuario.
// El total se calcula automáticamente como precio × cantidad.

import 'product.dart';

class CartItem {
  final Product product;
  int quantity;  // Cantidad seleccionada (mínimo 1)

  CartItem({required this.product, this.quantity = 1});

  // Precio total de este ítem (precio unitario × cantidad)
  double get total => product.price * quantity;
}
