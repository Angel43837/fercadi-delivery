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

  // product.promoPrice (no product.price): si el producto tiene un
  // descuento activo (promo_discount_percent + promo_expires_at vigente),
  // antes se mostraba la insignia de descuento pero se cobraba el precio
  // completo igual — el carrito nunca aplicaba el precio con descuento en
  // ningún lado.
  double get total => product.promoPrice * quantity;
}
