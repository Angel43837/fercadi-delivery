import 'package:flutter/foundation.dart';
import '../models/rider_balance.dart';
import '../models/rider_withdrawal.dart';
import '../services/rider_withdrawal_service.dart';

/// Mismo patrón que AppDataProvider (ChangeNotifier via provider). Se carga
/// perezoso: no consulta nada hasta que la pantalla de retiros llama load().
class RiderWithdrawalController extends ChangeNotifier {
  final RiderWithdrawalService _service;
  RiderWithdrawalController([RiderWithdrawalService? service]) : _service = service ?? RiderWithdrawalService();

  RiderBalance balance = RiderBalance.zero;
  List<RiderWithdrawal> history = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([_service.fetchBalance(), _service.fetchHistory()]);
      balance = results[0] as RiderBalance;
      history = results[1] as List<RiderWithdrawal>;
    } catch (e) {
      error = 'No se pudo cargar tu saldo. Revisa tu conexión.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> submitWithdrawal(double amount) async {
    error = null;
    notifyListeners();
    try {
      await _service.requestWithdrawal(amount, balance);
      await load();
      return true;
    } on WithdrawalException catch (e) {
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
