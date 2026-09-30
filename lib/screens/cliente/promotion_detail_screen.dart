// promotion_detail_screen.dart
// Detalle de una promoción real, con el botón "Reclamar" — a donde llega el
// cliente al tocar un banner de app_promos que tiene linked_promotion_id.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/promotion.dart';
import '../../services/supabase_service.dart';

class PromotionDetailScreen extends StatefulWidget {
  final String promotionId;
  const PromotionDetailScreen({super.key, required this.promotionId});

  @override
  State<PromotionDetailScreen> createState() => _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends State<PromotionDetailScreen> {
  Promotion? _promo;
  bool _loading = true;
  bool _claiming = false;
  bool _claimed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final promo = await SupabaseService.getPromotionById(widget.promotionId);
    if (mounted) setState(() { _promo = promo; _loading = false; });
  }

  Future<void> _claim() async {
    setState(() { _claiming = true; _error = null; });
    try {
      await SupabaseService.claimPromotion(widget.promotionId);
      if (mounted) setState(() { _claimed = true; _claiming = false; });
    } catch (e) {
      if (mounted) setState(() { _error = _mapError(e); _claiming = false; });
    }
  }

  String _mapError(Object e) {
    final s = e.toString();
    if (s.contains('promocion_no_iniciada')) return 'Esta promoción todavía no empieza.';
    if (s.contains('promocion_expirada')) return 'Esta promoción ya venció.';
    if (s.contains('promocion_inactiva')) return 'Esta promoción ya no está disponible.';
    if (s.contains('limite_de_reclamos_alcanzado')) return 'Se agotaron los cupos para esta promoción.';
    if (s.contains('ya_reclamaste_el_maximo')) return 'Ya reclamaste esta promoción antes.';
    return 'No se pudo reclamar la promoción. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
          : _promo == null
              ? const Center(child: Text('Promoción no encontrada', style: TextStyle(color: Colors.white54)))
              : _buildContent(_promo!),
    );
  }

  Widget _buildContent(Promotion p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(p.imageUrl!, height: 200, width: double.infinity, fit: BoxFit.cover),
            ),
          const SizedBox(height: 20),
          Text(p.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          if (p.benefitLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.benefitLabel, style: const TextStyle(color: AppConstants.primaryColor, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, height: 1.5)),
          ],
          if (p.conditionsSummary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppConstants.surfaceColor, borderRadius: BorderRadius.circular(12)),
              child: Text(p.conditionsSummary, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 28),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_claimed || _claiming || !p.isCurrentlyClaimable) ? null : _claim,
              style: ElevatedButton.styleFrom(
                backgroundColor: _claimed ? Colors.green : AppConstants.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: _claiming
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _claimed
                          ? '¡Reclamada! Ya está en Mis promociones'
                          : (p.isCurrentlyClaimable ? 'Reclamar promoción' : 'No disponible por ahora'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
