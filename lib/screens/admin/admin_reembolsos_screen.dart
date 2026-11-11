// Módulo "Reembolsos" del panel de Admin — solicitudes de reembolso de
// pedidos normales (order_refund_requests). No confundir con el reembolso
// de la función "Pedir un repartidor" (rider_calls), que tiene su propia
// lógica de auto-reembolso aparte.
import 'package:flutter/material.dart';
import 'package:gogo_core/services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

class AdminReembolsosScreen extends StatefulWidget {
  const AdminReembolsosScreen({super.key});
  @override
  State<AdminReembolsosScreen> createState() => _AdminReembolsosScreenState();
}

class _AdminReembolsosScreenState extends State<AdminReembolsosScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _all = [];
  String? _estado = 'pendiente';

  final Map<String, Map<String, dynamic>?> _orderInfo = {};
  final Map<String, Map<String, dynamic>?> _customerInfo = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SupabaseService.getAllRefundRequests();
    if (mounted) setState(() { _all = list; _loading = false; });
    for (final r in list) {
      final orderId = r['order_id'] as String;
      final requestedBy = r['requested_by'] as String?;
      if (!_orderInfo.containsKey(orderId)) {
        final order = await SupabaseService.getOrderById(orderId);
        _orderInfo[orderId] = order;
        if (mounted) setState(() {});
      }
      if (requestedBy != null && !_customerInfo.containsKey(requestedBy)) {
        final info = await SupabaseService.lookupAuthUser(requestedBy);
        _customerInfo[requestedBy] = info;
        if (mounted) setState(() {});
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_estado == null) return _all;
    return _all.where((r) => r['status'] == _estado).toList();
  }

  (String, Color) _styleFor(String status) => switch (status) {
        'procesado'  => ('Reembolsado', AdminColors.statusDelivered),
        'rechazado'  => ('Rechazado',   AdminColors.statusCancelled),
        'aprobado'   => ('Aprobado',    AdminColors.accent),
        _            => ('Pendiente',   AdminColors.statusPending),
      };

  Future<void> _resolve(Map<String, dynamic> r, String action) async {
    String? adminNotes;
    if (action == 'reject') {
      final ctrl = TextEditingController();
      adminNotes = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rechazar reembolso', style: TextStyle(color: AdminColors.textPrimary)),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            style: const TextStyle(color: AdminColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Motivo del rechazo (el cliente no lo ve directo, es para tu registro)',
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
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.statusCancelled),
              child: const Text('Rechazar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (adminNotes == null) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('¿Aprobar y reembolsar?', style: TextStyle(color: AdminColors.textPrimary)),
          content: Text('Esto cobra el reembolso real por Stripe de inmediato, no se puede deshacer.',
              style: TextStyle(color: AdminColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar', style: TextStyle(color: AdminColors.textSecondary))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AdminColors.accent),
              child: const Text('Sí, reembolsar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AdminColors.accent)),
    );
    try {
      await SupabaseService.processOrderRefund(
        r['id'] as String,
        action: action,
        adminNotes: adminNotes,
      );
      if (mounted) Navigator.pop(context); // cierra el loading
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'approve' ? 'Reembolso procesado por Stripe.' : 'Solicitud rechazada.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // cierra el loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AdminColors.statusCancelled,
          duration: const Duration(seconds: 6),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: const Text('Reembolsos', style: TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
          : Column(children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  AdminFilterChip(label: 'Todos', selected: _estado == null, onTap: () => setState(() => _estado = null)),
                  const SizedBox(width: 8),
                  ...['pendiente', 'aprobado', 'rechazado', 'procesado'].map((s) {
                    final (label, _) = _styleFor(s);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AdminFilterChip(label: label, selected: _estado == s, onTap: () => setState(() => _estado = s)),
                    );
                  }),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text('Sin solicitudes con este filtro', style: TextStyle(color: AdminColors.textFaint)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _buildCard(list[i]),
                      ),
              ),
            ]),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final status = r['status'] as String;
    final (label, color) = _styleFor(status);
    final order = _orderInfo[r['order_id'] as String];
    final customer = _customerInfo[r['requested_by'] as String?];
    final restaurantName = (order?['restaurants'] as Map<String, dynamic>?)?['name'] as String? ?? 'Pedido ${(r['order_id'] as String).substring(0, 6)}';
    final total = (order?['total'] as num?)?.toDouble();
    final customerName = customer?['name'] as String? ?? customer?['email'] as String? ?? 'Cliente';
    final created = DateTime.tryParse(r['created_at'] as String? ?? '');
    final fecha = created == null ? '' : '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AdminSectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(restaurantName, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('$customerName · $fecha', style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
              ]),
            ),
            if (total != null)
              Text('\$${total.toStringAsFixed(0)}', style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
            child: Text(r['reason'] as String? ?? '', style: TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
          ),
          if (r['admin_notes'] != null && (r['admin_notes'] as String).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Nota: ${r['admin_notes']}', style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
          ],
          if (status == 'pendiente') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _resolve(r, 'reject'),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AdminColors.statusCancelled)),
                  child: const Text('Rechazar', style: TextStyle(color: AdminColors.statusCancelled, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _resolve(r, 'approve'),
                  style: ElevatedButton.styleFrom(backgroundColor: AdminColors.accent, foregroundColor: Colors.white),
                  child: const Text('Aprobar y reembolsar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
