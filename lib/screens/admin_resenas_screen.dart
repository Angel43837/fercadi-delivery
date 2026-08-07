// Módulo "Reseñas" del panel de Admin — moderación de las calificaciones
// cliente↔repartidor (tabla `ratings`). Es exclusivamente sobre los
// trabajadores (repartidores): no hay reseñas de platillos ni de
// restaurantes, eso es responsabilidad de cada restaurante, no de la
// plataforma.
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../theme/admin_theme.dart';
import '../theme/admin_widgets.dart';

enum _Tipo { todas, cliente, repartidor, reportadas }

enum _Orden { recientes, antiguas, mejor, peor }

class AdminResenasScreen extends StatefulWidget {
  const AdminResenasScreen({super.key});
  @override
  State<AdminResenasScreen> createState() => _AdminResenasScreenState();
}

class _AdminResenasScreenState extends State<AdminResenasScreen> {
  bool _tabEstadisticas = false;
  bool _loading = true;
  List<Map<String, dynamic>> _all = [];

  String _search = '';
  _Tipo _tipo = _Tipo.todas;
  int? _estrellas;
  _Orden _orden = _Orden.recientes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await SupabaseService.getAllRatingsForAdmin();
    if (mounted)
      setState(() {
        _all = data;
        _loading = false;
      });
  }

  // ── Helpers de datos ─────────────────────────────────────────────────────

  Map<String, dynamic>? _orderOf(Map<String, dynamic> r) =>
      r['orders'] as Map<String, dynamic>?;

  bool _esRepartidor(Map<String, dynamic> r) => r['is_driver'] == true;

  String _reviewerLabel(Map<String, dynamic> r) {
    if (_esRepartidor(r)) {
      final repId = _orderOf(r)?['repartidor_id'] as String?;
      return repId == null ? 'Repartidor' : 'Repartidor ${adminShortId(repId)}';
    }
    final order = _orderOf(r);
    try {
      final delivery =
          jsonDecode(order?['customer_name'] as String? ?? '{}')
              as Map<String, dynamic>;
      final name = delivery['name'] as String?;
      return (name == null || name.isEmpty) ? 'Cliente invitado' : name;
    } catch (_) {
      return 'Cliente invitado';
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _all.where((r) {
      switch (_tipo) {
        case _Tipo.cliente:
          if (_esRepartidor(r)) return false;
        case _Tipo.repartidor:
          if (!_esRepartidor(r)) return false;
        case _Tipo.reportadas:
          if (r['is_flagged'] != true) return false;
        case _Tipo.todas:
          break;
      }
      if (_estrellas != null && (r['stars'] as int? ?? 0) != _estrellas)
        return false;
      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        final hay = '${_reviewerLabel(r)} ${r['comment'] ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    int byDate(Map<String, dynamic> a, Map<String, dynamic> b) =>
        (a['created_at'] as String? ?? '').compareTo(
          b['created_at'] as String? ?? '',
        );
    switch (_orden) {
      case _Orden.recientes:
        list.sort((a, b) => byDate(b, a));
      case _Orden.antiguas:
        list.sort(byDate);
      case _Orden.mejor:
        list.sort(
          (a, b) =>
              (b['stars'] as int? ?? 0).compareTo(a['stars'] as int? ?? 0),
        );
      case _Orden.peor:
        list.sort(
          (a, b) =>
              (a['stars'] as int? ?? 0).compareTo(b['stars'] as int? ?? 0),
        );
    }
    return list;
  }

  // ── Moderación ───────────────────────────────────────────────────────────

  Future<void> _toggleHidden(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    final hidden = r['is_hidden'] == true;
    final email = (await AuthService.getSession())?.email ?? 'admin';
    await SupabaseService.setRatingModeration(id, isHidden: !hidden);
    await SupabaseService.logModerationAction(
      id,
      email,
      hidden ? 'unhide' : 'hide',
    );
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Eliminar reseña?',
          style: TextStyle(color: AdminColors.textPrimary),
        ),
        content: Text(
          'No se puede deshacer.',
          style: TextStyle(color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AdminColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AdminColors.statusCancelled),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = r['id'] as String;
    final email = (await AuthService.getSession())?.email ?? 'admin';
    await SupabaseService.logModerationAction(id, email, 'delete');
    await SupabaseService.deleteRating(id);
    await _load();
  }

  Future<void> _report(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    final flagged = r['is_flagged'] == true;
    if (flagged) {
      final email = (await AuthService.getSession())?.email ?? 'admin';
      await SupabaseService.setRatingModeration(id, isFlagged: false);
      await SupabaseService.logModerationAction(id, email, 'unflag');
      await _load();
      return;
    }
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Marcar como inapropiada',
          style: TextStyle(color: AdminColors.textPrimary),
        ),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          style: const TextStyle(color: AdminColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Motivo del reporte',
            hintStyle: TextStyle(color: AdminColors.textFaint),
            filled: true,
            fillColor: AdminColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AdminColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.accent,
            ),
            child: const Text(
              'Marcar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;
    final email = (await AuthService.getSession())?.email ?? 'admin';
    await SupabaseService.setRatingModeration(
      id,
      isFlagged: true,
      reportReason: reason.isEmpty ? 'Sin motivo especificado' : reason,
    );
    await SupabaseService.logModerationAction(id, email, 'flag', note: reason);
    await _load();
  }

  void _openDetail(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ResenaDetailSheet(
        rating: r,
        reviewerLabel: _reviewerLabel(r),
        isRepartidor: _esRepartidor(r),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: const Text(
          'Reseñas',
          style: TextStyle(
            color: AdminColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tabEstadisticas = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_tabEstadisticas
                            ? AdminColors.accent
                            : AdminColors.surface,
                        borderRadius: BorderRadius.circular(AdminRadii.chip),
                      ),
                      child: Text(
                        'Lista',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: !_tabEstadisticas
                              ? Colors.white
                              : AdminColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                        color: _tabEstadisticas
                            ? AdminColors.accent
                            : AdminColors.surface,
                        borderRadius: BorderRadius.circular(AdminRadii.chip),
                      ),
                      child: Text(
                        'Estadísticas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _tabEstadisticas
                              ? Colors.white
                              : AdminColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AdminColors.accent),
                  )
                : _tabEstadisticas
                ? _EstadisticasView(all: _all)
                : _buildLista(),
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: AdminColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar por usuario, restaurante o palabra clave',
              hintStyle: TextStyle(color: AdminColors.textFaint),
              prefixIcon: Icon(Icons.search, color: AdminColors.textFaint),
              filled: true,
              fillColor: AdminColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AdminFilterChip(
                label: 'Todas',
                selected: _tipo == _Tipo.todas,
                onTap: () => setState(() => _tipo = _Tipo.todas),
              ),
              const SizedBox(width: 8),
              AdminFilterChip(
                label: 'Cliente → Repartidor',
                selected: _tipo == _Tipo.cliente,
                onTap: () => setState(() => _tipo = _Tipo.cliente),
              ),
              const SizedBox(width: 8),
              AdminFilterChip(
                label: 'Repartidor → Cliente',
                selected: _tipo == _Tipo.repartidor,
                onTap: () => setState(() => _tipo = _Tipo.repartidor),
              ),
              const SizedBox(width: 8),
              AdminFilterChip(
                label: 'Reportadas',
                selected: _tipo == _Tipo.reportadas,
                onTap: () => setState(() => _tipo = _Tipo.reportadas),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _dropdownEstrellas(),
              const SizedBox(width: 8),
              _dropdownOrden(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Sin reseñas con estos filtros',
                    style: TextStyle(color: AdminColors.textFaint),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ResenaCard(
                    rating: list[i],
                    reviewerLabel: _reviewerLabel(list[i]),
                    onTap: () => _openDetail(list[i]),
                    onHide: () => _toggleHidden(list[i]),
                    onReport: () => _report(list[i]),
                    onDelete: () => _delete(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _dropdownEstrellas() => AdminPill(
    child: DropdownButton<int?>(
      value: _estrellas,
      underline: const SizedBox(),
      dropdownColor: AdminColors.surfaceElevated,
      hint: Text(
        'Estrellas',
        style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
      ),
      style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas')),
        ...List.generate(
          5,
          (i) => 5 - i,
        ).map((s) => DropdownMenuItem(value: s, child: Text('$s ★'))),
      ],
      onChanged: (v) => setState(() => _estrellas = v),
    ),
  );

  Widget _dropdownOrden() => AdminPill(
    child: DropdownButton<_Orden>(
      value: _orden,
      underline: const SizedBox(),
      dropdownColor: AdminColors.surfaceElevated,
      style: const TextStyle(color: AdminColors.textPrimary, fontSize: 13),
      items: const [
        DropdownMenuItem(value: _Orden.recientes, child: Text('Más recientes')),
        DropdownMenuItem(value: _Orden.antiguas, child: Text('Más antiguas')),
        DropdownMenuItem(value: _Orden.mejor, child: Text('Mejor calificadas')),
        DropdownMenuItem(value: _Orden.peor, child: Text('Peor calificadas')),
      ],
      onChanged: (v) => setState(() => _orden = v ?? _Orden.recientes),
    ),
  );
}

// ── Tarjeta de reseña ────────────────────────────────────────────────────────

class _ResenaCard extends StatelessWidget {
  final Map<String, dynamic> rating;
  final String reviewerLabel;
  final VoidCallback onTap, onHide, onReport, onDelete;
  const _ResenaCard({
    required this.rating,
    required this.reviewerLabel,
    required this.onTap,
    required this.onHide,
    required this.onReport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final stars = rating['stars'] as int? ?? 0;
    final comment = rating['comment'] as String?;
    final hidden = rating['is_hidden'] == true;
    final flagged = rating['is_flagged'] == true;
    final createdAt = DateTime.tryParse(rating['created_at'] as String? ?? '');
    final fecha = createdAt == null
        ? ''
        : '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AdminSectionCard(
          child: Opacity(
            opacity: hidden ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reviewerLabel,
                            style: const TextStyle(
                              color: AdminColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFFFB300),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                if (comment != null && comment.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    comment,
                    style: TextStyle(
                      color: AdminColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      fecha,
                      style: TextStyle(
                        color: AdminColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                    if (hidden) ...[
                      const SizedBox(width: 8),
                      _tag('Oculta', AdminColors.textFaint),
                    ],
                    if (flagged) ...[
                      const SizedBox(width: 8),
                      _tag('Reportada', AdminColors.statusCancelled),
                    ],
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AdminColors.textSecondary,
                        size: 18,
                      ),
                      tooltip: hidden ? 'Mostrar' : 'Ocultar',
                      onPressed: onHide,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.flag_outlined,
                        color: flagged
                            ? AdminColors.statusCancelled
                            : AdminColors.textSecondary,
                        size: 18,
                      ),
                      tooltip: flagged ? 'Quitar reporte' : 'Reportar',
                      onPressed: onReport,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AdminColors.statusCancelled,
                        size: 18,
                      ),
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

// ── Detalle de la reseña + perfil del usuario ────────────────────────────────

class _ResenaDetailSheet extends StatefulWidget {
  final Map<String, dynamic> rating;
  final String reviewerLabel;
  final bool isRepartidor;
  const _ResenaDetailSheet({
    required this.rating,
    required this.reviewerLabel,
    required this.isRepartidor,
  });

  @override
  State<_ResenaDetailSheet> createState() => _ResenaDetailSheetState();
}

class _ResenaDetailSheetState extends State<_ResenaDetailSheet> {
  Map<String, dynamic>? _authInfo;
  bool _loadingAuth = false;
  List<Map<String, dynamic>> _historial = [];
  List<Map<String, dynamic>> _log = [];
  int _totalResenas = 0;
  bool _busyBan = false;

  String? get _repartidorId =>
      (widget.rating['orders'] as Map<String, dynamic>?)?['repartidor_id']
          as String?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ratingId = widget.rating['id'] as String;
    final log = await SupabaseService.getModerationLogForRating(ratingId);
    if (mounted) setState(() => _log = log);

    if (widget.isRepartidor && _repartidorId != null) {
      setState(() => _loadingAuth = true);
      final results = await Future.wait([
        SupabaseService.lookupAuthUser(_repartidorId!),
        SupabaseService.getOrdersByRepartidor(_repartidorId!),
      ]);
      final orders = results[1] as List<Map<String, dynamic>>;
      final orderIds = orders.map((o) => o['id'] as String).toList();
      final allRatings = orderIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await SupabaseService.getRatingsForOrders(orderIds);
      if (mounted) {
        setState(() {
          _authInfo = results[0] as Map<String, dynamic>?;
          _historial = orders;
          _totalResenas = allRatings
              .where((r) => r['is_driver'] == false)
              .length;
          _loadingAuth = false;
        });
      }
    } else {
      final order = widget.rating['orders'] as Map<String, dynamic>?;
      String? phone;
      try {
        final delivery =
            jsonDecode(order?['customer_name'] as String? ?? '{}')
                as Map<String, dynamic>;
        phone = delivery['phone'] as String?;
      } catch (_) {}
      if (phone != null && phone.isNotEmpty) {
        final orders = await SupabaseService.getOrdersByPhone(phone);
        if (mounted) setState(() => _historial = orders);
      }
    }
  }

  Future<void> _toggleBan() async {
    if (_repartidorId == null) return;
    setState(() => _busyBan = true);
    final banned = _authInfo?['banned'] == true;
    final ok = await SupabaseService.setUserBanned(_repartidorId!, !banned);
    if (ok && mounted) {
      setState(() => _authInfo = {...(_authInfo ?? {}), 'banned': !banned});
    }
    if (mounted) setState(() => _busyBan = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rating;
    final stars = r['stars'] as int? ?? 0;
    final comment = r['comment'] as String?;
    final reportReason = r['report_reason'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.reviewerLabel,
              style: const TextStyle(
                color: AdminColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFFFB300),
                  size: 20,
                ),
              ),
            ),
            if (comment != null && comment.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                comment,
                style: TextStyle(
                  color: AdminColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            if (reportReason != null && reportReason.isNotEmpty) ...[
              const SizedBox(height: 14),
              AdminSectionCard(
                title: 'Motivo del reporte',
                child: Text(
                  reportReason,
                  style: TextStyle(
                    color: AdminColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AdminSectionCard(
              title: widget.isRepartidor
                  ? 'Cuenta del repartidor'
                  : 'Información del cliente',
              child: widget.isRepartidor
                  ? _buildCuentaRepartidor()
                  : _buildCuentaCliente(),
            ),
            const SizedBox(height: 16),
            AdminSectionCard(
              title: 'Historial de pedidos (${_historial.length})',
              child: _historial.isEmpty
                  ? Text(
                      'Sin más pedidos registrados',
                      style: TextStyle(
                        color: AdminColors.textFaint,
                        fontSize: 12,
                      ),
                    )
                  : Column(
                      children: _historial.take(5).map((o) {
                        final total = (o['total'] as num?)?.toDouble() ?? 0;
                        final created = DateTime.tryParse(
                          o['created_at'] as String? ?? '',
                        );
                        final fecha = created == null
                            ? ''
                            : '${created.day}/${created.month}/${created.year}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fecha,
                                  style: TextStyle(
                                    color: AdminColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                '\$${total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: AdminColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              AdminSectionCard(
                title: 'Historial de moderación',
                child: Column(
                  children: _log.map((l) {
                    final created = DateTime.tryParse(
                      l['created_at'] as String? ?? '',
                    );
                    final fecha = created == null
                        ? ''
                        : '${created.day}/${created.month} ${created.hour}:${created.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '$fecha — ${l['admin_email']} → ${l['action']}${l['note'] != null && (l['note'] as String).isNotEmpty ? ' ("${l['note']}")' : ''}',
                        style: TextStyle(
                          color: AdminColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCuentaRepartidor() {
    if (_loadingAuth) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: CircularProgressIndicator(
            color: AdminColors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_authInfo == null) {
      return Text(
        'No se pudo consultar la cuenta.',
        style: TextStyle(color: AdminColors.textFaint, fontSize: 12),
      );
    }
    final email = _authInfo!['email'] as String?;
    final provider = _authInfo!['provider'] as String? ?? 'email';
    final createdAt = DateTime.tryParse(
      _authInfo!['createdAt'] as String? ?? '',
    );
    final banned = _authInfo!['banned'] == true;
    final registro = createdAt == null
        ? '—'
        : '${createdAt.day}/${createdAt.month}/${createdAt.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              provider == 'google' ? Icons.g_mobiledata : Icons.person_outline,
              color: AdminColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              provider == 'google'
                  ? 'Inició con Google'
                  : 'Cuenta propia de la app',
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Correo: ${email ?? '—'}',
          style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Registrado: $registro',
          style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Reseñas publicadas: $_totalResenas',
          style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Estado: ',
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            ),
            Text(
              banned ? 'Suspendida' : 'Activa',
              style: TextStyle(
                color: banned
                    ? AdminColors.statusCancelled
                    : AdminColors.statusDelivered,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busyBan ? null : _toggleBan,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: banned
                    ? AdminColors.statusDelivered
                    : AdminColors.statusCancelled,
              ),
            ),
            child: _busyBan
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    banned ? 'Reactivar cuenta' : 'Suspender cuenta',
                    style: TextStyle(
                      color: banned
                          ? AdminColors.statusDelivered
                          : AdminColors.statusCancelled,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCuentaCliente() {
    final order = widget.rating['orders'] as Map<String, dynamic>?;
    String? phone;
    try {
      final delivery =
          jsonDecode(order?['customer_name'] as String? ?? '{}')
              as Map<String, dynamic>;
      phone = delivery['phone'] as String?;
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.person_outline,
              color: AdminColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              'Invitado — sin cuenta vinculada',
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Teléfono: $phone',
            style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Los pedidos no requieren una cuenta real (solo nombre/teléfono), así que no hay correo, fecha de registro ni método de inicio de sesión que mostrar para el lado cliente.',
          style: TextStyle(
            color: AdminColors.textFaint,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ── Estadísticas ─────────────────────────────────────────────────────────────

class _EstadisticasView extends StatefulWidget {
  final List<Map<String, dynamic>> all;
  const _EstadisticasView({required this.all});
  @override
  State<_EstadisticasView> createState() => _EstadisticasViewState();
}

class _EstadisticasViewState extends State<_EstadisticasView> {
  bool _loadingProviders = true;
  int _googleCount = 0;
  int _emailCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final ids = widget.all
        .where((r) => r['is_driver'] == true)
        .map(
          (r) =>
              (r['orders'] as Map<String, dynamic>?)?['repartidor_id']
                  as String?,
        )
        .whereType<String>()
        .toSet();
    int google = 0, email = 0;
    final results = await Future.wait(ids.map(SupabaseService.lookupAuthUser));
    for (final info in results) {
      if (info == null) continue;
      if (info['provider'] == 'google') {
        google++;
      } else {
        email++;
      }
    }
    if (mounted)
      setState(() {
        _googleCount = google;
        _emailCount = email;
        _loadingProviders = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.all;
    final total = all.length;
    final avg = total == 0
        ? 0.0
        : all.fold<int>(0, (s, r) => s + (r['stars'] as int? ?? 0)) / total;
    final dist = List.filled(6, 0);
    for (final r in all) {
      final s = r['stars'] as int? ?? 0;
      if (s >= 1 && s <= 5) dist[s]++;
    }

    // Solo reseñas cliente→repartidor (is_driver: false) — son las que
    // califican al trabajador, que es lo único que le importa a la
    // plataforma (no hay reseñas de platillos ni de restaurantes).
    final Map<String, List<int>> porRepartidor = {};
    for (final r in all) {
      if (r['is_driver'] != false) continue;
      final repId =
          (r['orders'] as Map<String, dynamic>?)?['repartidor_id'] as String?;
      if (repId == null) continue;
      porRepartidor.putIfAbsent(repId, () => []).add(r['stars'] as int? ?? 0);
    }
    final ranked = porRepartidor.entries.where((e) => e.value.length >= 3).map((
      e,
    ) {
      final avgR = e.value.reduce((a, b) => a + b) / e.value.length;
      final shortId = e.key.length >= 8
          ? e.key.substring(0, 8).toUpperCase()
          : e.key.toUpperCase();
      return (name: 'Repartidor $shortId', avg: avgR, count: e.value.length);
    }).toList()..sort((a, b) => b.avg.compareTo(a.avg));

    final now = DateTime.now();
    final ultimos7 = List.generate(
      7,
      (i) => now.subtract(Duration(days: 6 - i)),
    );
    final porDia = ultimos7.map((d) {
      return all.where((r) {
        final c = DateTime.tryParse(r['created_at'] as String? ?? '');
        return c != null &&
            c.year == d.year &&
            c.month == d.month &&
            c.day == d.day;
      }).length;
    }).toList();
    final maxDia = porDia.isEmpty
        ? 1
        : porDia.reduce((a, b) => a > b ? a : b).clamp(1, 999999);

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
            AdminStatCard(
              label: 'Total de reseñas',
              value: '$total',
              icon: Icons.forum_outlined,
              color: AdminColors.accent,
            ),
            AdminStatCard(
              label: 'Promedio general',
              value: avg.toStringAsFixed(1),
              icon: Icons.star_rounded,
              color: const Color(0xFFFFB300),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Distribución por estrellas',
          child: Column(
            children: List.generate(5, (i) {
              final s = 5 - i;
              final count = dist[s];
              final frac = total == 0 ? 0.0 : count / total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$s★',
                        style: TextStyle(
                          color: AdminColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 8,
                          backgroundColor: AdminColors.surfaceElevated,
                          color: AdminColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AdminColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Reseñas en los últimos 7 días',
          child: SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final d = ultimos7[i];
                final h = porDia[i] / maxDia;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${porDia[i]}',
                          style: TextStyle(
                            color: AdminColors.textFaint,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 40 * h + 4,
                          decoration: BoxDecoration(
                            color: AdminColors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.day}/${d.month}',
                          style: TextStyle(
                            color: AdminColors.textFaint,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (ranked.isNotEmpty) ...[
          AdminSectionCard(
            title: 'Repartidores mejor calificados (mín. 3 reseñas)',
            child: Column(
              children: ranked
                  .take(5)
                  .map((e) => _rankRow(e.name, e.avg, e.count))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          AdminSectionCard(
            title: 'Repartidores peor calificados (mín. 3 reseñas)',
            child: Column(
              children: ranked.reversed
                  .take(5)
                  .map((e) => _rankRow(e.name, e.avg, e.count))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        AdminSectionCard(
          title: 'Método de inicio de sesión (lado repartidor)',
          child: _loadingProviders
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AdminColors.accent,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google: $_googleCount   ·   Cuenta propia: $_emailCount',
                      style: TextStyle(
                        color: AdminColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Solo aplica al lado repartidor de las reseñas: los pedidos de clientes no requieren cuenta, así que no hay método de login que contar para ese lado.',
                      style: TextStyle(
                        color: AdminColors.textFaint,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _rankRow(String name, double avg, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.star_rounded, color: const Color(0xFFFFB300), size: 14),
        const SizedBox(width: 3),
        Text(
          '${avg.toStringAsFixed(1)} ($count)',
          style: const TextStyle(
            color: AdminColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
