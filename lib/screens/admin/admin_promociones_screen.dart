// admin_promociones_screen.dart
// Panel de administración de promociones/cupones reales — separado por
// completo de app_promos (banners visuales, que solo pueden enlazar a una
// promoción de aquí, nunca aplicar un descuento por sí mismos).
// Sigue el mismo patrón que Retiros/Reseñas: pantalla propia con su ruta
// (/admin/promociones en main_admin.dart), no una pestaña del IndexedStack.

import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

const _typeLabels = {
  '2x1': '2x1',
  'percent': '% de descuento',
  'fixed_amount': 'Monto fijo',
  'free_shipping': 'Envío gratis',
  'free_product': 'Producto gratis',
};

const _weekdayLabels = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 7: 'Dom'};

class AdminPromocionesScreen extends StatefulWidget {
  const AdminPromocionesScreen({super.key});
  @override
  State<AdminPromocionesScreen> createState() => _AdminPromocionesScreenState();
}

class _AdminPromocionesScreenState extends State<AdminPromocionesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _promos = [];
  final Map<String, Map<String, dynamic>> _stats = {};
  Map<String, String> _restaurantNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final restaurants = await SupabaseService.getRestaurantsAdmin();
    _restaurantNames = {for (final r in restaurants) r['id'] as String: r['name'] as String? ?? ''};
    final promos = await SupabaseService.adminGetPromotions();
    if (!mounted) return;
    setState(() { _promos = promos; _loading = false; });
    for (final p in promos) {
      final stats = await SupabaseService.getPromotionStats(p['id'] as String);
      if (mounted) setState(() => _stats[p['id'] as String] = stats);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> promo) async {
    final newValue = !(promo['is_active'] as bool? ?? true);
    await SupabaseService.adminSetPromotionActive(promo['id'] as String, newValue);
    _load();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _PromotionFormScreen(existing: existing)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: const Text('Promociones', style: TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AdminColors.accent,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
          : _promos.isEmpty
              ? Center(child: Text('Todavía no hay promociones', style: TextStyle(color: AdminColors.textSecondary)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AdminColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    itemCount: _promos.length,
                    itemBuilder: (context, i) => _PromoCard(
                      promo: _promos[i],
                      restaurantName: _restaurantNames[_promos[i]['restaurant_id']],
                      stats: _stats[_promos[i]['id']],
                      onTap: () => _openForm(existing: _promos[i]),
                      onToggle: () => _toggleActive(_promos[i]),
                    ),
                  ),
                ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final String? restaurantName;
  final Map<String, dynamic>? stats;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _PromoCard({required this.promo, this.restaurantName, this.stats, required this.onTap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isActive = promo['is_active'] as bool? ?? true;
    final type = promo['type'] as String? ?? '';
    final maxClaims = promo['max_claims'] as int?;
    final claims = stats?['claims'] as int? ?? 0;
    final used = stats?['used'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminSectionCard(
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(promo['title'] as String? ?? '',
                    style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Switch(value: isActive, onChanged: (_) => onToggle(), activeThumbColor: AdminColors.accent),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              AdminPill(child: Text(_typeLabels[type] ?? type, style: TextStyle(color: AdminColors.textSecondary, fontSize: 11))),
              AdminPill(child: Text(restaurantName ?? 'Toda la plataforma', style: TextStyle(color: AdminColors.textSecondary, fontSize: 11))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _MiniStat('Reclamos', '$claims${maxClaims != null ? '/$maxClaims' : ''}'),
              const SizedBox(width: 16),
              _MiniStat('Usadas', '$used'),
              const SizedBox(width: 16),
              _MiniStat('Disponibles', maxClaims != null ? '${(maxClaims - claims).clamp(0, maxClaims)}' : '∞'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
      Text(label, style: TextStyle(color: AdminColors.textSecondary, fontSize: 10)),
    ]);
  }
}

// ── Formulario de crear/editar ──────────────────────────────────────────

class _PromotionFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PromotionFormScreen({this.existing});

  @override
  State<_PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<_PromotionFormScreen> {
  late final _titleCtrl = TextEditingController(text: widget.existing?['title'] as String? ?? '');
  late final _descCtrl = TextEditingController(text: widget.existing?['description'] as String? ?? '');
  late final _imageCtrl = TextEditingController(text: widget.existing?['image_url'] as String? ?? '');
  late final _benefitCtrl = TextEditingController(text: widget.existing?['benefit_label'] as String? ?? '');
  late final _codeCtrl = TextEditingController(text: widget.existing?['code'] as String? ?? '');
  late final _termsCtrl = TextEditingController(text: widget.existing?['terms'] as String? ?? '');
  late final _minPurchaseCtrl = TextEditingController(text: (widget.existing?['min_purchase_amount'] as num?)?.toString() ?? '0');
  late final _maxDiscountCtrl = TextEditingController(text: (widget.existing?['max_discount_amount'] as num?)?.toString() ?? '');
  late final _maxTotalUsesCtrl = TextEditingController(text: (widget.existing?['max_total_uses'] as num?)?.toString() ?? '');
  late final _maxUsesPerUserCtrl = TextEditingController(text: (widget.existing?['max_uses_per_user'] as num?)?.toString() ?? '1');
  late final _maxClaimsCtrl = TextEditingController(text: (widget.existing?['max_claims'] as num?)?.toString() ?? '');
  late final _freeProductIdCtrl = TextEditingController(text: widget.existing?['free_product_id'] as String? ?? '');

  late String _type = widget.existing?['type'] as String? ?? 'percent';
  // Valor específico del tipo (percent/amount/min_qty) — vive en `rules`.
  late final _ruleValueCtrl = TextEditingController(
    text: ((widget.existing?['rules'] as Map?)?['percent'] ??
            (widget.existing?['rules'] as Map?)?['amount'] ??
            (widget.existing?['rules'] as Map?)?['min_qty'])
        ?.toString() ??
        '',
  );

  late String? _restaurantId = widget.existing?['restaurant_id'] as String?;
  List<Map<String, dynamic>> _restaurants = [];
  List<Category> _categories = [];
  List<Product> _products = [];
  Set<String> _selectedProductIds = {};
  Set<String> _selectedCategoryIds = {};

  DateTime? _startsAt = _parseDate(null);
  DateTime? _expiresAt;
  TimeOfDay? _timeStart;
  TimeOfDay? _timeEnd;
  Set<int> _daysOfWeek = {};
  bool _combinable = false;
  bool _appliesToShipping = false;
  bool _isActive = true;
  bool _saving = false;
  bool _loadingLists = true;

  static DateTime? _parseDate(String? s) => s != null ? DateTime.tryParse(s) : null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _startsAt = _parseDate(e['starts_at'] as String?);
      _expiresAt = _parseDate(e['expires_at'] as String?);
      _combinable = e['combinable'] as bool? ?? false;
      _appliesToShipping = e['applies_to_shipping'] as bool? ?? false;
      _isActive = e['is_active'] as bool? ?? true;
      _selectedProductIds = ((e['applicable_product_ids'] as List?)?.cast<String>() ?? []).toSet();
      _selectedCategoryIds = ((e['applicable_category_ids'] as List?)?.cast<String>() ?? []).toSet();
      final dow = (e['days_of_week'] as List?)?.cast<int>();
      if (dow != null) _daysOfWeek = dow.toSet();
      final ts = e['time_window_start'] as String?;
      final te = e['time_window_end'] as String?;
      if (ts != null) _timeStart = _parseTimeOfDay(ts);
      if (te != null) _timeEnd = _parseTimeOfDay(te);
    } else {
      _startsAt = null;
    }
    _loadLists();
  }

  static TimeOfDay _parseTimeOfDay(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _loadLists() async {
    final restaurants = await SupabaseService.getRestaurantsAdmin();
    if (mounted) setState(() { _restaurants = restaurants; _loadingLists = false; });
    if (_restaurantId != null) await _loadRestaurantCatalog(_restaurantId!);
  }

  Future<void> _loadRestaurantCatalog(String restaurantId) async {
    final cats = await SupabaseService.getCategories(restaurantId);
    final prods = await SupabaseService.getProductsForRestaurant(restaurantId);
    if (mounted) setState(() { _categories = cats; _products = prods; });
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl, _descCtrl, _imageCtrl, _benefitCtrl, _codeCtrl, _termsCtrl,
      _minPurchaseCtrl, _maxDiscountCtrl, _maxTotalUsesCtrl, _maxUsesPerUserCtrl,
      _maxClaimsCtrl, _freeProductIdCtrl, _ruleValueCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildRules() {
    final v = _ruleValueCtrl.text.trim();
    if (v.isEmpty) return {};
    switch (_type) {
      case 'percent': return {'percent': num.tryParse(v) ?? 0};
      case 'fixed_amount': return {'amount': num.tryParse(v) ?? 0};
      case '2x1': return {'min_qty': int.tryParse(v) ?? 2};
      default: return {};
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ponle un título a la promoción'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'type': _type,
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'image_url': _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
      'benefit_label': _benefitCtrl.text.trim(),
      'code': _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
      'terms': _termsCtrl.text.trim(),
      'restaurant_id': _restaurantId,
      'applicable_product_ids': _selectedProductIds.isEmpty ? null : _selectedProductIds.toList(),
      'applicable_category_ids': _selectedCategoryIds.isEmpty ? null : _selectedCategoryIds.toList(),
      'free_product_id': _type == 'free_product' && _freeProductIdCtrl.text.trim().isNotEmpty
          ? _freeProductIdCtrl.text.trim() : null,
      'min_purchase_amount': num.tryParse(_minPurchaseCtrl.text.trim()) ?? 0,
      'max_discount_amount': _maxDiscountCtrl.text.trim().isEmpty ? null : num.tryParse(_maxDiscountCtrl.text.trim()),
      'starts_at': _startsAt?.toIso8601String(),
      'expires_at': _expiresAt?.toIso8601String(),
      'time_window_start': _timeStart != null ? '${_timeStart!.hour.toString().padLeft(2, '0')}:${_timeStart!.minute.toString().padLeft(2, '0')}:00' : null,
      'time_window_end': _timeEnd != null ? '${_timeEnd!.hour.toString().padLeft(2, '0')}:${_timeEnd!.minute.toString().padLeft(2, '0')}:00' : null,
      'days_of_week': _daysOfWeek.isEmpty ? null : _daysOfWeek.toList(),
      'max_total_uses': _maxTotalUsesCtrl.text.trim().isEmpty ? null : int.tryParse(_maxTotalUsesCtrl.text.trim()),
      'max_uses_per_user': int.tryParse(_maxUsesPerUserCtrl.text.trim()) ?? 1,
      'max_claims': _maxClaimsCtrl.text.trim().isEmpty ? null : int.tryParse(_maxClaimsCtrl.text.trim()),
      'combinable': _combinable,
      'applies_to_shipping': _appliesToShipping,
      'rules': _buildRules(),
      'is_active': _isActive,
    };
    try {
      if (widget.existing != null) {
        await SupabaseService.adminUpdatePromotion(widget.existing!['id'] as String, payload);
      } else {
        await SupabaseService.adminCreatePromotion(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AdminColors.textSecondary),
        filled: true,
        fillColor: AdminColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: Text(widget.existing != null ? 'Editar promoción' : 'Nueva promoción',
            style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loadingLists
          ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                AdminSectionCard(
                  title: 'Datos generales',
                  child: Column(children: [
                    TextField(controller: _titleCtrl, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Título')),
                    const SizedBox(height: 10),
                    TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Descripción')),
                    const SizedBox(height: 10),
                    TextField(controller: _benefitCtrl, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Beneficio (ej. "20% de descuento")')),
                    const SizedBox(height: 10),
                    TextField(controller: _imageCtrl, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('URL de imagen (opcional)')),
                    const SizedBox(height: 10),
                    TextField(controller: _codeCtrl, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Código (opcional)')),
                    const SizedBox(height: 10),
                    TextField(controller: _termsCtrl, maxLines: 2, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Condiciones (texto libre)')),
                  ]),
                ),
                const SizedBox(height: 16),
                AdminSectionCard(
                  title: 'Tipo y restaurante',
                  child: Column(children: [
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: _deco('Tipo de promoción'),
                      dropdownColor: AdminColors.surface,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      items: _typeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() => _type = v ?? 'percent'),
                    ),
                    if (_type == 'percent' || _type == 'fixed_amount' || _type == '2x1') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ruleValueCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AdminColors.textPrimary),
                        decoration: _deco(switch (_type) {
                          'percent' => 'Porcentaje (ej. 20)',
                          'fixed_amount' => 'Monto fijo en MXN',
                          _ => 'Cantidad mínima para el 2x1 (normalmente 2)',
                        }),
                      ),
                    ],
                    if (_type == 'free_product') ...[
                      const SizedBox(height: 10),
                      TextField(controller: _freeProductIdCtrl, style: const TextStyle(color: AdminColors.textPrimary),
                          decoration: _deco('ID del producto gratis')),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: _restaurantId,
                      decoration: _deco('Restaurante (vacío = toda la plataforma)'),
                      dropdownColor: AdminColors.surface,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Toda la plataforma')),
                        ..._restaurants.map((r) => DropdownMenuItem<String?>(value: r['id'] as String, child: Text(r['name'] as String? ?? ''))),
                      ],
                      onChanged: (v) {
                        setState(() { _restaurantId = v; _selectedProductIds = {}; _selectedCategoryIds = {}; _categories = []; _products = []; });
                        if (v != null) _loadRestaurantCatalog(v);
                      },
                    ),
                  ]),
                ),
                if (_restaurantId != null && (_categories.isNotEmpty || _products.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  AdminSectionCard(
                    title: 'Productos/categorías aplicables (vacío = todos)',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_categories.isNotEmpty) ...[
                        Text('Categorías', style: TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: _categories.map((c) {
                          final sel = _selectedCategoryIds.contains(c.id);
                          return AdminFilterChip(label: c.name, selected: sel, onTap: () => setState(() {
                            sel ? _selectedCategoryIds.remove(c.id) : _selectedCategoryIds.add(c.id);
                          }));
                        }).toList()),
                        const SizedBox(height: 14),
                      ],
                      if (_products.isNotEmpty) ...[
                        Text('Productos', style: TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: _products.map((p) {
                          final sel = _selectedProductIds.contains(p.id);
                          return AdminFilterChip(label: p.name, selected: sel, onTap: () => setState(() {
                            sel ? _selectedProductIds.remove(p.id) : _selectedProductIds.add(p.id);
                          }));
                        }).toList()),
                      ],
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                AdminSectionCard(
                  title: 'Fechas y horario',
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _DateButton(label: 'Inicio', value: _startsAt, onPick: (d) => setState(() => _startsAt = d))),
                      const SizedBox(width: 10),
                      Expanded(child: _DateButton(label: 'Vence', value: _expiresAt, onPick: (d) => setState(() => _expiresAt = d))),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _TimeButton(label: 'Desde', value: _timeStart, onPick: (t) => setState(() => _timeStart = t))),
                      const SizedBox(width: 10),
                      Expanded(child: _TimeButton(label: 'Hasta', value: _timeEnd, onPick: (t) => setState(() => _timeEnd = t))),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, children: _weekdayLabels.entries.map((e) {
                      final sel = _daysOfWeek.contains(e.key);
                      return AdminFilterChip(label: e.value, selected: sel, onTap: () => setState(() {
                        sel ? _daysOfWeek.remove(e.key) : _daysOfWeek.add(e.key);
                      }));
                    }).toList()),
                  ]),
                ),
                const SizedBox(height: 16),
                AdminSectionCard(
                  title: 'Límites',
                  child: Column(children: [
                    TextField(controller: _minPurchaseCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Compra mínima (MXN)')),
                    const SizedBox(height: 10),
                    TextField(controller: _maxDiscountCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Tope de descuento (MXN, opcional)')),
                    const SizedBox(height: 10),
                    TextField(controller: _maxTotalUsesCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Usos totales máximos (vacío = sin límite)')),
                    const SizedBox(height: 10),
                    TextField(controller: _maxUsesPerUserCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Usos máximos por usuario')),
                    const SizedBox(height: 10),
                    TextField(controller: _maxClaimsCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AdminColors.textPrimary), decoration: _deco('Máximo de gente que puede reclamarla (vacío = sin límite)')),
                  ]),
                ),
                const SizedBox(height: 16),
                AdminSectionCard(
                  child: Column(children: [
                    SwitchListTile(
                      value: _combinable, onChanged: (v) => setState(() => _combinable = v),
                      title: const Text('Combinable con otras promociones', style: TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
                      activeThumbColor: AdminColors.accent, contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: _appliesToShipping, onChanged: (v) => setState(() => _appliesToShipping = v),
                      title: const Text('Aplica al costo de envío (no a productos)', style: TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
                      activeThumbColor: AdminColors.accent, contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: _isActive, onChanged: (v) => setState(() => _isActive = v),
                      title: const Text('Activa', style: TextStyle(color: AdminColors.textPrimary, fontSize: 13)),
                      activeThumbColor: AdminColors.accent, contentPadding: EdgeInsets.zero,
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                AdminPrimaryButton(label: 'Guardar promoción', onPressed: _save, loading: _saving),
              ],
            ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  const _DateButton({required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context, initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2024), lastDate: DateTime(2100),
        );
        onPick(picked);
      },
      style: OutlinedButton.styleFrom(side: BorderSide(color: AdminColors.textSecondary), padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Text(
        value != null ? '$label: ${value!.day}/${value!.month}/${value!.year}' : label,
        style: const TextStyle(color: AdminColors.textPrimary, fontSize: 12),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onPick;
  const _TimeButton({required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(context: context, initialTime: value ?? TimeOfDay.now());
        onPick(picked);
      },
      style: OutlinedButton.styleFrom(side: BorderSide(color: AdminColors.textSecondary), padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Text(
        value != null ? '$label: ${value!.format(context)}' : label,
        style: const TextStyle(color: AdminColors.textPrimary, fontSize: 12),
      ),
    );
  }
}
