// promotion.dart
// Definición de una promoción real (reclamable, con reglas, validada en el
// servidor) — no confundir con AppPromo (banner del carrusel "Promos",
// puramente visual). Ver supabase/migrations/20260901010000_promotions.sql.

enum PromotionType { twoForOne, percent, fixedAmount, freeShipping, freeProduct, unknown }

PromotionType _typeFromString(String? s) {
  switch (s) {
    case '2x1': return PromotionType.twoForOne;
    case 'percent': return PromotionType.percent;
    case 'fixed_amount': return PromotionType.fixedAmount;
    case 'free_shipping': return PromotionType.freeShipping;
    case 'free_product': return PromotionType.freeProduct;
    // Un tipo desconocido (ej. una versión vieja de la app frente a un tipo
    // nuevo agregado después) no debe tronar — solo no se sabrá aplicar.
    default: return PromotionType.unknown;
  }
}

class Promotion {
  final String id;
  final PromotionType type;
  final String title;
  final String description;
  final String? imageUrl;
  final String benefitLabel;
  final String? code;
  final String terms;
  final String? restaurantId; // null = de toda la plataforma
  final List<String>? applicableProductIds;
  final List<String>? applicableCategoryIds;
  final String? freeProductId;
  final double minPurchaseAmount;
  final double? maxDiscountAmount;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String? timeWindowStart; // 'HH:MM:SS'
  final String? timeWindowEnd;
  final List<int>? daysOfWeek; // 1=lunes..7=domingo
  final int? maxTotalUses;
  final int maxUsesPerUser;
  final int? maxClaims;
  final bool combinable;
  final bool appliesToShipping;
  final Map<String, dynamic> rules;
  final bool isActive;
  final DateTime createdAt;

  const Promotion({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.benefitLabel,
    this.code,
    required this.terms,
    this.restaurantId,
    this.applicableProductIds,
    this.applicableCategoryIds,
    this.freeProductId,
    required this.minPurchaseAmount,
    this.maxDiscountAmount,
    this.startsAt,
    this.expiresAt,
    this.timeWindowStart,
    this.timeWindowEnd,
    this.daysOfWeek,
    this.maxTotalUses,
    required this.maxUsesPerUser,
    this.maxClaims,
    required this.combinable,
    required this.appliesToShipping,
    required this.rules,
    required this.isActive,
    required this.createdAt,
  });

  bool get isPlatformWide => restaurantId == null;

  bool get isUpcoming => isActive && startsAt != null && startsAt!.isAfter(DateTime.now());

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isCurrentlyClaimable =>
      isActive && !isUpcoming && !isExpired;

  factory Promotion.fromMap(Map<String, dynamic> m) => Promotion(
    id: m['id'] as String,
    type: _typeFromString(m['type'] as String?),
    title: m['title'] as String? ?? '',
    description: m['description'] as String? ?? '',
    imageUrl: m['image_url'] as String?,
    benefitLabel: m['benefit_label'] as String? ?? '',
    code: m['code'] as String?,
    terms: m['terms'] as String? ?? '',
    restaurantId: m['restaurant_id'] as String?,
    applicableProductIds: (m['applicable_product_ids'] as List?)?.cast<String>(),
    applicableCategoryIds: (m['applicable_category_ids'] as List?)?.cast<String>(),
    freeProductId: m['free_product_id'] as String?,
    minPurchaseAmount: (m['min_purchase_amount'] as num?)?.toDouble() ?? 0,
    maxDiscountAmount: (m['max_discount_amount'] as num?)?.toDouble(),
    startsAt: m['starts_at'] != null ? DateTime.tryParse(m['starts_at'] as String) : null,
    expiresAt: m['expires_at'] != null ? DateTime.tryParse(m['expires_at'] as String) : null,
    timeWindowStart: m['time_window_start'] as String?,
    timeWindowEnd: m['time_window_end'] as String?,
    daysOfWeek: (m['days_of_week'] as List?)?.cast<int>(),
    maxTotalUses: m['max_total_uses'] as int?,
    maxUsesPerUser: (m['max_uses_per_user'] as int?) ?? 1,
    maxClaims: m['max_claims'] as int?,
    combinable: m['combinable'] as bool? ?? false,
    appliesToShipping: m['applies_to_shipping'] as bool? ?? false,
    rules: (m['rules'] as Map?)?.cast<String, dynamic>() ?? const {},
    isActive: m['is_active'] as bool? ?? true,
    createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  // Texto corto para condiciones, ej. "Lun a Vie, 1:00 PM - 6:00 PM · Compra mínima $100"
  String get conditionsSummary {
    final parts = <String>[];
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      const names = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      parts.add(daysOfWeek!.map((d) => names[d]).join(', '));
    }
    if (timeWindowStart != null && timeWindowEnd != null) {
      parts.add('${timeWindowStart!.substring(0, 5)} - ${timeWindowEnd!.substring(0, 5)}');
    }
    if (minPurchaseAmount > 0) {
      parts.add('Compra mínima \$${minPurchaseAmount.toStringAsFixed(0)} MXN');
    }
    if (!combinable) parts.add('No combinable con otras promociones');
    return parts.join(' · ');
  }
}
