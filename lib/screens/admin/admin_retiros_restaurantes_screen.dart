// Módulo "Retiros de restaurantes" del panel de Admin — mismo patrón que
// admin_retiros_screen.dart (repartidores), pero para que un restaurante
// pueda cobrar su parte de las ventas. Antes de esto no existía ninguna
// forma de que un restaurante pidiera su dinero desde la app.
import 'package:flutter/material.dart';
import '../../models/restaurant_withdrawal.dart';
import '../../models/withdrawal_status.dart';
import '../../repositories/restaurant_withdrawal_repository.dart';
import '../../services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

class AdminRetirosRestaurantesScreen extends StatefulWidget {
  const AdminRetirosRestaurantesScreen({super.key});
  @override
  State<AdminRetirosRestaurantesScreen> createState() => _AdminRetirosRestaurantesScreenState();
}

class _AdminRetirosRestaurantesScreenState extends State<AdminRetirosRestaurantesScreen> {
  final _repo = RestaurantWithdrawalRepository();
  bool _loading = true;
  List<RestaurantWithdrawal> _all = [];
  final Map<String, String> _restaurantNames = {};
  String? _estado;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await _repo.fetchAllForAdmin();
    final list = raw.map(RestaurantWithdrawal.fromJson).toList();
    if (mounted) setState(() { _all = list; _loading = false; });
    for (final id in list.map((w) => w.restaurantId).toSet()) {
      if (_restaurantNames.containsKey(id)) continue;
      final r = await SupabaseService.getRestaurantById(id);
      if (mounted) setState(() => _restaurantNames[id] = r?.name ?? 'Restaurante $id');
    }
  }

  String _nameFor(String restaurantId) => _restaurantNames[restaurantId] ?? 'Restaurante $restaurantId';

  List<RestaurantWithdrawal> get _filtered {
    final list = _estado == null ? _all : _all.where((w) => w.status == _estado).toList();
    return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _transition(RestaurantWithdrawal w, String newStatus, {String? rejectionReason, String? transactionReference}) async {
    await _repo.transitionStatus(
      withdrawalId: w.id,
      newStatus: newStatus,
      rejectionReason: rejectionReason,
      transactionReference: transactionReference,
    );
    await _load();
  }

  // Mismo criterio que admin_retiros_screen.dart: "Aprobar" ya no solo
  // cambia el estatus — intenta pagar de verdad por Stripe Connect.
  Future<void> _approveWithTransfer(RestaurantWithdrawal w) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AdminColors.accent)),
    );
    String? errorMsg;
    try {
      await _repo.approveAndTransfer(w.id);
    } catch (e) {
      errorMsg = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) Navigator.pop(context);
    await _load();
    if (errorMsg != null && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          title: const Text('No se pudo pagar por Stripe', style: TextStyle(color: AdminColors.textPrimary)),
          content: Text(errorMsg!, style: TextStyle(color: AdminColors.textSecondary)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
    }
  }

  Future<void> _promptTexto(RestaurantWithdrawal w, {required String titulo, required String hint, required String newStatus, bool esReferencia = false}) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(titulo, style: const TextStyle(color: AdminColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          maxLines: esReferencia ? 1 : 3,
          style: const TextStyle(color: AdminColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AdminColors.textFaint),
            filled: true,
            fillColor: AdminColors.surfaceElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: AdminColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.accent),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value.isEmpty) return;
    await _transition(w, newStatus, rejectionReason: esReferencia ? null : value, transactionReference: esReferencia ? value : null);
  }

  void _openDetail(RestaurantWithdrawal w) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RetiroDetailSheet(
        withdrawal: w,
        restaurantName: _nameFor(w.restaurantId),
        onApprove: () => _approveWithTransfer(w),
        onReject: () => _promptTexto(w, titulo: 'Rechazar retiro', hint: 'Motivo del rechazo', newStatus: WithdrawalStatus.rechazado),
        onCancel: () => _transition(w, WithdrawalStatus.cancelado),
        onComplete: () => _promptTexto(w, titulo: 'Marcar como completado', hint: 'Referencia de la transacción', newStatus: WithdrawalStatus.completado, esReferencia: true),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: const Text('Retiros de restaurantes', style: TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _estadoChip(null, 'Todos'),
                    ...[WithdrawalStatus.pendiente, WithdrawalStatus.enProceso, WithdrawalStatus.completado, WithdrawalStatus.rechazado, WithdrawalStatus.cancelado].map((s) {
                      final (label, _) = WithdrawalStatus.styleFor(s);
                      return _estadoChip(s, label);
                    }),
                  ]),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(child: Text('Sin retiros de restaurantes todavía', style: TextStyle(color: AdminColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final w = _filtered[i];
                          final (label, color) = WithdrawalStatus.styleFor(w.status);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () => _openDetail(w),
                              child: AdminSectionCard(
                                child: Row(children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                                    child: Icon(Icons.storefront_rounded, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(_nameFor(w.restaurantId),
                                        style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text('\$${w.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
                                      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ]),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }

  Widget _estadoChip(String? value, String label) {
    final selected = _estado == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _estado = value),
        selectedColor: AdminColors.accent,
        backgroundColor: AdminColors.surface,
        labelStyle: TextStyle(color: selected ? Colors.white : AdminColors.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _RetiroDetailSheet extends StatefulWidget {
  final RestaurantWithdrawal withdrawal;
  final String restaurantName;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onComplete;
  const _RetiroDetailSheet({
    required this.withdrawal,
    required this.restaurantName,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
    required this.onComplete,
  });

  @override
  State<_RetiroDetailSheet> createState() => _RetiroDetailSheetState();
}

class _RetiroDetailSheetState extends State<_RetiroDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final w = widget.withdrawal;
    final (label, color) = WithdrawalStatus.styleFor(w.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(color: AdminColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.restaurantName, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Row(children: [
              Text('\$${w.amount.toStringAsFixed(0)} MXN', style: const TextStyle(color: AdminColors.accent, fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            AdminSectionCard(
              title: 'Detalle del retiro',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailRow('Solicitado', _fmt(w.createdAt)),
                if (w.processedAt != null) _detailRow('En proceso desde', _fmt(w.processedAt!)),
                if (w.completedAt != null) _detailRow('Finalizado', _fmt(w.completedAt!)),
                if (w.transactionReference != null && w.transactionReference!.isNotEmpty) _detailRow('Referencia', w.transactionReference!),
                if (w.rejectionReason != null && w.rejectionReason!.isNotEmpty) _detailRow('Motivo de rechazo', w.rejectionReason!),
              ]),
            ),
            const SizedBox(height: 20),
            ..._buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AdminColors.textFaint, fontSize: 12))),
          Text(value, style: TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
        ]),
      );

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<Widget> _buildActions(BuildContext context) {
    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    switch (widget.withdrawal.status) {
      case WithdrawalStatus.pendiente:
        return [
          AdminPrimaryButton(label: 'Aprobar y pagar por Stripe', onPressed: () => run(widget.onApprove)),
          const SizedBox(height: 10),
          _actionButton('Rechazar', AdminColors.statusCancelled, () => run(widget.onReject)),
          const SizedBox(height: 10),
          _actionButton('Cancelar', AdminColors.textFaint, () => run(widget.onCancel)),
        ];
      case WithdrawalStatus.enProceso:
        return [
          AdminPrimaryButton(label: 'Marcar como completado', onPressed: () => run(widget.onComplete)),
          const SizedBox(height: 10),
          _actionButton('Rechazar', AdminColors.statusCancelled, () => run(widget.onReject)),
          const SizedBox(height: 10),
          _actionButton('Cancelar', AdminColors.textFaint, () => run(widget.onCancel)),
        ];
      default:
        return [];
    }
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.5))),
        child: Text(label),
      ),
    );
  }
}
