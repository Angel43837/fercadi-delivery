// Única capa que habla directo con Supabase para el módulo de retiros de
// restaurante. Mismo patrón que rider_withdrawal_repository.dart.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider_balance.dart';
import '../models/restaurant_withdrawal.dart';

class RestaurantWithdrawalRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<RiderBalance> fetchBalance([String? restaurantId]) async {
    final data = await _client.rpc('get_restaurant_balance',
        params: restaurantId != null ? {'p_restaurant_id': restaurantId} : {}) as List;
    if (data.isEmpty) return RiderBalance.zero;
    return RiderBalance.fromJson(data.first as Map<String, dynamic>);
  }

  Future<List<RestaurantWithdrawal>> fetchMyWithdrawals(String restaurantId) async {
    final data = await _client
        .from('restaurant_withdrawals')
        .select()
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => RestaurantWithdrawal.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RestaurantWithdrawal> requestWithdrawal(double amount) async {
    final data = await _client.rpc('request_restaurant_withdrawal', params: {'p_amount': amount});
    return RestaurantWithdrawal.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> fetchAllForAdmin() async {
    final data = await _client.from('restaurant_withdrawals').select().order('created_at', ascending: false).limit(500);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> transitionStatus({
    required String withdrawalId,
    required String newStatus,
    String? rejectionReason,
    String? transactionReference,
  }) async {
    await _client.rpc('admin_transition_restaurant_withdrawal', params: {
      'p_withdrawal_id': withdrawalId,
      'p_new_status': newStatus,
      'p_rejection_reason': rejectionReason,
      'p_transaction_reference': transactionReference,
    });
  }

  // ── Stripe Connect (pago real del retiro) ──────────────────────────────────
  // Mismo motivo que en rider_withdrawal_repository.dart: functions.invoke()
  // lanza FunctionException (no regresa el body) en cualquier respuesta fuera
  // de 2xx — las Edge Functions regresan su error real en el campo 'error'.

  String _functionErrorMessage(Object e) {
    if (e is FunctionException) {
      final details = e.details;
      if (details is Map && details['error'] != null) return details['error'].toString();
      return e.reasonPhrase ?? 'Error de Stripe';
    }
    return e.toString();
  }

  Future<({String status, Map<String, dynamic>? debugInfo})> fetchConnectStatus() async {
    try {
      final res = await _client.functions.invoke('restaurant-stripe-connect', body: {'action': 'status'});
      final data = res.data as Map<String, dynamic>;
      return (
        status: data['status'] as String? ?? 'not_started',
        debugInfo: data['debugInfo'] as Map<String, dynamic>?,
      );
    } catch (e) {
      throw Exception(_functionErrorMessage(e));
    }
  }

  Future<String> startConnectOnboarding() async {
    try {
      final res = await _client.functions.invoke('restaurant-stripe-connect', body: {'action': 'onboard'});
      final data = res.data as Map<String, dynamic>;
      return data['url'] as String;
    } catch (e) {
      throw Exception(_functionErrorMessage(e));
    }
  }

  // Admin: aprueba el retiro y, si el restaurante ya terminó su registro con
  // Stripe, transfiere el dinero de verdad.
  Future<void> approveAndTransfer(String withdrawalId) async {
    try {
      await _client.functions.invoke('restaurant-withdrawal-transfer', body: {'withdrawalId': withdrawalId});
    } catch (e) {
      throw Exception(_functionErrorMessage(e));
    }
  }
}
