class Product {
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final List<String> images;
  final int? promoDiscountPercent;
  final bool promoIs2x1;
  final DateTime? promoExpiresAt;

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.isAvailable = true,
    this.images = const [],
    this.promoDiscountPercent,
    this.promoIs2x1 = false,
    this.promoExpiresAt,
  });

  bool get isPromoActive =>
      promoExpiresAt != null &&
      promoExpiresAt!.isAfter(DateTime.now()) &&
      (promoDiscountPercent != null || promoIs2x1);

  double get promoPrice {
    if (!isPromoActive || promoDiscountPercent == null) return price;
    return price * (1 - promoDiscountPercent! / 100);
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['image_url'] as String?,
        isAvailable: json['is_available'] as bool? ?? true,
        images: const [],
        promoDiscountPercent: json['promo_discount_percent'] as int?,
        promoIs2x1: json['promo_is_2x1'] as bool? ?? false,
        promoExpiresAt: json['promo_expires_at'] != null
            ? DateTime.parse(json['promo_expires_at'] as String).toLocal()
            : null,
      );
}
