// my_promotions_screen.dart
// "Mis promociones" — las promociones que el cliente ya reclamó, agrupadas
// en las 4 secciones de siempre. Se usa de dos formas:
//   - Modo normal (desde el perfil/menú): solo para consultar.
//   - Modo selección (selectionMode: true, desde checkout_screen.dart):
//     tocar una promoción Disponible la regresa con Navigator.pop(claim) en
//     vez de navegar más adentro — el mismo patrón que ya usa
//     MapPickerScreen para regresar una ubicación elegida.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/promotion_claim.dart';
import '../../services/supabase_service.dart';

class MyPromotionsScreen extends StatefulWidget {
  final bool selectionMode;
  final String? restaurantId; // si se da, en modo selección solo se pueden elegir promos de ese restaurante (o de toda la plataforma)

  const MyPromotionsScreen({super.key, this.selectionMode = false, this.restaurantId});

  @override
  State<MyPromotionsScreen> createState() => _MyPromotionsScreenState();
}

class _MyPromotionsScreenState extends State<MyPromotionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  Map<ClaimBucket, List<PromotionClaim>> _grouped = {};

  // Nota: "Próximamente" (ClaimBucket.proximamente) se quitó de esta lista a
  // petición — el enum y el cálculo del bucket se quedan igual (ver
  // promotion_claim.dart), simplemente esa pestaña ya no se muestra. Un
  // reclamo de una promoción que todavía no empieza no aparece en ningún
  // lado hasta que de verdad empiece (ahí ya cae solo en Disponibles).
  static const _buckets = [
    (ClaimBucket.disponible, 'Disponibles', '🟢'),
    (ClaimBucket.expirada, 'Expiradas', '🔴'),
    (ClaimBucket.utilizada, 'Utilizadas', '⚫'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _buckets.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final grouped = await SupabaseService.getMyPromotions();
    if (!mounted) return;
    setState(() { _grouped = grouped; _loading = false; });
  }

  bool _selectable(PromotionClaim c) {
    if (!widget.selectionMode || c.bucket != ClaimBucket.disponible) return false;
    final p = c.promotion;
    if (p == null) return false;
    if (widget.restaurantId == null) return true;
    return p.isPlatformWide || p.restaurantId == widget.restaurantId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.bgColor,
        elevation: 0,
        title: const Text('Mis promociones', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppConstants.primaryColor,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: [for (final b in _buckets) Tab(text: '${b.$3} ${b.$2}')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppConstants.primaryColor,
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final b in _buckets) _buildList(_grouped[b.$1] ?? const []),
                ],
              ),
            ),
    );
  }

  Widget _buildList(List<PromotionClaim> claims) {
    if (claims.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text('Nada por aquí todavía', style: TextStyle(color: Colors.white38)),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: claims.length,
      itemBuilder: (context, i) => _PromoClaimCard(
        claim: claims[i],
        selectable: _selectable(claims[i]),
        onTap: _selectable(claims[i]) ? () => Navigator.pop(context, claims[i]) : null,
      ),
    );
  }
}

class _PromoClaimCard extends StatelessWidget {
  final PromotionClaim claim;
  final bool selectable;
  final VoidCallback? onTap;

  const _PromoClaimCard({required this.claim, required this.selectable, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = claim.promotion;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: selectable ? Border.all(color: AppConstants.primaryColor, width: 1.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p?.imageUrl != null)
              Image.network(p!.imageUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(p?.title ?? 'Promoción', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    _StatusChip(claim.bucket),
                  ]),
                  if (p != null && p.benefitLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.benefitLabel, style: const TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                  if (p != null && p.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(p.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                  ],
                  if (p?.expiresAt != null) ...[
                    const SizedBox(height: 6),
                    Text('Válido hasta: ${_formatDate(p!.expiresAt!)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                  ],
                  if (p != null && p.conditionsSummary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.conditionsSummary, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                  ],
                  if (p?.code != null) ...[
                    const SizedBox(height: 6),
                    Text('Código: ${p!.code}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
                  ],
                  if (claim.status == 'used' && claim.discountAmount != null) ...[
                    const SizedBox(height: 6),
                    Text('Descuento aplicado: \$${claim.discountAmount!.toStringAsFixed(0)} MXN',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                  if (selectable) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, foregroundColor: Colors.white),
                        child: const Text('Gastar cupón'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} de ${months[d.month]}';
  }
}

class _StatusChip extends StatelessWidget {
  final ClaimBucket bucket;
  const _StatusChip(this.bucket);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (bucket) {
      ClaimBucket.disponible => ('DISPONIBLE', Colors.green),
      ClaimBucket.proximamente => ('PRÓXIMAMENTE', Colors.amber),
      ClaimBucket.expirada => ('EXPIRADA', Colors.redAccent),
      ClaimBucket.utilizada => ('UTILIZADA', Colors.white38),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}
