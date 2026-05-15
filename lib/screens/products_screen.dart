import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/supabase_service.dart';

class ProductsScreen extends StatefulWidget {
  final Category category;
  final Restaurant restaurant;
  const ProductsScreen({super.key, required this.category, required this.restaurant});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _futureProducts;

  @override
  void initState() {
    super.initState();
    _futureProducts = SupabaseService.getProducts(widget.category.id);
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.category.icon ?? '🍽️', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(widget.category.name, style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => context.push('/cart'),
              ),
              if (cartCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppConstants.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$cartCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Product>>(
        future: _futureProducts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.no_food_outlined, size: 60, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('No hay productos disponibles',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, i) => _ProductCard(
              product: products[i],
              restaurant: widget.restaurant,
            ),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final Restaurant restaurant;
  const _ProductCard({required this.product, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/product-detail', extra: {
        'product': product,
        'restaurantId': restaurant.id,
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 110,
                height: 110,
                child: product.imageUrl != null
                    ? Image.network(product.imageUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _imagePlaceholder())
                    : _imagePlaceholder(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (product.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.description!,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      '\$${product.price.toStringAsFixed(0)} MXN',
                      style: const TextStyle(
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: AppConstants.primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        color: AppConstants.surface2Color,
        child: const Center(child: Icon(Icons.fastfood, size: 36, color: AppConstants.primaryColor)),
      );
}
