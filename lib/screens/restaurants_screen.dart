import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import 'map_picker_screen.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../providers/app_data_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/theme_provider.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/order_history_service.dart';
import '../services/supabase_service.dart';
import '../models/restaurant_banner.dart';

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
  final Set<String> _expandedIds = {};
  final Map<String, int> _selCat = {};
  final Map<String, List<Category>> _cats = {};
  final Map<String, Map<String, List<Product>>> _prods = {};
  final Map<String, bool> _loadingMenu = {};

  // Banners dinámicos por restaurante
  final Map<String, List<RestaurantBanner>> _banners = {};
  // productId → descuento% activo de banner
  final Map<String, int> _bannerDiscounts = {};


  // Product accordion
  String? _expandedProductId;
  final Map<String, int> _productQty = {};

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Restaurant>? _searchResults;
  Set<String> _productMatchIds = {};

  // Active order banner
  Map<String, dynamic>? _activeOrder;
  String _prevActiveStatus = '';
  Timer? _activeOrderTimer;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptLocationIfNeeded());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _activeOrderTimer?.cancel();
    super.dispose();
  }

  Future<void> _promptLocationIfNeeded() async {
    if (kIsWeb) return; // En web no hay mapa disponible
    final addresses = await AuthService.getSavedAddresses();
    if (!mounted || addresses.isNotEmpty) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: AppConstants.primaryColor, size: 38),
          ),
          const SizedBox(height: 18),
          const Text('¿Dónde te entregamos?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Text('Marca tu casa o lugar favorito en el mapa para que tus pedidos lleguen directo ahí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.5)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push<LatLng>(
                  context,
                  MaterialPageRoute(builder: (_) => const MapPickerScreen()),
                );
                if (result == null || !mounted) return;
                final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
                await AuthService.saveAddress(
                  label: 'Mi casa',
                  address: addr ?? '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}',
                  lat: result.latitude,
                  lng: result.longitude,
                );
              },
              icon: const Icon(Icons.map_outlined, size: 20),
              label: const Text('Ubicar mi casa en el mapa', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Ahora no',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
          ),
        ]),
      ),
    );
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
        NotificationService.repartidorEnCamino();
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
        NotificationService.pedidoAceptado();
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
        if (result.position != null) {
          LocationService.reverseGeocode(
            result.position!.latitude,
            result.position!.longitude,
          ).then((addr) {
            if (addr != null) {
              AuthService.saveAddress(
                label: 'Mi ubicación',
                address: addr,
                lat: result.position!.latitude,
                lng: result.position!.longitude,
              );
            }
          });
        }
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
    final results = await Future.wait([
      SupabaseService.getCategories(restaurantId),
      SupabaseService.getBanners(restaurantId),
    ]);
    if (!mounted) return;
    final cats = results[0] as List<Category>;
    final banners = results[1] as List<RestaurantBanner>;
    final prodLists = await Future.wait(cats.map((c) => SupabaseService.getProducts(c.id)));
    if (!mounted) return;
    final prods = <String, List<Product>>{
      for (var i = 0; i < cats.length; i++) cats[i].id: prodLists[i],
    };
    setState(() {
      _cats[restaurantId] = cats;
      _prods[restaurantId] = prods;
      _banners[restaurantId] = banners;
      _loadingMenu[restaurantId] = false;
      _selCat[restaurantId] = 0;
      for (final b in banners) {
        if (b.productId != null && b.isDiscountActive) {
          _bannerDiscounts[b.productId!] = b.discountPercent!;
        }
      }
    });
  }

  void _jumpToProduct(String restaurantId, String productId) {
    final cats = _cats[restaurantId] ?? [];
    final prods = _prods[restaurantId] ?? {};
    for (int i = 0; i < cats.length; i++) {
      if ((prods[cats[i].id] ?? []).any((p) => p.id == productId)) {
        setState(() {
          _selCat[restaurantId] = i;
          _expandedProductId = productId;
        });
        return;
      }
    }
  }

  void _toggleRestaurant(String id) {
    final opening = !_expandedIds.contains(id);
    setState(() {
      if (opening) _expandedIds.add(id); else _expandedIds.remove(id);
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

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;
    final appData  = context.watch<AppDataProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        // ── Usuario a la izquierda ───────────────────────────────────────────
        leading: GestureDetector(
          onTap: () async {
            await context.push('/profile');
            final n = await AuthService.getDisplayName();
            final p = await AuthService.getProfilePhoto();
            if (mounted) setState(() { _displayName = n; _photoPath = p; });
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _photoPath != null
                ? ClipOval(
                    child: _photoPath!.startsWith('http')
                        ? Image.network(_photoPath!, fit: BoxFit.cover, width: 36, height: 36,
                            errorBuilder: (_, __, ___) => _defaultAvatar())
                        : Image.file(File(_photoPath!), fit: BoxFit.cover, width: 36, height: 36,
                            errorBuilder: (_, __, ___) => _defaultAvatar()))
                : _defaultAvatar(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('GOGO FOOD',
                style: TextStyle(
                    color: isDark ? AppConstants.primaryColor : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            if (_displayName.isNotEmpty)
              Text('Hola, $_displayName',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11)),
          ],
        ),
        // ── Carrito + menú 3 líneas a la derecha ────────────────────────────
        actions: [
          Stack(clipBehavior: Clip.none, children: [
            _appBarIconButton(
              icon: Icons.shopping_bag_outlined,
              isDark: isDark,
              onTap: () => context.push('/cart'),
            ),
            if (cartCount > 0)
              Positioned(
                right: 4, top: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: isDark ? AppConstants.primaryColor : Colors.white,
                      shape: BoxShape.circle),
                  child: Text('$cartCount',
                      style: TextStyle(
                          color: isDark ? Colors.white : AppConstants.primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
          _appBarIconButton(
            icon: Icons.menu,
            isDark: isDark,
            onTap: _showSideMenu,
          ),
          const SizedBox(width: 4),
        ],
      ),
      // ── Barra de carrito fija abajo ──────────────────────────────────────
      bottomNavigationBar: (cartCount > 0 || _activeOrder != null)
          ? _buildBottomArea(cartCount, context.read<CartProvider>())
          : null,
      body: _checkingLocation ? _buildChecking(isDark) : _buildBody(appData, isDark),
    );
  }

  Widget _buildActiveOrderBannerInline() {
    final name = (_activeOrder!['restaurantName'] as String?) ?? 'Tu pedido';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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

  // ── Avatar por defecto ───────────────────────────────────────────────────
  Widget _defaultAvatar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CircleAvatar(
      radius: 18,
      backgroundColor: isDark
          ? AppConstants.primaryColor.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.9),
      child: Icon(Icons.person,
          color: AppConstants.primaryColor, size: 20),
    );
  }

  // ── Botón de AppBar (fondo blanco en modo claro, transparente en oscuro) ─
  Widget _appBarIconButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    if (isDark) {
      return IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppConstants.primaryColor, size: 22),
      ),
    );
  }

  // ── Menú lateral (3 líneas) ───────────────────────────────────────────────
  void _showSideMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppConstants.surfaceColor : AppConstants.primaryColor;
    final textColor = Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white30, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(Icons.person_outline, color: isDark ? AppConstants.primaryColor : Colors.white),
          title: Text('Mi perfil', style: TextStyle(color: textColor)),
          onTap: () { Navigator.pop(context); context.push('/profile'); },
        ),
        ListTile(
          leading: Icon(Icons.receipt_long_outlined, color: isDark ? AppConstants.primaryColor : Colors.white),
          title: Text('Mis pedidos', style: TextStyle(color: textColor)),
          onTap: () { Navigator.pop(context); context.push('/history'); },
        ),
        Consumer<ThemeProvider>(
          builder: (ctx, theme, child) {
            return SwitchListTile(
              secondary: Icon(
                theme.isDark ? Icons.dark_mode : Icons.light_mode,
                color: isDark ? AppConstants.primaryColor : Colors.white,
              ),
              title: Text(
                theme.isDark ? 'Modo oscuro' : 'Modo claro',
                style: TextStyle(color: textColor),
              ),
              value: theme.isDark,
              activeThumbColor: isDark ? AppConstants.primaryColor : Colors.white,
              inactiveThumbColor: Colors.white70,
              onChanged: (_) => theme.toggle(),
            );
          },
        ),
        Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
        ListTile(
          leading: Icon(Icons.logout, color: isDark ? Colors.redAccent : Colors.white70),
          title: Text('Cerrar sesión',
              style: TextStyle(color: isDark ? Colors.redAccent : Colors.white70)),
          onTap: () async {
            Navigator.pop(context);
            final router = GoRouter.of(context);
            await AuthService.clearSession();
            router.go('/login');
          },
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ── Área inferior: pedido activo + barra de carrito ───────────────────────
  Widget _buildBottomArea(int cartCount, CartProvider cart) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_activeOrder != null) _buildActiveOrderBannerInline(),
      if (cartCount > 0)
        Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: SafeArea(
            child: ElevatedButton(
              onPressed: () => context.push('/cart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C98F5),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: const StadiumBorder(),
                elevation: 4,
                shadowColor: const Color(0xFF0C98F5).withValues(alpha: 0.5),
              ),
              child: Row(children: [
                Text('$cartCount/U',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white)),
                const SizedBox(width: 8),
                const Text('•', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Center(
                    child: Text('REALIZAR PEDIDO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5)),
                  ),
                ),
                const Text('•', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 8),
                Text('\$${cart.total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _buildChecking(bool isDark) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(
              color: isDark ? AppConstants.primaryColor : Colors.white),
          const SizedBox(height: 20),
          Text('Detectando tu ubicación...',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 16)),
        ]),
      );

  Widget _buildBody(AppDataProvider appData, bool isDark) {
    if (_locationResult?.status != LocationStatus.enMaravatio) {
      return _buildFueraDeZona(_locationResult?.status);
    }
    return FutureBuilder<List<Restaurant>>(
      future: _futureRestaurants,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                  color: isDark ? AppConstants.primaryColor : Colors.white));
        }
        final all = snapshot.data ?? [];
        final restaurants = _searchQuery.isEmpty
            ? all
            : (_searchResults ?? all.where((r) => r.name.toLowerCase().contains(_searchQuery)).toList());
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
                      colorFilter: ColorFilter.mode(
                          Theme.of(context).brightness == Brightness.dark
                              ? AppConstants.primaryColor
                              : Colors.white,
                          BlendMode.srcIn),
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
                  const SizedBox(height: 20),
                  // ── Buscador ────────────────────────────────────────────
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) async {
                      final q = v.trim().toLowerCase();
                      setState(() { _searchQuery = q; _searchResults = null; });
                      if (q.isEmpty) return;
                      final all = await _futureRestaurants;
                      final result = await SupabaseService.searchByQuery(q, all);
                      if (!mounted || _searchQuery != q) return;
                      setState(() {
                        _searchResults = result.restaurants;
                        _productMatchIds = result.productRestaurantIds;
                        // Auto-expandir restaurantes que tienen un platillo que coincide
                        for (final rid in result.productRestaurantIds) {
                          _expandedIds.add(rid);
                        }
                      });
                      // Cargar menú de los que aún no lo tienen
                      for (final rid in result.productRestaurantIds) {
                        if (!_cats.containsKey(rid)) _loadMenu(rid);
                      }
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Busca un restaurante o platillo...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 22),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  for (final rid in _productMatchIds) { _expandedIds.remove(rid); }
                                  _searchQuery = ''; _searchResults = null; _productMatchIds = {};
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.18),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white54, width: 1),
                      ),
                    ),
                  ),
                ]),
              );
            }
            if (restaurants.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    'No se encontró "$_searchQuery"',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                ),
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
    final isExpanded = _expandedIds.contains(r.id);
    final isLoading = _loadingMenu[r.id] == true;
    final cats = _cats[r.id] ?? [];
    final selIdx = _selCat[r.id] ?? 0;
    const headerColor = AppConstants.primaryColor;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(isExpanded ? 0 : 12),
      bottomRight: Radius.circular(isExpanded ? 0 : 12),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 6),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(children: [
        // ── Banda del nombre ──────────────────────────────────────────────
        GestureDetector(
          onTap: () => _toggleRestaurant(r.id),
          child: Container(
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: borderRadius,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(
                child: Text(r.name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              GestureDetector(
                onTap: () => context.read<AppDataProvider>().toggleLike(r.id).ignore(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(
                      appData.isLikedByUser(r.id) ? Icons.thumb_up : Icons.thumb_up_outlined,
                      color: Colors.white, size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text('${appData.getLikes(r.id)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
          ),
        ),

        // ── Logo circular + estado (solo visible cuando está expandido) ─────
        if (isExpanded) GestureDetector(
          onTap: () => _toggleRestaurant(r.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.hardEdge,
                child: r.imageUrl != null && r.imageUrl!.isNotEmpty
                    ? Image.network(r.imageUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, e, s) =>
                            const Icon(Icons.storefront_rounded, size: 28, color: Colors.grey))
                    : const Icon(Icons.storefront_rounded, size: 28, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Row(children: [
                Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: r.isOpen ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  r.isOpen ? 'Abierto' : 'Cerrado',
                  style: TextStyle(
                    color: r.isOpen ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ]),
              const Spacer(),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down,
                    color: Colors.grey.shade500, size: 26),
              ),
            ]),
          ),
        ),

        // ── Contenido expandido ───────────────────────────────────────────
        if (isExpanded)
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(children: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (cats.isNotEmpty) ...[
                _buildPromoBanner(r),
                _buildCategoryTabs(r.id, cats, selIdx),
                _buildProducts(r, cats, selIdx, appData),
                const SizedBox(height: 8),
              ],
            ]),
          ),
      ]),
    );
  }

  // ── Promo carousel ────────────────────────────────────────────────────

  Widget _buildPromoBanner(Restaurant r) {
    final realBanners = _banners[r.id] ?? [];
    if (realBanners.isNotEmpty) {
      return _PromoCarousel(slides: realBanners.map((b) => _PromoSlide(
        image: b.imageUrl,
        badge: b.badge,
        title: b.title,
        subtitle: b.subtitle,
        badgeColor: b.badgeColor,
        onTap: b.productId != null ? () => _jumpToProduct(r.id, b.productId!) : null,
      )).toList());
    }
    // Sin banners en BD → generar slides desde los productos reales del restaurante
    final allProds = (_prods[r.id] ?? {}).values.expand((list) => list).toList();
    final withImage = allProds.where((p) => p.imageUrl != null && p.imageUrl!.isNotEmpty).toList();
    if (withImage.isNotEmpty) {
      final picks = (withImage..shuffle()).take(3).toList();
      final badgeColors = [const Color(0xFFE53935), const Color(0xFF43A047), const Color(0xFF1E88E5)];
      return _PromoCarousel(slides: List.generate(picks.length, (i) {
        final p = picks[i];
        return _PromoSlide(
          image: p.imageUrl!,
          badge: 'ESPECIAL',
          title: p.name,
          subtitle: p.description ?? r.name,
          badgeColor: badgeColors[i % badgeColors.length],
          onTap: () => _jumpToProduct(r.id, p.id),
        );
      }));
    }

    final name = r.name.toLowerCase();
    final List<_PromoSlide> slides;

    if (name.contains('hot dog') || name.contains('hotdog') || name.contains('sonora')) {
      slides = [
        const _PromoSlide(image: 'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=700&h=220&fit=crop', badge: 'ESPECIAL', title: 'Hot Dogs estilo Sonora', subtitle: 'Los mejores de Maravatío', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.pexels.com/photos/4518641/pexels-photo-4518641.jpeg?auto=compress&cs=tinysrgb&w=700&h=220&fit=crop', badge: '30 min', title: 'Entrega rápida', subtitle: 'Directo a tu puerta', badgeColor: Color(0xFF1E88E5)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=700&h=220&fit=crop&q=80', badge: 'NUEVO', title: 'Lo más pedido', subtitle: 'Prueba nuestras especialidades', badgeColor: Color(0xFF43A047)),
      ];
    } else if (name.contains('nieve') || name.contains('paleta') || name.contains('helado')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1501443762994-82bd5dace89a?w=700&h=220&fit=crop&q=80', badge: 'FRÍO', title: 'Nieves artesanales', subtitle: 'Más de 20 sabores disponibles', badgeColor: Color(0xFF1E88E5)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1559181567-c3190ca9959b?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Nieve de limón', subtitle: 'Refrescante y deliciosa', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1488900128323-21503983a07e?w=700&h=220&fit=crop&q=80', badge: 'PALETAS', title: 'Paletas artesanales', subtitle: 'Sabores únicos', badgeColor: Color(0xFFE53935)),
      ];
    } else if (name.contains('taco') || name.contains('chuy') || name.contains('taquer')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1624726175512-19b9baf9fbd1?w=700&h=220&fit=crop&q=80', badge: 'HOY', title: 'Tacos al pastor', subtitle: 'Recién llegados del trompo', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Tacos de bistec', subtitle: 'Jugosos y bien sazonados', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Quesadillas', subtitle: 'Con queso que se derrite', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('carnita')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504544750208-dc0358e63f7f?w=700&h=220&fit=crop&q=80', badge: 'CLÁSICO', title: 'Carnitas estilo Michoacán', subtitle: 'Receta tradicional de la región', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1529543544282-ea669407fca3?w=700&h=220&fit=crop&q=80', badge: 'POPULAR', title: 'Lo más pedido', subtitle: 'Surtida, maciza, buche y más', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Directo a tu puerta', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('birria')) {
      slides = [
        const _PromoSlide(image: 'https://images.pexels.com/photos/7613568/pexels-photo-7613568.jpeg?auto=compress&cs=tinysrgb&w=700&h=220&fit=crop', badge: 'ESPECIAL', title: 'Birria estilo Jalisco', subtitle: 'Con consomé bien sazonado', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.pexels.com/photos/6896379/pexels-photo-6896379.jpeg?auto=compress&cs=tinysrgb&w=700&h=220&fit=crop', badge: 'CALIENTE', title: 'Plato de birria', subtitle: 'Tradición michoacana', badgeColor: Color(0xFFFF6F00)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1547592180-85f173990554?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Consomé extra', subtitle: 'El mejor para los días fríos', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('pizza')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Pizzas artesanales', subtitle: 'Masa delgada y crujiente', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=700&h=220&fit=crop&q=80', badge: 'NUEVA', title: 'Lo más pedido', subtitle: 'Ingredientes frescos', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Directo a tu puerta', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('marisco') || name.contains('pescado') || name.contains('seafood')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=700&h=220&fit=crop&q=80', badge: 'FRESCO', title: 'Camarones del día', subtitle: 'Traídos diariamente del mar', badgeColor: Color(0xFF1E88E5)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1510130387422-82bed34b37e9?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Filetes de pescado', subtitle: 'A la plancha o empanizados', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Mariscos a tu puerta', subtitle: 'Frescos y bien sazonados', badgeColor: Color(0xFFE53935)),
      ];
    } else if (name.contains('torta')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1639667911189-700bd2029f5b?w=700&h=220&fit=crop&q=80', badge: 'CLÁSICA', title: 'Torta de pierna', subtitle: 'Con aguacate, frijoles y jalapeño', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1702119614788-bae35a7be313?w=700&h=220&fit=crop&q=80', badge: 'POPULAR', title: 'Torta de milanesa', subtitle: 'Empanizada y bien cargada', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1642694325494-9b3c23b80cc3?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Torta cubana', subtitle: 'Jamón, queso, pierna y chorizo', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('wok') || name.contains('chino') || name.contains('china') || name.contains('oriental')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=700&h=220&fit=crop&q=80', badge: 'WOK', title: 'Arroz frito especial', subtitle: 'Receta de la casa', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1555126634-323283e090fa?w=700&h=220&fit=crop&q=80', badge: 'POPULAR', title: 'Chow mein', subtitle: 'Fideos salteados al estilo oriental', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=700&h=220&fit=crop&q=80', badge: 'DULCE', title: 'Pollo agridulce', subtitle: 'Clásico oriental irresistible', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('alita') || name.contains('wings')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=700&h=220&fit=crop&q=80', badge: 'HOT', title: 'Alitas picosas', subtitle: 'Para los que les gusta el calor', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?w=700&h=220&fit=crop&q=80', badge: 'BBQ', title: 'Alitas BBQ', subtitle: 'Ahumadas y bien glaseadas', badgeColor: Color(0xFFFF6F00)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Alitas bien calientes a tu puerta', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('pollo') || name.contains('chicken')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?w=700&h=220&fit=crop&q=80', badge: 'CRUJIENTE', title: 'Pollo frito', subtitle: 'Receta secreta de la casa', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Pollo asado', subtitle: 'Dorado y bien sazonado', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Directo a tu puerta', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('pastel') || name.contains('dulc') || name.contains('postre') || name.contains('café') || name.contains('cafe')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=700&h=220&fit=crop&q=80', badge: 'DELICIA', title: 'Pasteles artesanales', subtitle: 'Decorados con amor', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Tres leches', subtitle: 'El postre favorito de todos', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=700&h=220&fit=crop&q=80', badge: 'CAFÉ', title: 'Café premium', subtitle: 'El mejor acompañante', badgeColor: Color(0xFF1E88E5)),
      ];
    } else if (name.contains('sushi') || name.contains('roll') || name.contains('japon')) {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1553621042-f6e147245754?w=700&h=220&fit=crop&q=80', badge: 'FRESCO', title: 'California Roll', subtitle: 'Camarón, aguacate y pepino', badgeColor: Color(0xFF1E88E5)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=700&h=220&fit=crop&q=80', badge: 'ESPECIAL', title: 'Lo más pedido', subtitle: 'Rolls premium de la casa', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Sushi directo a tu puerta', badgeColor: Color(0xFFE53935)),
      ];
    } else {
      slides = [
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=700&h=220&fit=crop&q=80', badge: '20% OFF', title: '¡Oferta del día!', subtitle: 'Solo por tiempo limitado', badgeColor: Color(0xFFE53935)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=700&h=220&fit=crop&q=80', badge: 'NUEVO', title: 'Lo más pedido', subtitle: 'Prueba nuestras especialidades', badgeColor: Color(0xFF43A047)),
        const _PromoSlide(image: 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=700&h=220&fit=crop&q=80', badge: '30 min', title: 'Entrega rápida', subtitle: 'Directo a tu puerta', badgeColor: Color(0xFF1E88E5)),
      ];
    }
    return _PromoCarousel(slides: slides);
  }

  // ── Category tabs ──────────────────────────────────────────────────────

  static IconData _categoryIcon(String name, String? emoji) {
    final key = name.toLowerCase();
    if (key.contains('hambur') || key.contains('burger'))  return Icons.lunch_dining;
    if (key.contains('papa')  || key.contains('frita'))    return Icons.set_meal;
    if (key.contains('bebida')|| key.contains('drink'))    return Icons.local_drink;
    if (key.contains('postre')|| key.contains('dulce') || key.contains('helado')) return Icons.icecream;
    if (key.contains('ensalada') || key.contains('vegano')) return Icons.eco;
    if (key.contains('desayuno') || key.contains('breakfast')) return Icons.breakfast_dining;
    if (key.contains('café') || key.contains('cafe') || key.contains('coffee')) return Icons.coffee;
    if (key.contains('frappé')|| key.contains('frappe')|| key.contains('smoothie')) return Icons.local_cafe;
    if (key.contains('pizza'))                             return Icons.local_pizza;
    if (key.contains('pollo') || key.contains('chicken'))  return Icons.egg_alt;
    if (key.contains('taco')  || key.contains('burritos')) return Icons.wrap_text;
    if (key.contains('sushi') || key.contains('roll'))     return Icons.set_meal;
    if (key.contains('entrada')|| key.contains('snack'))   return Icons.tapas;
    if (key.contains('comida')|| key.contains('platillo'))  return Icons.restaurant;
    if (key.contains('carne') || key.contains('asado'))    return Icons.outdoor_grill;
    if (key.contains('mariscos') || key.contains('pesca')) return Icons.water;
    if (key.contains('pasta') || key.contains('sopa'))     return Icons.ramen_dining;
    if (key.contains('sandwich')|| key.contains('torta'))  return Icons.brunch_dining;
    return Icons.restaurant_menu;
  }

  Widget _buildCategoryTabs(
      String restaurantId, List<Category> cats, int selIdx) {
    return _CategoryTabsRow(
      restaurantId: restaurantId,
      cats: cats,
      selIdx: selIdx,
      onSelect: (i) => setState(() {
        _selCat[restaurantId] = i;
        _expandedProductId = null;
      }),
      categoryIcon: _categoryIcon,
    );
  }

  // ── Product accordion list ─────────────────────────────────────────────

  Widget _buildProducts(
      Restaurant r, List<Category> cats, int selIdx, AppDataProvider appData) {
    const accent  = Color(0xFFF4510C);

    // Si hay búsqueda activa y este restaurante matcheó por platillo,
    // mostrar todos los productos de todas las categorías que coincidan
    final isProductSearch = _searchQuery.isNotEmpty && _productMatchIds.contains(r.id);
    if (isProductSearch) {
      final allMatching = <Product>[];
      for (final cat in cats) {
        for (final p in (_prods[r.id]?[cat.id] ?? [])) {
          if (appData.getProductAvailability(p.id, p.isAvailable) &&
              p.name.toLowerCase().contains(_searchQuery)) {
            allMatching.add(p);
          }
        }
      }
      if (allMatching.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Text('Cargando platillos...', style: TextStyle(color: Colors.grey))),
        );
      }
      return Column(children: [
        ...allMatching.map((p) {
          final isExp = _expandedProductId == p.id;
          final qty = _productQty[p.id] ?? 1;
          return _buildProductTile(p, r.id, r.name, accent, isExp, qty, isPromo: false, bannerDiscount: _bannerDiscounts[p.id]);
        }),
        const SizedBox(height: 8),
      ]);
    }

    final catId   = cats[selIdx].id;
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
        final bd = _bannerDiscounts[p.id];
        return _buildProductTile(p, r.id, r.name, accent, isExpanded, qty, isPromo: p.isPromoActive, bannerDiscount: bd);
      }),
      ...extras.map((p) {
        final isExpanded = _expandedProductId == p.id;
        final qty = _productQty[p.id] ?? 1;
        final asProduct = Product(
          id: p.id,
          categoryId: p.categoryIds.first,
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
      Color accent, bool isExpanded, int qty, {bool isPromo = false, int? bannerDiscount}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useOrange = isPromo || isDark || bannerDiscount != null;
    final tileColor = useOrange ? const Color(0xFFF4510C) : const Color(0xFFF2F2F2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
        border: null,
      ),
      child: Column(children: [
        // ── Product header row (solo visible cuando está colapsado) ──
        if (!isExpanded) GestureDetector(
          onTap: () => _toggleProduct(p.id),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 100,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Imagen izquierda ~42%
              Flexible(
                flex: 42,
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                    child: ColoredBox(color: tileColor, child: const SizedBox.expand()),
                  ),
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                    child: _productImage(p.imageUrl, small: true),
                  ),
                  // Solo degradado derecho
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            tileColor.withValues(alpha: 0),
                            tileColor.withValues(alpha: 0),
                            tileColor.withValues(alpha: 0.7),
                            tileColor,
                          ],
                          stops: const [0.0, 0.30, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              // Texto central
              Flexible(
                flex: 58,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Badges de promo
                      if (isPromo) ...[
                        Wrap(
                          spacing: 4,
                          children: [
                            if (p.promoDiscountPercent != null)
                              _PromoBadge('-${p.promoDiscountPercent}%'),
                            if (p.promoIs2x1)
                              _PromoBadge('2x1'),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (p.promoExpiresAt != null)
                          _PromoCountdown(expiresAt: p.promoExpiresAt!),
                        const SizedBox(height: 3),
                      ],
                      Text(p.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: useOrange ? Colors.white : const Color(0xFFF4510C))),
                      if (p.description != null) ...[
                        const SizedBox(height: 3),
                        Text(p.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: useOrange
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : Colors.black45)),
                      ],
                      const SizedBox(height: 5),
                      if (bannerDiscount != null) ...[
                        _PromoBadge('-$bannerDiscount%'),
                        const SizedBox(height: 3),
                      ],
                      if (isPromo && p.promoDiscountPercent != null) ...[
                        Text('\$${p.price.toStringAsFixed(0)} MXN',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.65),
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.white70)),
                        Text('\$${p.promoPrice.toStringAsFixed(0)} MXN',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ] else if (bannerDiscount != null) ...[
                        Text('\$${p.price.toStringAsFixed(0)} MXN',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.65),
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.white70)),
                        Text('\$${(p.price * (1 - bannerDiscount / 100)).toStringAsFixed(0)} MXN',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ] else
                        Text('\$${p.price.toStringAsFixed(0)} MXN',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: useOrange ? Colors.white : const Color(0xFFF4510C))),
                    ],
                  ),
                ),
              ),
              // Like + flecha a la derecha
              Padding(
                padding: const EdgeInsets.only(right: 6, left: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Consumer<AppDataProvider>(
                    builder: (_, appData, _) {
                      final liked = appData.isProductLikedByUser(p.id);
                      final likes = appData.getProductLikes(p.id);
                      return GestureDetector(
                        onTap: () => appData.toggleProductLike(p.id),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                            color: useOrange
                                ? Colors.white.withValues(alpha: liked ? 1 : 0.6)
                                : (liked ? accent : Colors.black26),
                            size: 18,
                          ),
                          if (likes > 0) ...[
                            const SizedBox(width: 3),
                            Text('$likes',
                                style: TextStyle(
                                    color: useOrange
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : (liked ? accent : Colors.black38),
                                    fontSize: 11)),
                          ],
                        ]),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down,
                        color: useOrange
                            ? Colors.white.withValues(alpha: 0.9)
                            : (isExpanded ? accent : Colors.black38),
                        size: 22),
                  ),
                ]),
              ),
            ]),
          ),
        ),

        // ── Expanded detail ──────────────────────────────────
        if (isExpanded)
          Column(children: [
            // Header naranja con nombre y like — tap para cerrar
            GestureDetector(
              onTap: () => _toggleProduct(p.id),
              child: Container(
              color: accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
                Consumer<AppDataProvider>(
                  builder: (_, appData, _) {
                    final liked = appData.isProductLikedByUser(p.id);
                    return GestureDetector(
                      onTap: () => appData.toggleProductLike(p.id),
                      child: Icon(
                        liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        color: Colors.white.withValues(alpha: liked ? 1 : 0.6),
                        size: 20,
                      ),
                    );
                  },
                ),
              ]),
            ),
            ), // cierre GestureDetector
            // Imagen completa con marco redondeado y tamaño estándar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                      ? Image.network(
                          p.imageUrl!,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        )
                      : const Center(child: Icon(Icons.fastfood, size: 60, color: Colors.black12)),
                ),
              ),
            ),
            // Descripción, precio, cantidad, botón — fondo blanco
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p.description != null)
                  Text(p.description!,
                      style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (bannerDiscount != null || (isPromo && p.promoDiscountPercent != null))
                      Text('\$${p.price.toStringAsFixed(0)} MXN',
                          style: TextStyle(
                              fontSize: 13, color: Colors.black38,
                              decoration: TextDecoration.lineThrough)),
                    Text('\$${(() {
                      if (isPromo && p.promoDiscountPercent != null) return p.promoPrice;
                      if (bannerDiscount != null) return p.price * (1 - bannerDiscount / 100);
                      return p.price;
                    })().toStringAsFixed(0)} MXN',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent)),
                  ]),
                  const Spacer(),
                  // Selector cantidad
                  Row(children: [
                    GestureDetector(
                      onTap: () {
                        if (qty > 1) setState(() => _productQty[p.id] = qty - 1);
                      },
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Icon(Icons.remove,
                            color: qty > 1 ? Colors.black87 : Colors.black26, size: 18),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('$qty',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _productQty[p.id] = qty + 1),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: accent, borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: const Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    ),
                  ]),
                ]),
                const SizedBox(height: 14),
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: const StadiumBorder(),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      final cart = context.read<CartProvider>();
                      // Si hay items de otro restaurante, pedir confirmación
                      if (cart.restaurantId != null && cart.restaurantId != restaurantId) {
                        final cambiar = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppConstants.surfaceColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('¿Cambiar restaurante?',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            content: Text(
                              'Tienes productos de ${cart.restaurantName} en tu carrito.\n\n¿Quieres vaciarlo y pedir de $restaurantName?',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: accent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Sí, cambiar', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (cambiar != true || !mounted) return;
                      }
                      final effectiveProduct = (bannerDiscount != null && !isPromo)
                          ? Product(
                              id: p.id, categoryId: p.categoryId, name: p.name,
                              description: p.description,
                              price: p.price * (1 - bannerDiscount / 100),
                              imageUrl: p.imageUrl, isAvailable: p.isAvailable)
                          : p;
                      for (int i = 0; i < qty; i++) {
                        context.read<CartProvider>().addProduct(effectiveProduct, restaurantId, restaurantName);
                      }
                      setState(() {
                        _expandedProductId = null;
                        _productQty[p.id] = 1;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('$qty× ${p.name} agregado al pedido'),
                        backgroundColor: accent,
                        duration: const Duration(seconds: 2),
                      ));
                    },
                    child: Text(
                      'Agregar Pedido  •  \$${(p.price * qty).toStringAsFixed(0)} MXN',
                      style: const TextStyle(
                          fontSize: 15,
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
    if (url != null && url.isNotEmpty && !url.startsWith('/') && !url.startsWith('file:')) {
      return SizedBox.expand(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox.expand(),
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.fastfood, size: size,
                color: const Color(0xFFF4510C).withValues(alpha: 0.3))),
        ),
      );
    }
    if (url != null && !kIsWeb && url.startsWith('/')) {
      return SizedBox.expand(
        child: Image.file(File(url), fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(Icons.fastfood, size: size,
                  color: const Color(0xFFF4510C).withValues(alpha: 0.3)))),
      );
    }
    return Center(child: Icon(Icons.fastfood, size: size,
        color: const Color(0xFFF4510C).withValues(alpha: 0.3)));
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
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
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

