import 'package:flutter/material.dart';

class RestaurantBanner {
  final String id;
  final String restaurantId;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final String? productId;
  final int? discountPercent;
  final DateTime? expiresAt;
  final int sortOrder;

  const RestaurantBanner({
    required this.id,
    required this.restaurantId,
    required this.imageUrl,
    this.title = '',
    this.subtitle = '',
    this.badge = '',
    this.badgeColor = const Color(0xFFE53935),
    this.productId,
    this.discountPercent,
    this.expiresAt,
    this.sortOrder = 0,
  });

  bool get isDiscountActive =>
      discountPercent != null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory RestaurantBanner.fromJson(Map<String, dynamic> json) {
    final hex = (json['badge_color_hex'] as String? ?? 'E53935').replaceAll('#', '');
    final colorInt = int.tryParse('FF$hex', radix: 16) ?? 0xFFE53935;
    return RestaurantBanner(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      imageUrl: json['image_url'] as String,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      badge: json['badge'] as String? ?? '',
      badgeColor: Color(colorInt),
      productId: json['product_id'] as String?,
      discountPercent: json['discount_percent'] as int?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String).toLocal()
          : null,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'restaurant_id': restaurantId,
        'image_url': imageUrl,
        'title': title,
        'subtitle': subtitle,
        'badge': badge,
        'badge_color_hex': '#${badgeColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        'product_id': productId,
        'discount_percent': discountPercent,
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'sort_order': sortOrder,
        'is_active': true,
      };
}
