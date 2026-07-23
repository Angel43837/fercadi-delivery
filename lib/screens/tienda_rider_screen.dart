import 'package:flutter/material.dart';
import '../core/constants.dart';

const _items = [
  _Item(
    emoji: '⛽',
    name: 'Tanque de gas',
    desc: 'Descuento \$50 MXN en tu próxima carga',
    coins: 300,
    imageUrl: 'https://images.unsplash.com/photo-1571685261180-cdc9f8bc77f0?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '📱',
    name: 'Recarga de celular',
    desc: '\$30 MXN de tiempo aire para cualquier operadora',
    coins: 200,
    imageUrl: 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '💵',
    name: 'Bono en efectivo',
    desc: '\$100 MXN directos a tu saldo de retiro',
    coins: 600,
    imageUrl: 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '🧢',
    name: 'Gorra GOGO',
    desc: 'Gorra oficial de repartidor GOGO Food',
    coins: 1000,
    imageUrl: 'https://images.unsplash.com/photo-1588850561407-ed78c282e89b?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '🏷️',
    name: 'Super descuento',
    desc: '20% de descuento en tu próximo pedido como cliente',
    coins: 150,
    imageUrl: 'https://images.unsplash.com/photo-1607082348824-0a96f2a4b9da?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '🎮',
    name: 'Steam Gift Card',
    desc: 'Código digital \$200 MXN para Steam',
    coins: 2000,
    imageUrl: 'https://images.unsplash.com/photo-1593305841991-05c297ba4575?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '🍕',
    name: 'Pedido gratis',
    desc: 'Un pedido gratis hasta \$150 MXN para ti',
    coins: 800,
    imageUrl: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&h=260&fit=crop&auto=format',
  ),
  _Item(
    emoji: '⚡',
    name: 'Doble coins',
    desc: 'Gana 2× coins en todos tus repartos por 24 horas',
    coins: 500,
    imageUrl: 'https://images.unsplash.com/photo-1518546305927-5a555bb7020d?w=400&h=260&fit=crop&auto=format',
  ),
];

class _Item {
  final String emoji;
  final String name;
  final String desc;
  final int coins;
  final String imageUrl;
  const _Item({
    required this.emoji,
    required this.name,
    required this.desc,
    required this.coins,
    required this.imageUrl,
  });
}

class TiendaRiderScreen extends StatefulWidget {
  final int currentCoins;
  const TiendaRiderScreen({super.key, required this.currentCoins});

  @override
  State<TiendaRiderScreen> createState() => _TiendaRiderScreenState();
}

class _TiendaRiderScreenState extends State<TiendaRiderScreen> {
  late int _coins;
  final Set<int> _canjeados = {};

  @override
  void initState() {
    super.initState();
    _coins = widget.currentCoins;
  }

  void _openDetail(int index) {
    final item = _items[index];
    final canPay = _coins >= item.coins;
    final done = _canjeados.contains(index);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemSheet(
        item: item,
        canPay: canPay,
        done: done,
        onCanjear: done
            ? null
            : () {
                if (!canPay) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Necesitas ${item.coins - _coins} coins más'),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                setState(() {
                  _coins -= item.coins;
                  _canjeados.add(index);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('¡${item.name} canjeado! 🎉'),
                    backgroundColor: Colors.green.shade700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: CustomScrollView(
        slivers: [
          // Header naranja
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: AppConstants.primaryColor,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 8),
                  const Text('Tienda de Coins',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Text('🪙', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Tus coins disponibles',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('$_coins coins',
                          style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = _items[i];
                  final canPay = _coins >= item.coins;
                  final done = _canjeados.contains(i);
                  return GestureDetector(
                    onTap: () => _openDetail(i),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: done ? 0.55 : 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Imagen
                            Expanded(
                              flex: 5,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    item.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) => Container(
                                      color: const Color(0xFFFFE0CC),
                                      child: Center(
                                        child: Text(item.emoji,
                                            style: const TextStyle(fontSize: 40)),
                                      ),
                                    ),
                                  ),
                                  if (done)
                                    Container(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      child: const Center(
                                        child: Icon(Icons.check_circle_rounded,
                                            color: Colors.green, size: 36),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Info
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name,
                                        style: const TextStyle(
                                            color: Color(0xFF1A1A1A),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 3),
                                    Text(item.desc,
                                        style: const TextStyle(
                                            color: Color(0xFF888888),
                                            fontSize: 10),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    const Spacer(),
                                    done
                                        ? const Text('✓ Canjeado',
                                            style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold))
                                        : Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: canPay
                                                  ? AppConstants.primaryColor
                                                  : const Color(0xFFEEEEEE),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text('🪙',
                                                    style: TextStyle(fontSize: 11)),
                                                const SizedBox(width: 3),
                                                Text('${item.coins}',
                                                    style: TextStyle(
                                                        color: canPay
                                                            ? Colors.white
                                                            : const Color(0xFF999999),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _ItemSheet extends StatelessWidget {
  final _Item item;
  final bool canPay;
  final bool done;
  final VoidCallback? onCanjear;

  const _ItemSheet({
    required this.item,
    required this.canPay,
    required this.done,
    required this.onCanjear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Imagen grande
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              item.imageUrl,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => Container(
                height: 220,
                color: const Color(0xFFFFE0CC),
                child: Center(
                  child: Text(item.emoji, style: const TextStyle(fontSize: 72)),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(item.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.name,
                        style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(item.desc,
                    style: const TextStyle(
                        color: Color(0xFF666666), fontSize: 14, height: 1.5)),
                const SizedBox(height: 20),
                Row(children: [
                  const Text('🪙', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 6),
                  Text('${item.coins} coins',
                      style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: done
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text('Ya canjeaste este artículo',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                        )
                      : ElevatedButton(
                          onPressed: onCanjear,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canPay
                                ? AppConstants.primaryColor
                                : const Color(0xFFCCCCCC),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            canPay ? 'Canjear ahora' : 'Coins insuficientes',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
