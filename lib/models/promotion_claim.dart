// promotion_claim.dart
// Una promoción reclamada por un usuario. La misma fila sirve para "Mis
// promociones" y como historial de uso — no hay tabla aparte para eso.

import 'promotion.dart';

enum ClaimBucket { disponible, proximamente, expirada, utilizada }

class PromotionClaim {
  final String id;
  final String promotionId;
  final String userId;
  final String? restaurantId;
  final String status; // available | used | revoked
  final DateTime claimedAt;
  final DateTime? usedAt;
  final String? orderId;
  final String? restaurantIdAtUse;
  final double? discountAmount;
  final Promotion? promotion; // viene de un select con join

  const PromotionClaim({
    required this.id,
    required this.promotionId,
    required this.userId,
    this.restaurantId,
    required this.status,
    required this.claimedAt,
    this.usedAt,
    this.orderId,
    this.restaurantIdAtUse,
    this.discountAmount,
    this.promotion,
  });

  // Se calcula siempre al leer — nunca se guarda un "expirada"/"próximamente"
  // en la base de datos, así no hace falta ningún proceso que las actualice.
  ClaimBucket get bucket {
    if (status == 'used') return ClaimBucket.utilizada;
    if (status == 'revoked') return ClaimBucket.expirada;
    final p = promotion;
    if (p == null) return ClaimBucket.disponible;
    if (p.isExpired) return ClaimBucket.expirada;
    if (p.isUpcoming) return ClaimBucket.proximamente;
    return ClaimBucket.disponible;
  }

  factory PromotionClaim.fromMap(Map<String, dynamic> m) => PromotionClaim(
    id: m['id'] as String,
    promotionId: m['promotion_id'] as String,
    userId: m['user_id'] as String,
    restaurantId: m['restaurant_id'] as String?,
    status: m['status'] as String? ?? 'available',
    claimedAt: DateTime.tryParse(m['claimed_at'] as String? ?? '') ?? DateTime.now(),
    usedAt: m['used_at'] != null ? DateTime.tryParse(m['used_at'] as String) : null,
    orderId: m['order_id'] as String?,
    restaurantIdAtUse: m['restaurant_id_at_use'] as String?,
    discountAmount: (m['discount_amount'] as num?)?.toDouble(),
    promotion: m['promotion'] != null
        ? Promotion.fromMap((m['promotion'] as Map).cast<String, dynamic>())
        : null,
  );
}
