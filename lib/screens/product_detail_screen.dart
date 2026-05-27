import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String restaurantId;
  final String restaurantName;
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.restaurantId,
    this.restaurantName = 'Tu restaurante',
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity     = 1;
  int _currentImage = 0;

  void _addToCart() {
    final cart = context.read<CartProvider>();
    for (int i = 0; i < _quantity; i++) {
      cart.addProduct(widget.product, widget.restaurantId, widget.restaurantName);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.product.name} agregado al carrito'),
        backgroundColor: Colors.green[700],
        action: SnackBarAction(
          label: 'Ver carrito',
          textColor: Colors.white,
          onPressed: () => context.push('/cart'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: images.isNotEmpty
                  ? Stack(
                      children: [
                        CarouselSlider(
                          options: CarouselOptions(
                            height: 320,
                            viewportFraction: 1.0,
                            autoPlay: images.length > 1,
                            onPageChanged: (i, _) => setState(() => _currentImage = i),
                          ),
                          items: images
                              .map(
                                (url) => Image.network(url, fit: BoxFit.cover, width: double.infinity,
                                    errorBuilder: (ctx, err, st) => _imagePlaceholder()),
                              )
                              .toList(),
                        ),
                        // Indicadores de imagen
                        if (images.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: images.asMap().entries.map((e) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _currentImage == e.key ? 20 : 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: _currentImage == e.key
                                        ? AppConstants.primaryColor
                                        : Colors.white.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    )
                  : _imagePlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppConstants.surface2Color,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${widget.product.price.toStringAsFixed(0)} MXN',
                      style: TextStyle(fontSize: 22, color: AppConstants.primaryColor, fontWeight: FontWeight.bold),
                    ),
                    if (widget.product.description != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.product.description!,
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.65), fontSize: 15, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('Cantidad', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                        const Spacer(),
                        _QuantityButton(
                          icon: Icons.remove,
                          onTap: () { if (_quantity > 1) setState(() => _quantity--); },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ),
                        _QuantityButton(
                          icon: Icons.add,
                          filled: true,
                          onTap: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
          color: AppConstants.primaryColor,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _addToCart,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Agregar al pedido  •  \$${(widget.product.price * _quantity).toStringAsFixed(0)} MXN',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConstants.primaryColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        color: AppConstants.surfaceColor,
        child: const Center(child: Icon(Icons.fastfood, size: 100, color: AppConstants.primaryColor)),
      );
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _QuantityButton({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? AppConstants.primaryColor : AppConstants.surface2Color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
