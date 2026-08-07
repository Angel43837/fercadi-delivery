import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider_balance.dart';
import '../models/rider_withdrawal.dart';
import '../repositories/rider_withdrawal_repository.dart';

enum WithdrawalErrorCode {
  montoInvalido,
  montoMinimo,
  riderDeFlota,
  retiroEnCurso,
  saldoInsuficiente,
  noAutenticado,
  desconocido,
}

class WithdrawalException implements Exception {
  final WithdrawalErrorCode code;
  final String message;
  const WithdrawalException(this.code, this.message);

  @override
  String toString() => message;
}

/// Reglas de negocio sobre el repositorio: valida rápido en el cliente antes
/// de pegarle a la red, y traduce errores de Postgres a mensajes en español.
class RiderWithdrawalService {
  final RiderWithdrawalRepository _repo;
  RiderWithdrawalService([RiderWithdrawalRepository? repo]) : _repo = repo ?? RiderWithdrawalRepository();

  static const double minimoRetiro = 200;

  Future<RiderBalance> fetchBalance() => _repo.fetchBalance();

  Future<List<RiderWithdrawal>> fetchHistory() => _repo.fetchMyWithdrawals();

  Future<RiderWithdrawal> requestWithdrawal(double amount, RiderBalance balance) async {
    if (amount <= 0) {
      throw const WithdrawalException(WithdrawalErrorCode.montoInvalido, 'Ingresa un monto válido.');
    }
    if (amount < minimoRetiro) {
      throw WithdrawalException(WithdrawalErrorCode.montoMinimo, 'El monto mínimo de retiro es \$${minimoRetiro.toStringAsFixed(0)} MXN.');
    }
    if (amount > balance.saldoDisponible) {
      throw const WithdrawalException(WithdrawalErrorCode.saldoInsuficiente, 'No tienes suficiente saldo disponible.');
    }
    try {
      return await _repo.requestWithdrawal(amount);
    } on PostgrestException catch (e) {
      throw _translate(e.message);
    }
  }

  WithdrawalException _translate(String raw) {
    switch (raw) {
      case 'monto_invalido':
        return const WithdrawalException(WithdrawalErrorCode.montoInvalido, 'Ingresa un monto válido.');
      case 'monto_minimo':
        return WithdrawalException(WithdrawalErrorCode.montoMinimo, 'El monto mínimo de retiro es \$${minimoRetiro.toStringAsFixed(0)} MXN.');
      case 'rider_de_flota':
        return const WithdrawalException(WithdrawalErrorCode.riderDeFlota, 'Los repartidores de flota reciben su pago directo de su jefe de flota.');
      case 'retiro_en_curso':
        return const WithdrawalException(WithdrawalErrorCode.retiroEnCurso, 'Ya tienes un retiro en curso. Espera a que se procese.');
      case 'saldo_insuficiente':
        return const WithdrawalException(WithdrawalErrorCode.saldoInsuficiente, 'No tienes suficiente saldo disponible.');
      case 'no_autenticado':
        return const WithdrawalException(WithdrawalErrorCode.noAutenticado, 'Tu sesión expiró. Vuelve a iniciar sesión.');
      default:
        return WithdrawalException(WithdrawalErrorCode.desconocido, 'No se pudo procesar el retiro: $raw');
    }
  }
}
