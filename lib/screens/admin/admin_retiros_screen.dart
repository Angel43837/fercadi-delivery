// Módulo "Retiros" del panel de Admin — solicitudes de retiro de saldo de
// repartidores independientes (repartidor_plus). Los repartidores de flota
// no aparecen aquí: a ellos les paga directo su jefe de flota.
import 'package:flutter/material.dart';
import '../../models/rider_withdrawal.dart';
import '../../models/withdrawal_status.dart';
import '../../repositories/rider_withdrawal_repository.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

enum _Orden { recientes, antiguas, mayor, menor }

class AdminRetirosScreen extends StatefulWidget {
  const AdminRetirosScreen({super.key});
  @override
  State<AdminRetirosScreen> createState() => _AdminRetirosScreenState();
}

class _AdminRetirosScreenState extends State<AdminRetirosScreen> {
  final _repo = RiderWithdrawalRepository();
  bool _tabEstadisticas = false;
  bool _loading = true;
  List<RiderWithdrawal> _all = [];

  final Map<String, Map<String, dynamic>?> _riderInfo = {};
  final Map<String, String> _zonas = {};

  String _search = '';
  String? _estado;
  String? _zonaFiltro;
  DateTimeRange? _rangoFechas;
  _Orden _orden = _Orden.recientes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await _repo.fetchAllForAdmin();
    final list = raw.map(RiderWithdrawal.fromJson).toList();
    if (mounted) setState(() { _all = list; _loading = false; });
    await _loadRiderInfo(list);
  }

  Future<void> _loadRiderInfo(List<RiderWithdrawal> list) async {
    final ids = list.map((w) => w.riderId).toSet();
    for (final id in ids) {
      if (_riderInfo.containsKey(id)) continue;
      final info = await SupabaseService.lookupAuthUser(id);
      _riderInfo[id] = info;
      final loc = await _repo.fetchLatestRiderLocation(id);
      if (loc != null) {
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final zona = LocationService.zonaFromCoords(lat, lng);
          _zonas[id] = LocationService.zonaLabel(zona);
        }
      }
      if (mounted) setState(() {});
    }
  }

  String _nameFor(String riderId) {
    final info = _riderInfo[riderId];
    final name = info?['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final email = info?['email'] as String?;
    if (email != null && email.isNotEmpty) return email;
    return 'Repartidor ${adminShortId(riderId)}';
  }

  List<String> get _zonaOptions => _zonas.values.toSet().toList()..sort();

  List<RiderWithdrawal> get _filtered {
    var list = _all.where((w) {
      if (_estado != null && w.status != _estado) return false;
      final zona = _zonas[w.riderId];
      if (_zonaFiltro != null && zona != _zonaFiltro) return false;
      if (_rangoFechas != null) {
        final d = w.createdAt;
        final start = DateTime(_rangoFechas!.start.year, _rangoFechas!.start.month, _rangoFechas!.start.day);
        final end = DateTime(_rangoFechas!.end.year, _rangoFechas!.end.month, _rangoFechas!.end.day, 23, 59, 59);
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        if (!_nameFor(w.riderId).toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    switch (_orden) {
      case _Orden.recientes: list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Orden.antiguas: list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _Orden.mayor: list.sort((a, b) => b.amount.compareTo(a.amount));
      case _Orden.menor: list.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return list;
  }

  Future<void> _transition(RiderWithdrawal w, String newStatus, {String? rejectionReason, String? transactionReference}) async {
    await _repo.transitionStatus(
      withdrawalId: w.id,
      newStatus: newStatus,
      rejectionReason: rejectionReason,
      transactionReference: transactionReference,
    );
    await _load();
  }

  Future<void> _promptTexto(RiderWithdrawal w, {required String titulo, required String hint, required String newStatus, bool esReferencia = false}) async {
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

  void _openDetail(RiderWithdrawal w) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RetiroDetailSheet(
        withdrawal: w,
        riderName: _nameFor(w.riderId),
        riderInfo: _riderInfo[w.riderId],
        repo: _repo,
        onApprove: () => _transition(w, WithdrawalStatus.enProceso),
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
        title: const Text('Retiros', style: TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tabEstadisticas = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !_tabEstadisticas ? AdminColors.accent : AdminColors.surface,
                    borderRadius: BorderRadius.circular(AdminRadii.chip),
                  ),
                  child: Text('Lista', textAlign: TextAlign.center,
                      style: TextStyle(color: !_tabEstadisticas ? Colors.white : AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tabEstadisticas = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tabEstadisticas ? AdminColors.accent : AdminColors.surface,
                    borderRadius: BorderRadius.circular(AdminRadii.chip),
                  ),
                  child: Text('Estadísticas', textAlign: TextAlign.center,
                      style: TextStyle(color: _tabEstadisticas ? Colors.white : AdminColors.textSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
              : _tabEstadisticas
                  ? _buildEstadisticas()
                  : _buildLista(),
        ),
      ]),
    );
  }

  Widget _buildEstadisticas() {
    final totalSolicitado = _all.fold<double>(0, (s, w) => s + w.amount);
    final totalPagado = _all.where((w) => w.status == WithdrawalStatus.completado).fold<double>(0, (s, w) => s + w.amount);
    final totalPendiente = _all.where((w) => WithdrawalStatus.abiertos.contains(w.status)).fold<double>(0, (s, w) => s + w.amount);
    final totalRechazado = _all.where((w) => w.status == WithdrawalStatus.rechazado).fold<double>(0, (s, w) => s + w.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            AdminStatCard(label: 'Total solicitado', value: '\$${totalSolicitado.toStringAsFixed(0)}', icon: Icons.request_page_outlined, color: AdminColors.accent),
            AdminStatCard(label: 'Total pagado', value: '\$${totalPagado.toStringAsFixed(0)}', icon: Icons.check_circle_outline, color: AdminColors.statusDelivered),
            AdminStatCard(label: 'Total pendiente', value: '\$${totalPendiente.toStringAsFixed(0)}', icon: Icons.hourglass_empty_rounded, color: AdminColors.statusPending),
            AdminStatCard(label: 'Total rechazado', value: '\$${totalRechazado.toStringAsFixed(0)}', icon: Icons.cancel_outlined, color: AdminColors.statusCancelled),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, color: AdminColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text('${_all.length} retiros en total', style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }

  Widget _buildLista() {
    final list = _filtered;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(color: AdminColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Buscar por repartidor',
            hintStyle: TextStyle(color: AdminColors.textFaint),
            prefixIcon: Icon(Icons.search, color: AdminColors.textFaint),
            filled: true,
            fillColor: AdminColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          AdminFilterChip(label: 'Todos', selected: _estado == null, onTap: () => setState(() => _estado = null)),
          const SizedBox(width: 8),
          ...[WithdrawalStatus.pendiente, WithdrawalStatus.enProceso, WithdrawalStatus.completado, WithdrawalStatus.rechazado, WithdrawalStatus.cancelado].map((s) {
            final (label, _) = WithdrawalStatus.styleFor(s);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AdminFilterChip(label: label, selected: _estado == s, onTap: () => setState(() => _estado = s)),
            );
          }),
        ]),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          AdminPill(child: DropdownButton<String?>(
            value: _zonaFiltro,
            underline: const SizedBox(),
            dropdownColor: AdminColors.surfaceElevated,
            hint: Text('Zona', style: TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
            style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              ..._zonaOptions.map((z) => DropdownMenuItem(value: z, child: Text(z))),
            ],
            onChanged: (v) => setState(() => _zonaFiltro = v),
          )),
          const SizedBox(width: 8),
          AdminPill(child: GestureDetector(
            onTap: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: _rangoFechas,
              );
              if (range != null) setState(() => _rangoFechas = range);
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.date_range, color: AdminColors.textSecondary, size: 16),
              const SizedBox(width: 6),
              Text(_rangoFechas == null ? 'Fecha' : '${_rangoFechas!.start.day}/${_rangoFechas!.start.month} - ${_rangoFechas!.end.day}/${_rangoFechas!.end.month}',
                  style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
              if (_rangoFechas != null)
                GestureDetector(
                  onTap: () => setState(() => _rangoFechas = null),
                  child: Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.close, color: AdminColors.textFaint, size: 14)),
                ),
            ]),
          )),
          const SizedBox(width: 8),
          AdminPill(child: DropdownButton<_Orden>(
            value: _orden,
            underline: const SizedBox(),
            dropdownColor: AdminColors.surfaceElevated,
            style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13),
            items: const [
              DropdownMenuItem(value: _Orden.recientes, child: Text('Más recientes')),
              DropdownMenuItem(value: _Orden.antiguas, child: Text('Más antiguas')),
              DropdownMenuItem(value: _Orden.mayor, child: Text('Mayor monto')),
              DropdownMenuItem(value: _Orden.menor, child: Text('Menor monto')),
            ],
            onChanged: (v) => setState(() => _orden = v ?? _Orden.recientes),
          )),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text('Sin retiros con estos filtros', style: TextStyle(color: AdminColors.textFaint)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: list.length,
                itemBuilder: (_, i) => _buildCard(list[i]),
              ),
      ),
    ]);
  }

  Widget _buildCard(RiderWithdrawal w) {
    final (label, color) = WithdrawalStatus.styleFor(w.status);
    final avatarUrl = _riderInfo[w.riderId]?['avatarUrl'] as String?;
    final zona = _zonas[w.riderId];
    final f = w.createdAt;
    final fecha = '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _openDetail(w),
        child: AdminSectionCard(
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AdminColors.surfaceElevated,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl == null || avatarUrl.isEmpty) ? Icon(Icons.person_outline, color: AdminColors.textFaint) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nameFor(w.riderId), style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                Row(children: [
                  if (zona != null) ...[
                    Icon(Icons.place_outlined, color: AdminColors.textFaint, size: 12),
                    const SizedBox(width: 2),
                    Text(zona, style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
                    const SizedBox(width: 8),
                  ],
                  Text(fecha, style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${w.amount.toStringAsFixed(0)}', style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _RetiroDetailSheet extends StatefulWidget {
  final RiderWithdrawal withdrawal;
  final String riderName;
  final Map<String, dynamic>? riderInfo;
  final RiderWithdrawalRepository repo;
  final VoidCallback onApprove, onReject, onCancel, onComplete;
  const _RetiroDetailSheet({
    required this.withdrawal,
    required this.riderName,
    required this.riderInfo,
    required this.repo,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
    required this.onComplete,
  });

  @override
  State<_RetiroDetailSheet> createState() => _RetiroDetailSheetState();
}

class _RetiroDetailSheetState extends State<_RetiroDetailSheet> {
  List<Map<String, dynamic>> _log = [];
  String? _clabe;

  @override
  void initState() {
    super.initState();
    widget.repo.fetchStatusLog(widget.withdrawal.id).then((l) {
      if (mounted) setState(() => _log = l);
    });
    // Se guarda específicamente para que Admin la vea al procesar el
    // retiro — antes nada la leía de vuelta, Admin tenía que pedírsela al
    // repartidor por fuera de la app.
    widget.repo.getClabe(widget.withdrawal.riderId).then((c) {
      if (mounted) setState(() => _clabe = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.withdrawal;
    final (label, color) = WithdrawalStatus.styleFor(w.status);
    final info = widget.riderInfo;
    final email = info?['email'] as String?;
    final provider = info?['provider'] as String? ?? 'email';
    final banned = info?['banned'] == true;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(color: AdminColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.riderName, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
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
              title: 'Cuenta del repartidor',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(provider == 'google' ? Icons.g_mobiledata : Icons.person_outline, color: AdminColors.textSecondary, size: 18),
                  const SizedBox(width: 6),
                  Text(provider == 'google' ? 'Inició con Google' : 'Cuenta propia de la app', style: TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
                ]),
                const SizedBox(height: 6),
                Text('Correo: ${email ?? '—'}', style: TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Estado de cuenta: ${banned ? 'Suspendida' : 'Activa'}',
                    style: TextStyle(color: banned ? AdminColors.statusCancelled : AdminColors.statusDelivered, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('CLABE: ', style: TextStyle(color: AdminColors.textSecondary, fontSize: 13)),
                  Expanded(
                    child: SelectableText(
                      _clabe ?? 'No registrada',
                      style: TextStyle(
                        color: _clabe != null ? AdminColors.textPrimary : AdminColors.textSecondary,
                        fontSize: 13,
                        fontWeight: _clabe != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
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
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              AdminSectionCard(
                title: 'Historial',
                child: Column(children: _log.map((l) {
                  final created = DateTime.tryParse(l['created_at'] as String? ?? '');
                  final fecha = created == null ? '' : '${created.day}/${created.month} ${created.hour}:${created.minute.toString().padLeft(2, '0')}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('$fecha — ${l['admin_email']} → ${l['action']}', style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
                  );
                }).toList()),
              ),
            ],
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
          AdminPrimaryButton(label: 'Aprobar (pasar a en proceso)', onPressed: () => run(widget.onApprove)),
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

  Widget _actionButton(String label, Color color, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(side: BorderSide(color: color)),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
      );
}
