import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/restaurant.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';

typedef _MenuSection = ({String name, String icon, List<Product> products});

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _pageController = PageController();
  int _currentTab = 0;

  // Location
  LocationResult? _locationResult;
  bool _checkingLocation = true;
  late Future<List<Restaurant>> _futureRestaurants;

  // Navigation state
  Restaurant? _restaurant;
  Future<List<_MenuSection>>? _futureMenu;
  Product? _product;

  static const _tabColors = [
    AppConstants.primaryColor,
    Color(0xFFFF6D00),
    Color(0xFF00BFA5),
  ];

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (SupabaseService.useMock) {
      setState(() {
        _locationResult = LocationResult(
          status: LocationStatus.enMaravatio,
          distanciaKm: 0.5,
        );
        _checkingLocation = false;
      });
      _futureRestaurants = SupabaseService.getRestaurants();
      return;
    }
    final result = await LocationService.verificarUbicacion();
    setState(() {
      _locationResult = result;
      _checkingLocation = false;
    });
    if (result.status == LocationStatus.enMaravatio) {
      _futureRestaurants = SupabaseService.getRestaurants();
    }
  }

  void _goToTab(int index) {
    if (index == _currentTab) return;
    if (index == 1 && _restaurant == null) return;
    if (index == 2 && _product == null) return;
    setState(() => _currentTab = index);
    _pageController.jumpToPage(index);
  }

  void _selectRestaurant(Restaurant r) {
    setState(() {
      _restaurant = r;
      _product = null;
      _futureMenu = SupabaseService.getMenuSections(r.id);
      _currentTab = 1;
    });
    _pageController.jumpToPage(1);
  }

  void _selectProduct(Product p) {
    setState(() {
      _product = p;
      _currentTab = 2;
    });
    _pageController.jumpToPage(2);
  }

  String _locationLabel() {
    if (_checkingLocation) return 'Detectando ubicación...';
    return switch (_locationResult?.status) {
      LocationStatus.enMaravatio => 'Maravatío, Mich.',
      _ => 'Ubicación no disponible',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;

    final tabLabels = [
      'Restaurantes',
      _restaurant?.name ?? 'Menú',
      _product?.name ?? 'Platillo',
    ];
    final tabIcons = [
      Icons.storefront_outlined,
      Icons.restaurant_menu_outlined,
      Icons.fastfood_outlined,
    ];
    final locked = [false, _restaurant == null, _product == null];

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grupo Fercadi',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            Row(
              children: [
                Icon(Icons.location_on,
                    size: 13, color: AppConstants.primaryColor),
                const SizedBox(width: 2),
                Text(
                  _locationLabel(),
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
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
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildRestaurantsPage(),
          _buildMenuPage(),
          _buildDetailPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: List.generate(3, (i) {
                final isActive = _currentTab == i;
                final isLocked = locked[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _goToTab(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? Colors.transparent
                            : isActive
                                ? _tabColors[i]
                                : _tabColors[i].withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tabIcons[i],
                            size: 22,
                            color: isLocked
                                ? Colors.white.withValues(alpha: 0.18)
                                : isActive
                                    ? Colors.white
                                    : _tabColors[i].withValues(alpha: 0.75),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tabLabels[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isLocked
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : isActive
                                      ? Colors.white
                                      : _tabColors[i].withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  // ── TAB 1: Restaurantes ──────────────────────────────────────────────────

  Widget _buildRestaurantsPage() {
    if (_checkingLocation) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppConstants.primaryColor),
            const SizedBox(height: 20),
            Text(
              'Detectando tu ubicación...',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_locationResult?.status != LocationStatus.enMaravatio) {
      return _buildFueraDeZona(_locationResult?.status);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar restaurantes...',
              hintStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              prefixIcon: Icon(Icons.search,
                  color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: AppConstants.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Restaurantes cerca de ti',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Restaurant>>(
            future: _futureRestaurants,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryColor));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white)),
                );
              }
              final restaurants = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: restaurants.length,
                itemBuilder: (context, i) => _RestaurantCard(
                  restaurant: restaurants[i],
                  onTap: () => _selectRestaurant(restaurants[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── TAB 2: Menú ──────────────────────────────────────────────────────────

  Widget _buildMenuPage() {
    if (_restaurant == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu,
                size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              'Selecciona un restaurante',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          color: AppConstants.surfaceColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _restaurant!.name,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              if (_restaurant!.address != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _restaurant!.address!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<_MenuSection>>(
            future: _futureMenu,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryColor));
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white)),
                );
              }
              final sections = snapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: sections.length,
                itemBuilder: (context, i) {
                  final section = sections[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Text(section.icon,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              section.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...section.products.map(
                        (p) => _ProductCard(
                          product: p,
                          onTap: () => _selectProduct(p),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── TAB 3: Detalle / Cobrar ──────────────────────────────────────────────

  Widget _buildDetailPage() {
    if (_product == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fastfood_outlined,
                size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              'Selecciona un platillo',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 16),
            ),
          ],
        ),
      );
    }

    final p = _product!;
    final cart = context.read<CartProvider>();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: p.imageUrl != null
                      ? Image.network(
                          p.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => _imgPlaceholder(),
                        )
                      : _imgPlaceholder(),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      if (p.description != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          p.description!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        '\$${p.price.toStringAsFixed(2)} MXN',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                if (_restaurant != null) {
                  cart.addProduct(p, _restaurant!.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${p.name} agregado al pedido'),
                      backgroundColor: AppConstants.primaryColor,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text(
                'Agregar al pedido  •  \$${p.price.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppConstants.surface2Color,
        child: const Center(
            child: Icon(Icons.fastfood,
                size: 80, color: AppConstants.primaryColor)),
      );

  Widget _buildFueraDeZona(LocationStatus? status) {
    final (icon, title, subtitle, canRetry) = switch (status) {
      LocationStatus.fueraDeMaravatio => (
          Icons.location_off_outlined,
          'Fuera de zona de servicio',
          'Solo operamos en el municipio de\nMaravatío, Mich.\n\nEstás a ${_locationResult?.distanciaKm?.toStringAsFixed(1)} km del centro.',
          false,
        ),
      LocationStatus.permisoDenegado ||
      LocationStatus.permisoDenegadoPermanente => (
          Icons.location_disabled_outlined,
          'Permiso de ubicación denegado',
          'Necesitamos acceder a tu ubicación\npara mostrarte restaurantes cercanos.',
          true,
        ),
      LocationStatus.servicioDesactivado => (
          Icons.gps_off_outlined,
          'GPS desactivado',
          'Activa tu GPS para que podamos\ndetectar si estás en Maravatío.',
          true,
        ),
      _ => (
          Icons.location_searching_outlined,
          'Ubicación no disponible',
          'No pudimos detectar tu ubicación.',
          true,
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 50, color: AppConstants.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.6),
              textAlign: TextAlign.center,
            ),
            if (canRetry) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _checkingLocation = true);
                  _initLocation();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Intentar de nuevo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;
  const _RestaurantCard({required this.restaurant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: restaurant.imageUrl != null
                    ? Image.network(restaurant.imageUrl!, fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => _placeholder())
                    : _placeholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        if (restaurant.address != null)
                          Text(
                            restaurant.address!,
                            style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.45),
                                fontSize: 13),
                          ),
                        if (restaurant.description != null)
                          Text(
                            restaurant.description!,
                            style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.6),
                                fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star,
                            color: AppConstants.primaryColor, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          restaurant.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppConstants.surface2Color,
        child: const Center(
            child: Icon(Icons.restaurant,
                size: 60, color: AppConstants.primaryColor)),
      );
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: BorderRadius.circular(12),
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
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${product.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: product.imageUrl != null
                    ? Image.network(product.imageUrl!, fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => _imgPlaceholder())
                    : _imgPlaceholder(),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: AppConstants.primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppConstants.surface2Color,
        child: const Center(
            child: Icon(Icons.fastfood,
                size: 30, color: AppConstants.primaryColor)),
      );
}
