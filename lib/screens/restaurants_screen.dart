import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../providers/app_data_provider.dart';
import '../providers/cart_provider.dart';
import '../services/location_service.dart';
import '../services/order_history_service.dart';
import '../services/supabase_service.dart';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});
  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  late Future<List<Restaurant>> _futureRestaurants;
  LocationResult? _locationResult;
  bool _checkingLocation = true;
  String  _displayName = '';
  String? _photoPath;

  // Restaurant accordion
  String? _expandedRestaurantId;
  final Map<String, int> _selCat = {};
  final Map<String, List<Category>> _cats = {};
  final Map<String, Map<String, List<Product>>> _prods = {};
  final Map<String, bool> _loadingMenu = {};


  // Product accordion
  String? _expandedProductId;
  final Map<String, int> _productQty = {};

  // Active order banner
  Map<String, dynamic>? _activeOrder;
  String _prevActiveStatus = '';
  Timer? _activeOrderTimer;

  static const _catColors = [
    AppConstants.primaryColor,
    Color(0xFFFF6D00),
    Color(0xFF00BFA5),
    Color(0xFF7C4DFF),
    Color(0xFF2196F3),
    Color(0xFFFFB300),
  ];

  @override
  void initState() {
    super.initState();
    _initLocation();
    AuthService.getDisplayName().then((n) {
      if (mounted) setState(() => _displayName = n);
    });
    AuthService.getProfilePhoto().then((p) {
      if (mounted) setState(() => _photoPath = p);
    });
    _checkActiveOrder();
    _activeOrderTimer = Timer.periodic(
      const Duration(seconds: 8), (_) => _checkActiveOrder());
  }

  @override
  void dispose() {
    _activeOrderTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveOrder() async {
    final order = await OrderHistoryService.getActiveOrder();
    if (!mounted) return;
    if (order == null) {
      if (_activeOrder != null) setState(() => _activeOrder = null);
      return;
    }
    final orderId = order['orderId'] as String;
    String status;
    try {
      status = await SupabaseService.getOrderStatus(orderId) ?? 'pending';
    } catch (_) {
      status = 'pending';
    }
    if (!mounted) return;
    if (status == 'delivered' || status == 'cancelled') {
      await OrderHistoryService.clearActiveOrder();
      setState(() => _activeOrder = null);
      return;
    }
    final prev = _prevActiveStatus;
    _prevActiveStatus = status;
    setState(() => _activeOrder = order);
    if (prev.isNotEmpty && prev != status) {
      if (status == 'delivering') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.delivery_dining, color: Colors.white),
            SizedBox(width: 8),
            Text('¡Tu repartidor está en camino!'),
          ]),
          backgroundColor: const Color(0xFF2196F3),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ));
      } else if (status == 'accepted') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.restaurant, color: Colors.white),
            SizedBox(width: 8),
            Text('Tu pedido fue aceptado, está siendo preparado'),
          ]),
          backgroundColor: AppConstants.primaryColor,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  bool _likesInited = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_likesInited) {
      _likesInited = true;
      context.read<AppDataProvider>().initProductLikes();
    }
  }

  Future<void> _initLocation() async {
    if (SupabaseService.useMock || kIsWeb) {
      setState(() {
        _locationResult = LocationResult(
            status: LocationStatus.enMaravatio, distanciaKm: 0.5);
        _checkingLocation = false;
      });
      _futureRestaurants = SupabaseService.getRestaurants();
      return;
    }
    try {
      final result = await LocationService.verificarUbicacion()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _locationResult = result;
        _checkingLocation = false;
      });
      if (result.status == LocationStatus.enMaravatio) {
        _futureRestaurants = SupabaseService.getRestaurants();
      }
    } catch (_) {
      // Timeout o error de GPS — dejar pasar para no bloquear al usuario
      if (!mounted) return;
      setState(() {
        _locationResult =
            LocationResult(status: LocationStatus.enMaravatio, distanciaKm: 0);
        _checkingLocation = false;
      });
      _futureRestaurants = SupabaseService.getRestaurants();
    }
  }

  Future<void> _loadMenu(String restaurantId) async {
    if (_cats.containsKey(restaurantId)) return;
    setState(() => _loadingMenu[restaurantId] = true);
    final cats = await SupabaseService.getCategories(restaurantId);
    final prods = <String, List<Product>>{};
    for (final cat in cats) {
      prods[cat.id] = await SupabaseService.getProducts(cat.id);
    }
    if (mounted) {
      setState(() {
        _cats[restaurantId] = cats;
        _prods[restaurantId] = prods;
        _loadingMenu[restaurantId] = false;
        _selCat[restaurantId] = 0;
      });
    }
  }

  void _toggleRestaurant(String id) {
    final opening = _expandedRestaurantId != id;
    setState(() {
      _expandedRestaurantId = opening ? id : null;
      _expandedProductId = null;
    });
    if (opening) _loadMenu(id);
  }

  void _toggleProduct(String productId) {
    setState(() {
      _expandedProductId =
          _expandedProductId == productId ? null : productId;
    });
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
    final appData  = context.watch<AppDataProvider>();
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppConstants.primaryColor,
        elevation: 0,
        centerTitle: true,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline, color: Colors.white.withValues(alpha: 0.8), size: 22),
            tooltip: 'Mi perfil',
            onPressed: () async {
              await context.push('/profile');
              final n = await AuthService.getDisplayName();
              final p = await AuthService.getProfilePhoto();
              if (mounted) setState(() { _displayName = n; _photoPath = p; });
            },
          ),
          IconButton(
            icon: Icon(Icons.receipt_long_outlined, color: Colors.white.withValues(alpha: 0.8), size: 22),
            tooltip: 'Mis pedidos',
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white.withValues(alpha: 0.8), size: 22),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final router = GoRouter.of(context);
              await AuthService.clearSession();
              router.go('/login');
            },
          ),
          Stack(clipBehavior: Clip.none, children: [
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
                      color: AppConstants.surfaceColor,
                      shape: BoxShape.circle),
                  child: Text('$cartCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
        ],
      ),
      body: Stack(children: [
        _checkingLocation ? _buildChecking() : _buildBody(appData),
        if (_activeOrder != null) _buildActiveOrderBanner(),
      ]),
    );
  }

  Widget _buildActiveOrderBanner() {
    final name = (_activeOrder!['restaurantName'] as String?) ?? 'Tu pedido';
    return Positioned(
      left: 16, right: 16, bottom: 16,
      child: GestureDetector(
        onTap: () => context.go('/tracking', extra: _activeOrder!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppConstants.primaryColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryColor.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            const Icon(Icons.delivery_dining, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pedido en curso',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text(name,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12)),
                ],
              ),
            ),
            const Text('Ver seguimiento',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildChecking() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: AppConstants.primaryColor),
          const SizedBox(height: 20),
          Text('Detectando tu ubicación...',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 16)),
        ]),
      );

  Widget _buildBody(AppDataProvider appData) {
    if (_locationResult?.status != LocationStatus.enMaravatio) {
      return _buildFueraDeZona(_locationResult?.status);
    }
    return FutureBuilder<List<Restaurant>>(
      future: _futureRestaurants,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: AppConstants.primaryColor));
        }
        final restaurants = snapshot.data ?? [];
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: restaurants.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(children: [
                  Center(
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: MediaQuery.of(context).size.width * 0.42,
                      fit: BoxFit.contain,
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_displayName.isNotEmpty)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (_photoPath != null)
                        Container(
                          width: 32, height: 32,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppConstants.surfaceColor,
                            border: Border.all(color: AppConstants.primaryColor, width: 1.5),
                          ),
                          child: ClipOval(child: _photoPath!.startsWith('http')
                            ? Image.network(_photoPath!, fit: BoxFit.cover, width: 32, height: 32,
                                errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white, size: 18))
                            : Image.file(File(_photoPath!), fit: BoxFit.cover, width: 32, height: 32,
                                errorBuilder: (_, e, s) => const Icon(Icons.person, color: Colors.white, size: 18))),
                        ),
                      Text(
                        'Hola, $_displayName 👋',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ]),
                ]),
              );
            }
            return _buildRestaurantTile(restaurants[i - 1], appData);
          },
        );
      },
    );
  }

  // ── Restaurant accordion tile ──────────────────────────────────────────

  Widget _buildRestaurantTile(Restaurant r, AppDataProvider appData) {
    final isExpanded = _expandedRestaurantId == r.id;
    final isLoading = _loadingMenu[r.id] == true;
    final cats = _cats[r.id] ?? [];
    final selIdx = _selCat[r.id] ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConstants.primaryColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            offset: const Offset(0, 8),
            blurRadius: 18,
          ),
        ],
        border: isExpanded
            ? Border.all(color: AppConstants.surfaceColor, width: 1.2)
            : null,
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => _toggleRestaurant(r.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.name,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              GestureDetector(
                onTap: () => context.read<AppDataProvider>().toggleLike(r.id).ignore(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: appData.isLikedByUser(r.id)
                        ? AppConstants.primaryColor
                        : AppConstants.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(
                      appData.isLikedByUser(r.id)
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${appData.getLikes(r.id)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down,
                    color: isExpanded
                        ? AppConstants.primaryColor
                        : Colors.white.withValues(alpha: 0.5),
                    size: 26),
              ),
            ]),
          ),
        ),
        if (isExpanded)
          Column(children: [
            const Divider(height: 1, color: AppConstants.surface2Color),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                    color: AppConstants.primaryColor),
              )
            else if (cats.isNotEmpty) ...[
              _buildCategoryTabs(r.id, cats, selIdx),
              _buildProducts(r, cats, selIdx, appData),
              const SizedBox(height: 8),
            ],
          ]),
      ]),
    );
  }

  // ── Category tabs ──────────────────────────────────────────────────────

  Widget _buildCategoryTabs(
      String restaurantId, List<Category> cats, int selIdx) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: List.generate(cats.length, (i) {
          final cat = cats[i];
          final color = _catColors[i % _catColors.length];
          final isSelected = selIdx == i;
          return GestureDetector(
            onTap: () => setState(() {
              _selCat[restaurantId] = i;
              _expandedProductId = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected
                        ? color
                        : color.withValues(alpha: 0.35),
                    width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (cat.icon != null)
                  Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Text(cat.icon!,
                          style: const TextStyle(fontSize: 14))),
                Text(cat.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: Colors.white)),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ── Product accordion list ─────────────────────────────────────────────

  Widget _buildProducts(
      Restaurant r, List<Category> cats, int selIdx, AppDataProvider appData) {
    final catId   = cats[selIdx].id;
    final accent  = AppConstants.primaryColor;
    final regular = (_prods[r.id]?[catId] ?? [])
        .where((p) => appData.getProductAvailability(p.id, p.isAvailable))
        .toList();
    final extras  = appData
        .extraProductsForCategory(r.id, catId)
        .where((p) => p.isAvailable)
        .toList();

    return Column(children: [
      ...regular.map((p) {
        final isExpanded = _expandedProductId == p.id;
        final qty = _productQty[p.id] ?? 1;
        return _buildProductTile(p, r.id, r.name, accent, isExpanded, qty);
      }),
      ...extras.map((p) {
        final isExpanded = _expandedProductId == p.id;
        final qty = _productQty[p.id] ?? 1;
        final asProduct = Product(
          id: p.id,
          categoryId: p.categoryId,
          name: p.name,
          description: p.description.isEmpty ? null : p.description,
          price: p.price,
          imageUrl: p.imagePath,
        );
        return _buildProductTile(asProduct, r.id, r.name, accent, isExpanded, qty);
      }),
    ]);
  }

  Widget _buildProductTile(Product p, String restaurantId, String restaurantName,
      Color accent, bool isExpanded, int qty) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: AppConstants.surface2Color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(0, 6),
            blurRadius: 12,
          ),
        ],
        border: isExpanded
            ? Border.all(color: AppConstants.primaryColor, width: 1.2)
            : null,
      ),
      child: Column(children: [
        // ── Product header row (always visible) ──
        GestureDetector(
          onTap: () => _toggleProduct(p.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _productImage(p.imageUrl, small: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(p.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryColor)),
                      if (p.description != null)
                        Text(p.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                          Colors.black.withOpacity(0.45))),
                      const SizedBox(height: 4),
                    Text('\$${p.price.toStringAsFixed(0)} MXN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryColor)),
                    ]),
              ),
              Consumer<AppDataProvider>(
                builder: (_, appData, _) {
                  final liked = appData.isProductLikedByUser(p.id);
                  final likes = appData.getProductLikes(p.id);
                  return GestureDetector(
                    onTap: () => appData.toggleProductLike(p.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                          color: liked ? AppConstants.primaryColor : Colors.black.withValues(alpha: 0.25),
                          size: 18,
                        ),
                        if (likes > 0) ...[
                          const SizedBox(width: 3),
                          Text('$likes',
                              style: TextStyle(
                                  color: liked ? AppConstants.primaryColor : Colors.black.withValues(alpha: 0.35),
                                  fontSize: 11)),
                        ],
                      ]),
                    ),
                  );
                },
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.keyboard_arrow_down,
                    color: isExpanded
                        ? accent
                        : Colors.white.withValues(alpha: 0.4),
                    size: 22),
              ),
            ]),
          ),
        ),

        // ── Expanded detail ──────────────────────────────────
        if (isExpanded)
          Column(children: [
            Divider(
                height: 1, color: accent.withValues(alpha: 0.3)),
            // Image grande
            SizedBox(
              height: 180,
              width: double.infinity,
              child: _productImage(p.imageUrl),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.description != null)
                      Text(p.description!,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              height: 1.5)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Text('\$${p.price.toStringAsFixed(0)} MXN',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: accent)),
                      const Spacer(),
                      // Quantity selector
                      Container(
                        decoration: BoxDecoration(
                            color: AppConstants.surfaceColor,
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () {
                              if (qty > 1) {
                                setState(
                                    () => _productQty[p.id] = qty - 1);
                              }
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              child: Icon(Icons.remove,
                                  color: Colors.white
                                      .withValues(alpha: qty > 1 ? 1 : 0.3),
                                  size: 18),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text('$qty',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _productQty[p.id] = qty + 1),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(8)),
                              alignment: Alignment.center,
                              child: const Icon(Icons.add,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          for (int i = 0; i < qty; i++) {
                            context
                                .read<CartProvider>()
                                .addProduct(p, restaurantId, restaurantName);
                          }
                          setState(() {
                            _expandedProductId = null;
                            _productQty[p.id] = 1;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('$qty× ${p.name} agregado al pedido'),
                              backgroundColor: accent,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text(
                          'Agregar al pedido  •  \$${(p.price * qty).toStringAsFixed(0)} MXN',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
            ),
          ]),
      ]),
    );
  }

  Widget _productImage(String? url, {bool small = false}) {
    final size = small ? 28.0 : 60.0;
    final placeholder = Container(
      color: AppConstants.surfaceColor,
      child: Center(child: Icon(Icons.fastfood, size: size, color: AppConstants.primaryColor)),
    );
    if (url == null) return placeholder;
    if (!kIsWeb && (url.startsWith('/') || url.startsWith('file:'))) {
      return Image.file(File(url), fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder);
    }
    return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder);
  }

  // ── Fuera de zona ──────────────────────────────────────────────────────

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
          'Activa tu GPS para detectar\nsi estás en Maravatío.',
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
                color: AppConstants.surfaceColor, shape: BoxShape.circle),
            child: Icon(icon, size: 50, color: AppConstants.primaryColor),
          ),
          const SizedBox(height: 24),
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.6),
              textAlign: TextAlign.center),
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
        ]),
      ),
    );
  }
}
