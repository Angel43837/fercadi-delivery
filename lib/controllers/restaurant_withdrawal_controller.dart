import 'package:flutter/foundation.dart';
import '../models/rider_balance.dart';
import '../models/restaurant_withdrawal.dart';
import '../services/restaurant_withdrawal_service.dart';

/// Mismo patrón que RiderWithdrawalController (ChangeNotifier via provider).
class RestaurantWithdrawalController extends ChangeNotifier {
  final RestaurantWithdrawalService _service;
  RestaurantWithdrawalController([RestaurantWithdrawalService? service]) : _service = service ?? RestaurantWithdrawalService();

  RiderBalance balance = RiderBalance.zero;
  List<RestaurantWithdrawal> history = [];
  bool loading = false;
  String? error;

  String connectStatus = 'not_started';
  Map<String, dynamic>? connectDebugInfo;
  bool connectLoading = false;
  String? _restaurantId;

  Future<void> load(String restaurantId) async {
    _restaurantId = restaurantId;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([_service.fetchBalance(), _service.fetchHistory(restaurantId)]);
      balance = results[0] as RiderBalance;
      history = results[1] as List<RestaurantWithdrawal>;
    } catch (e) {
      error = 'No se pudo cargar tu saldo. Revisa tu conexión.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadConnectStatus() async {
    connectLoading = true;
    notifyListeners();
    try {
      final result = await _service.fetchConnectStatus();
      connectStatus = result.status;
      connectDebugInfo = result.debugInfo;
    } catch (_) {
    } finally {
      connectLoading = false;
      notifyListeners();
    }
  }

  Future<String?> startConnectOnboarding() async {
    error = null;
    connectLoading = true;
    notifyListeners();
    try {
      return await _service.startConnectOnboarding();
    } catch (e) {
      // Se muestra el error real (no un mensaje genérico) — necesario para
      // diagnosticar la primera vez que alguien registra su cuenta: puede
      // ser desde "Stripe Connect no está activado" hasta un error real de
      // validación de Stripe, y un mensaje genérico escondería cuál es.
      error = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      connectLoading = false;
      notifyListeners();
    }
  }

  Future<bool> submitWithdrawal(double amount) async {
    error = null;
    notifyListeners();
    try {
      await _service.requestWithdrawal(amount, balance);
      if (_restaurantId != null) await load(_restaurantId!);
      return true;
    } on RestaurantWithdrawalException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      error = 'No se pudo procesar el retiro. Intenta de nuevo.';
      notifyListeners();
      return false;
    }
  }
}