// ── Tabs de categorías con indicador de scroll ───────────────────────────────

class _CategoryTabsRow extends StatefulWidget {
  final String restaurantId;
  final List<Category> cats;
  final int selIdx;
  final void Function(int) onSelect;
  final IconData Function(String, String?) categoryIcon;

  const _CategoryTabsRow({
    required this.restaurantId,
    required this.cats,
    required this.selIdx,
    required this.onSelect,
    required this.categoryIcon,
  });

  @override
  State<_CategoryTabsRow> createState() => _CategoryTabsRowState();
}

class _CategoryTabsRowState extends State<_CategoryTabsRow> {
  late final ScrollController _scrollCtrl;
  double _scrollFraction = 0.0;
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    setState(() {
      _canScroll = max > 0;
      _scrollFraction = max > 0 ? (_scrollCtrl.offset / max) : 0.0;
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showIndicator = _canScroll;
    return Column(children: [
      SingleChildScrollView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: List.generate(widget.cats.length, (i) {
            final cat = widget.cats[i];
            final isSelected = widget.selIdx == i;
            final bgColor = isSelected
                ? const Color(0xFFF4510C)
                : Colors.white;
            final fgColor = isSelected
                ? Colors.white
                : const Color(0xFFF4510C);

            return GestureDetector(
              onTap: () => widget.onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isSelected ? null : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      offset: const Offset(0, 2),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.categoryIcon(cat.name, cat.icon),
                      color: fgColor, size: 15),
                  const SizedBox(width: 5),
                  Text(cat.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: fgColor)),
                ]),
              ),
            );
          }),
        ),
      ),
      if (showIndicator)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: LayoutBuilder(builder: (_, constraints) {
            final trackW = constraints.maxWidth;
            final thumbW = (trackW * 0.35).clamp(40.0, trackW);
            final thumbX = _scrollFraction * (trackW - thumbW);
            return Stack(children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D0D0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Positioned(
                left: thumbX,
                child: Container(
                  width: thumbW,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4510C),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ]);
          }),
        ),
    ]);
  }
}

