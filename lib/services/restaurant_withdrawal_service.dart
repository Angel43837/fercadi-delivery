import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider_balance.dart';
import '../models/restaurant_withdrawal.dart';
import '../repositories/restaurant_withdrawal_repository.dart';

enum RestaurantWithdrawalErrorCode {
  montoInvalido,
  montoMinimo,
  retiroEnCurso,
  saldoInsuficiente,
  noAutenticado,
  desconocido,
}

class RestaurantWithdrawalException implements Exception {
  final RestaurantWithdrawalErrorCode code;
  final String message;
  const RestaurantWithdrawalException(this.code, this.message);

  @override
  String toString() => message;
}

/// Reglas de negocio sobre el repositorio — mismo patrón que
/// RiderWithdrawalService, para el retiro de un restaurante.
class RestaurantWithdrawalService {
  final RestaurantWithdrawalRepository _repo;
  RestaurantWithdrawalService([RestaurantWithdrawalRepository? repo]) : _repo = repo ?? RestaurantWithdrawalRepository();

  static const double minimoRetiro = 200;

  Future<RiderBalance> fetchBalance() => _repo.fetchBalance();

  Future<List<RestaurantWithdrawal>> fetchHistory(String restaurantId) => _repo.fetchMyWithdrawals(restaurantId);

  Future<({String status, Map<String, dynamic>? debugInfo})> fetchConnectStatus() => _repo.fetchConnectStatus();

  Future<String> startConnectOnboarding() => _repo.startConnectOnboarding();

  Future<RestaurantWithdrawal> requestWithdrawal(double amount, RiderBalance balance) async {
    if (amount <= 0) {
      throw const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.montoInvalido, 'Ingresa un monto válido.');
    }
    if (amount < minimoRetiro) {
      throw RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.montoMinimo,
          'El monto mínimo de retiro es \$${minimoRetiro.toStringAsFixed(0)} MXN.');
    }
    if (amount > balance.saldoDisponible) {
      throw const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.saldoInsuficiente, 'No tienes suficiente saldo disponible.');
    }
    try {
      return await _repo.requestWithdrawal(amount);
    } on PostgrestException catch (e) {
      throw _translate(e.message);
    }
  }

  RestaurantWithdrawalException _translate(String raw) {
    switch (raw) {
      case 'monto_invalido':
        return const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.montoInvalido, 'Ingresa un monto válido.');
      case 'monto_minimo':
        return RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.montoMinimo,
            'El monto mínimo de retiro es \$${minimoRetiro.toStringAsFixed(0)} MXN.');
      case 'retiro_en_curso':
        return const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.retiroEnCurso, 'Ya tienes un retiro en curso. Espera a que se procese.');
      case 'saldo_insuficiente':
        return const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.saldoInsuficiente, 'No tienes suficiente saldo disponible.');
      case 'no_autenticado':
        return const RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.noAutenticado, 'Tu sesión expiró. Vuelve a iniciar sesión.');
      default:
        return RestaurantWithdrawalException(RestaurantWithdrawalErrorCode.desconocido, 'No se pudo procesar el retiro: $raw');
    }
  }
}
