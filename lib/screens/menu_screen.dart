import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/supabase_service.dart';

class MenuScreen extends StatefulWidget {
  final Restaurant restaurant;
  const MenuScreen({super.key, required this.restaurant});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  int _selectedIndex = 0;
  List<Category> _categories = [];
  final Map<String, List<Product>> _products = {};
  bool _loading = true;

  static const _categoryColors = [
    AppConstants.primaryColor,
    Color(0xFFFF6D00),
    Color(0xFF00BFA5),
    Color(0xFF7C4DFF),
    Color(0xFF2196F3),
    Color(0xFFFFB300),
  ];

  Color get _activeColor =>
      _categoryColors[_selectedIndex % _categoryColors.length];

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    final cats = await SupabaseService.getCategories(widget.restaurant.id);
    final prods = <String, List<Product>>{};
    for (final cat in cats) {
      prods[cat.id] = await SupabaseService.getProducts(cat.id);
    }
    setState(() {
      _categories = cats;
      _products.addAll(prods);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.restaurant.name,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            if (widget.restaurant.address != null)
              Text(
                widget.restaurant.address!,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
          ],
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined,
                    color: Colors.white),
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppConstants.primaryColor))
          : Column(
              children: [
                _buildCategoryTabs(),
                Expanded(child: _buildProductList()),
              ],
            ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      color: AppConstants.surfaceColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: List.generate(_categories.length, (i) {
            final cat = _categories[i];
            final color = _categoryColors[i % _categoryColors.length];
            final isSelected = _selectedIndex == i;
            return GestureDetector(
              onTap: () => setState(() => _selectedIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : color.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cat.icon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(cat.icon!,
                            style: const TextStyle(fontSize: 16)),
                      ),
                    Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : color.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildProductList() {
    if (_categories.isEmpty) {
      return Center(
        child: Text('Sin productos disponibles',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15)),
      );
    }
    final catId = _categories[_selectedIndex].id;
    final products = _products[catId] ?? [];

    if (products.isEmpty) {
      return Center(
        child: Text('Sin productos en esta categoría',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15)),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: ListView.builder(
        key: ValueKey(catId),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: products.length,
        itemBuilder: (context, i) => _ProductTile(
          product: products[i],
          accentColor: _activeColor,
          onTap: () => context.push('/product-detail', extra: {
            'product': products[i],
            'restaurantId': widget.restaurant.id,
          }),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final Color accentColor;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  if (product.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${product.price.toStringAsFixed(0)} MXN',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: accentColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: product.imageUrl != null
                        ? Image.network(product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => _placeholder())
                        : _placeholder(),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppConstants.surface2Color,
        child: const Center(
          child: Icon(Icons.fastfood,
              size: 36, color: AppConstants.primaryColor),
        ),
      );
}