// ── Modelo de slide promocional ───────────────────────────────────────────────

class _PromoSlide {
  final String image;
  final String badge;
  final String title;
  final String subtitle;
  final Color badgeColor;
  final VoidCallback? onTap;
  const _PromoSlide({
    required this.image,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.badgeColor,
    this.onTap,
  });
}

// ── Carrusel de banners promocionales ────────────────────────────────────────

class _PromoCarousel extends StatefulWidget {
  final List<_PromoSlide> slides;
  const _PromoCarousel({required this.slides});

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _ctrl = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_current + 1) % widget.slides.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.zero,
        child: SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final slide = widget.slides[i];
              return GestureDetector(
                onTap: slide.onTap,
                child: Stack(fit: StackFit.expand, children: [
                // Fondo oscuro base
                Container(color: const Color(0xFF1A1A2E)),
                // Imagen de comida
                Image.network(
                  slide.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => const SizedBox.shrink(),
                ),
                // Gradiente oscuro de izquierda
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xE0000000), Color(0x40000000), Colors.transparent],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                // Sombra superior
                Positioned(
                  top: 0, left: 0, right: 0,
                  height: 60,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                // Sombra inferior
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: 60,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                // Contenido del banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: slide.badgeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(slide.badge,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 8),
                      // Título
                      Text(slide.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
                      const SizedBox(height: 4),
                      // Subtítulo
                      Text(slide.subtitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)])),
                    ],
                  ),
                ),
              ]),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.slides.length, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _current == i ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: _current == i ? const Color(0xFFF4510C) : const Color(0xFFFFCCB3),
            borderRadius: BorderRadius.circular(3),
          ),
        )),
      ),
    ]);
  }
}

// ── Promo badge (ej. "-20%" o "2x1") ────────────────────────────────────────
class _PromoBadge extends StatelessWidget {
  final String label;
  const _PromoBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white54, width: 0.8),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      );
}

// ── Countdown timer que se actualiza cada segundo ────────────────────────────
class _PromoCountdown extends StatefulWidget {
  final DateTime expiresAt;
  const _PromoCountdown({required this.expiresAt});

  @override
  State<_PromoCountdown> createState() => _PromoCountdownState();
}

class _PromoCountdownState extends State<_PromoCountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final r = widget.expiresAt.difference(DateTime.now());
    if (mounted) setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _fmt() {
    if (_remaining == Duration.zero) return 'Expirada';
    final d = _remaining.inDays;
    final h = _remaining.inHours.remainder(24).toString().padLeft(2, '0');
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d > 0 ? '${d}d $h:$m:$s' : '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 10, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(_fmt(),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3)),
        ],
      );
}
