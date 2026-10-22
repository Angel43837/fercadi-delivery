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

  // 'not_started' | 'pending' | 'completed' — cuenta de Stripe Connect para
  // que el retiro se pague de verdad (ver rider-stripe-connect).
  String connectStatus = 'not_started';
  Map<String, dynamic>? connectDebugInfo;
  // Antes un error aquí se tragaba en silencio — connectStatus se quedaba
  // en 'not_started' sin ninguna pista de qué pasó, ni siquiera cuando SÍ
  // existía una cuenta de Stripe creada (mismo bug encontrado del lado de
  // restaurantes: el query 'include[]' que Stripe rechaza).
  String? connectStatusError;
  bool connectLoading = false;

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

  Future<void> loadConnectStatus() async {
    connectLoading = true;
    connectStatusError = null;
    notifyListeners();
    try {
      final result = await _service.fetchConnectStatus();
      connectStatus = result.status;
      connectDebugInfo = result.debugInfo;
    } catch (e) {
      connectStatusError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      connectLoading = false;
      notifyListeners();
    }
  }

  /// Regresa la URL de registro de Stripe para abrirla en el navegador, o
  /// null si falló (el mensaje queda en [error]).
  Future<String?> startConnectOnboarding() async {
    error = null;
    try {
      return await _service.startConnectOnboarding();
    } catch (e) {
      error = 'No se pudo abrir el registro de Stripe. Intenta de nuevo.';
      notifyListeners();
      return null;
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
