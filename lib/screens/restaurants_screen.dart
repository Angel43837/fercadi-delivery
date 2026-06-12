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
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptLocationIfNeeded());
  }

  @override
  void dispose() {
    _activeOrderTimer?.cancel();
    super.dispose();
  }

  Future<void> _promptLocationIfNeeded() async {
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
    final cats = await SupabaseService.getCategories(restaurantId);
    if (!mounted) return;
    final prodLists = await Future.wait(cats.map((c) => SupabaseService.getProducts(c.id)));
    if (!mounted) return;
    final prods = <String, List<Product>>{
      for (var i = 0; i < cats.length; i++) cats[i].id: prodLists[i],
    };
    setState(() {
      _cats[restaurantId] = cats;
      _prods[restaurantId] = prods;
      _loadingMenu[restaurantId] = false;
      _selCat[restaurantId] = 0;
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_activeOrder != null) _buildActiveOrderBanner(),
      if (cartCount > 0)
        Container(
          color: isDark ? AppConstants.surfaceColor : AppConstants.primaryColor,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: SafeArea(
            child: ElevatedButton(
              onPressed: () => context.push('/cart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 6,
                shadowColor: Colors.black54,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$cartCount',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white)),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Realizar pedido',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  Text('\$${cart.total.toStringAsFixed(0)} MXN',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
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
    const tileBg = AppConstants.primaryColor;
    const tileText = Colors.white;
    final tileSub = Colors.white.withValues(alpha: 0.6);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 8),
            blurRadius: 18,
          ),
        ],
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
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: tileText)),
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
                        : tileSub,
                    size: 26),
              ),
            ]),
          ),
        ),
        if (isExpanded)
          Column(children: [
            Divider(
              height: 1,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppConstants.surface2Color
                  : Colors.white.withValues(alpha: 0.3),
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: List.generate(cats.length, (i) {
          final cat = cats[i];
          final color = _catColors[i % _catColors.length];
          final isSelected = selIdx == i;

          final bgColor = isDark
              ? (isSelected ? color : color.withValues(alpha: 0.12))
              : (isSelected ? AppConstants.primaryColor : AppConstants.primaryColor.withValues(alpha: 0.65));
          final borderColor = isDark
              ? (isSelected ? color : color.withValues(alpha: 0.35))
              : AppConstants.primaryColor;
          const textColor = Colors.white;

          return GestureDetector(
            onTap: () => setState(() {
              _selCat[restaurantId] = i;
              _expandedProductId = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (cat.icon != null)
                  Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Text(cat.icon!, style: const TextStyle(fontSize: 14))),
                Text(cat.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: textColor)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.surface2Color : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.45)
                                    : Colors.black54)),
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
                          color: liked
                              ? AppConstants.primaryColor
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.25)),
                          size: 18,
                        ),
                        if (likes > 0) ...[
                          const SizedBox(width: 3),
                          Text('$likes',
                              style: TextStyle(
                                  color: liked
                                      ? AppConstants.primaryColor
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.35)
                                          : Colors.black.withValues(alpha: 0.35)),
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
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.black38),
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
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : Colors.black54,
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
                            color: isDark ? AppConstants.surfaceColor : Colors.grey.shade100,
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
                                  color: (isDark ? Colors.white : Colors.black87)
                                      .withValues(alpha: qty > 1 ? 1 : 0.3),
                                  size: 18),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text('$qty',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
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
