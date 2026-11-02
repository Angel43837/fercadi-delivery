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

  // Precio unitario que de verdad se cobra: el de la promo por platillo si
  // sigue vigente (el mismo que se muestra tachado en la lista). Mismo
  // cálculo que place_order() en el servidor, que es quien decide el monto.
  double get unitPrice => product.promoPrice;

  // Con 2x1 vigente se paga la mitad redondeada hacia arriba.
  int get paidQuantity =>
      product.isPromoActive && product.promoIs2x1 ? quantity - quantity ~/ 2 : quantity;

  double get total => unitPrice * paidQuantity;
}
