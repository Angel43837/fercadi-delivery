class RiderBalance {
  final double totalGanado;
  final double totalRetirado;
  final double totalReservado;
  final double saldoDisponible;

  const RiderBalance({
    required this.totalGanado,
    required this.totalRetirado,
    required this.totalReservado,
    required this.saldoDisponible,
  });

  static const zero = RiderBalance(totalGanado: 0, totalRetirado: 0, totalReservado: 0, saldoDisponible: 0);

  factory RiderBalance.fromJson(Map<String, dynamic> json) => RiderBalance(
        totalGanado: (json['total_ganado'] as num?)?.toDouble() ?? 0,
        totalRetirado: (json['total_retirado'] as num?)?.toDouble() ?? 0,
        totalReservado: (json['total_reservado'] as num?)?.toDouble() ?? 0,
        saldoDisponible: (json['saldo_disponible'] as num?)?.toDouble() ?? 0,
      );
}
