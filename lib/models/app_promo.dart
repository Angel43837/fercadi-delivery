// app_promo.dart
// Cupón/promo propio de la app GOGO Food (no de un restaurante en particular)
// — se muestra en la pestaña "Promos" de restaurants_screen.dart.
// Corresponde a la tabla "app_promos" en Supabase.

import 'package:flutter/material.dart';

class AppPromo {
  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final int sortOrder;
  final DateTime? expiresAt;
  // Si no es null, este banner enlaza a una promoción real (reclamable) —
  // ver promotion_detail_screen.dart. Si es null, el banner sigue siendo
  // puramente visual, como siempre.
  final String? linkedPromotionId;

  const AppPromo({
    required this.id,
    required this.imageUrl,
    this.title = '',
    this.subtitle = '',
    this.badge = '',
    this.badgeColor = const Color(0xFFE53935),
    this.sortOrder = 0,
    this.expiresAt,
    this.linkedPromotionId,
  });

  factory AppPromo.fromJson(Map<String, dynamic> json) {
    final hex = (json['badge_color_hex'] as String? ?? 'E53935').replaceAll('#', '');
    final colorInt = int.tryParse('FF$hex', radix: 16) ?? 0xFFE53935;
    return AppPromo(
      id: json['id'] as String,
      imageUrl: json['image_url'] as String,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      badge: json['badge'] as String? ?? '',
      badgeColor: Color(colorInt),
      sortOrder: json['sort_order'] as int? ?? 0,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String).toLocal()
          : null,
      linkedPromotionId: json['linked_promotion_id'] as String?,
    );
  }
}
