// Única capa que habla directo con Supabase para el módulo de retiros.
// Los servicios/controllers de arriba nunca llaman a Supabase directamente.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider_balance.dart';
import '../models/rider_withdrawal.dart';

class RiderWithdrawalRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<RiderBalance> fetchBalance([String? riderId]) async {
    final data = await _client.rpc('get_rider_balance', params: riderId != null ? {'p_rider_id': riderId} : {}) as List;
    if (data.isEmpty) return RiderBalance.zero;
    return RiderBalance.fromJson(data.first as Map<String, dynamic>);
  }

  Future<List<RiderWithdrawal>> fetchMyWithdrawals() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await _client
        .from('rider_withdrawals')
        .select()
        .eq('rider_id', uid)
        .order('created_at', ascending: false);
    return (data as List).map((e) => RiderWithdrawal.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RiderWithdrawal> requestWithdrawal(double amount) async {
    final data = await _client.rpc('request_withdrawal', params: {'p_amount': amount});
    return RiderWithdrawal.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> fetchAllForAdmin() async {
    final data = await _client.from('rider_withdrawals').select().order('created_at', ascending: false).limit(500);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> transitionStatus({
    required String withdrawalId,
    required String newStatus,
    String? rejectionReason,
    String? transactionReference,
    String? adminNotes,
  }) async {
    await _client.rpc('admin_transition_withdrawal', params: {
      'p_withdrawal_id': withdrawalId,
      'p_new_status': newStatus,
      'p_rejection_reason': rejectionReason,
      'p_transaction_reference': transactionReference,
      'p_admin_notes': adminNotes,
    });
  }

  Future<List<Map<String, dynamic>>> fetchStatusLog(String withdrawalId) async {
    final data = await _client
        .from('withdrawal_status_log')
        .select()
        .eq('withdrawal_id', withdrawalId)
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> fetchLatestRiderLocation(String riderId) async {
    try {
      final data = await _client.from('rider_locations').select('lat, lng').eq('rider_id', riderId).maybeSingle();
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveClabe(String riderId, String clabe) async {
    await _client.from('rider_payout_accounts').upsert({'rider_id': riderId, 'clabe': clabe});
  }

  // Admin necesita ver la CLABE para transferirle el dinero al repartidor
  // al completar un retiro — se guardaba con ese propósito (saveClabe) pero
  // nada la leía de vuelta en ningún lado.
  Future<String?> getClabe(String riderId) async {
    try {
      final data = await _client
          .from('rider_payout_accounts')
          .select('clabe')
          .eq('rider_id', riderId)
          .maybeSingle();
      return data?['clabe'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Stripe Connect (pago real del retiro) ──────────────────────────────────
  // functions.invoke() lanza FunctionException (no regresa el body) en
  // cualquier respuesta fuera de 2xx — las 3 Edge Functions de abajo
  // regresan su mensaje de error real en el campo 'error' de ese body.

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
      final res = await _client.functions.invoke('rider-stripe-connect', body: {'action': 'status'});
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
      final res = await _client.functions.invoke('rider-stripe-connect', body: {'action': 'onboard'});
      final data = res.data as Map<String, dynamic>;
      return data['url'] as String;
    } catch (e) {
      throw Exception(_functionErrorMessage(e));
    }
  }

  // Admin: aprueba el retiro y, si el repartidor ya terminó su registro con
  // Stripe, transfiere el dinero de verdad (ver rider-withdrawal-transfer).
  Future<void> approveAndTransfer(String withdrawalId) async {
    try {
      await _client.functions.invoke('rider-withdrawal-transfer', body: {'withdrawalId': withdrawalId});
    } catch (e) {
      throw Exception(_functionErrorMessage(e));
    }
  }
}
