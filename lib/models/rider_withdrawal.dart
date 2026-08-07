class RiderWithdrawal {
  final String id;
  final String riderId;
  final double amount;
  final String status;
  final DateTime createdAt;
  final DateTime? processedAt;
  final DateTime? completedAt;
  final String? rejectionReason;
  final String? transactionReference;
  final String? stripePayoutId;
  final String? stripePayoutStatus;
  final String? adminNotes;

  const RiderWithdrawal({
    required this.id,
    required this.riderId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.processedAt,
    this.completedAt,
    this.rejectionReason,
    this.transactionReference,
    this.stripePayoutId,
    this.stripePayoutStatus,
    this.adminNotes,
  });

  factory RiderWithdrawal.fromJson(Map<String, dynamic> json) => RiderWithdrawal(
        id: json['id'] as String,
        riderId: json['rider_id'] as String,
        amount: (json['amount'] as num).toDouble(),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at'] as String).toLocal() : null,
        completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String).toLocal() : null,
        rejectionReason: json['rejection_reason'] as String?,
        transactionReference: json['transaction_reference'] as String?,
        stripePayoutId: json['stripe_payout_id'] as String?,
        stripePayoutStatus: json['stripe_payout_status'] as String?,
        adminNotes: json['admin_notes'] as String?,
      );
}
