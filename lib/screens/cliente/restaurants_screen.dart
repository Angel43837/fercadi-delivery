import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants.dart';
import '../../core/guest_prompt.dart';
import '../../core/restaurant_categories.dart';
import '../../services/auth_service.dart';
import '../map_picker_screen.dart';
import '../../models/restaurant.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../providers/app_data_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_history_service.dart';
import '../../services/supabase_service.dart';
import '../../models/restaurant_banner.dart';
import '../../models/app_promo.dart';

// Trunca por caracteres (no solo por ancho/maxLines) para que el título de
// un platillo nunca empuje el precio ni cambie la altura de la tarjeta,
// sin depender de en qué línea termine envolviendo el texto.
String _truncateTitle(String text, [int maxChars = 15]) =>
    text.length <= maxChars ? text : '${text.substring(0, maxChars)}...';

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
  String  _zona = 'maravatio';

  // Restaurant accordion
  final Set<String> _expandedIds = {};
  // Categoría activa por restaurante (pestaña única) — el Set siempre
  // tiene un solo índice, se mantiene como Set por compatibilidad con
  // _buildProducts/_jumpToProduct.
  final Map<String, Set<int>> _selCat = {};
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
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchExpanded = false;
  String _searchQuery = '';
  List<Restaurant>? _searchResults;
  Set<String> _productMatchIds = {};

  // Filtro por categoría en la lista de restaurantes (no el de dentro de un
  // restaurante) — se lee directo de Restaurant.categorias (lista fija,
  // asignada al registrar/editar el restaurante). Vacío = sin filtro.
  final Set<String> _categoryFilter = {};
  // Categorías de restaurantes de los que el cliente ya pidió antes — se usan
  // para adelantar en la lista los restaurantes afines, sin ocultar el resto.
  Set<String> _favoriteCategories = {};
  // Segundo botón de prueba: en vez de abrir una hoja, se expande hacia el
  // lado (mismo patrón que el buscador) mostrando las categorías inline.
  bool _categoryInlineOpen = false;
  // Precio del platillo más barato de cada restaurante — para los filtros
  // "Menos de $100"/"Menos de $200" (kPriceFilters, no son categorías reales).
  Map<String, double> _minPrices = {};
  // Cupones/promos propios de la app GOGO (no de un restaurante), para la
  // pestaña "Promos" en la lista.
  List<AppPromo> _allPromos = [];
  bool _promosExpanded = false;
  final _promosScrollCtrl = ScrollController();
  Timer? _promosAutoScrollTimer;

  // Active order banner
  Map<String, dynamic>? _activeOrder;
  String _prevActiveStatus = '';
  Timer? _activeOrderTimer;
  Timer? _promoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initLocation().then((_) {
      _loadFavoriteCategories();
      _loadMinPrices();
      _loadAppPromos();
    });
    AuthService.getDisplayName().then((n) {
      if (mounted) setState(() => _displayName = n);
    });
    AuthService.getProfilePhoto().then((p) {
      if (mounted) setState(() => _photoPath = p);
    });
    AuthService.getZona().then((z) {
      if (mounted) setState(() => _zona = z);
    });
    _checkActiveOrder();
    _activeOrderTimer = Timer.periodic(
      const Duration(seconds: 8), (_) => _checkActiveOrder());
    // Refresca periódicamente el estado de las promos: el rebuild general
    // hace que isPromoActive (promo directa del platillo) se re-evalúe
    // solo, y _recomputeBannerDiscounts() quita los descuentos de banner
    // cuyo tiempo ya pasó — ese segundo camino no tenía ningún timer y se
    // quedaba congelado para siempre una vez cargado.
    _promoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(_recomputeBannerDiscounts);
      _refreshOpenMenus();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptLocationIfNeeded());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _activeOrderTimer?.cancel();
    _promoRefreshTimer?.cancel();
    _promosAutoScrollTimer?.cancel();
    _promosScrollCtrl.dispose();
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
      } else if (status == 'restaurant_accepted') {
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

  // Junta las categorías de los restaurantes de los que el cliente ya pidió
  // antes, para adelantarlos en la lista (ver _personalize).
  Future<void> _loadFavoriteCategories() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final orderedIds = await SupabaseService.getCustomerOrderedRestaurantIds(uid);
    if (orderedIds.isEmpty) return;
    final restaurants = await _futureRestaurants;
    final byId = {for (final r in restaurants) r.id: r};
    final categories = <String>{};
    for (final rid in orderedIds) {
      final r = byId[rid];
      if (r != null) categories.addAll(r.categorias);
    }
    if (mounted && categories.isNotEmpty) {
      setState(() => _favoriteCategories = categories);
    }
  }

  // Trae el precio más barato de cada restaurante de la zona, para los
  // filtros "Menos de $100"/"Menos de $200" de la barra de categorías.
  Future<void> _loadMinPrices() async {
    final restaurants = await _futureRestaurants;
    final ids = restaurants.map((r) => r.id).toList();
    if (ids.isEmpty) return;
    final prices = await SupabaseService.getMinPricesForRestaurants(ids);
    if (mounted && prices.isNotEmpty) setState(() => _minPrices = prices);
  }

  // Trae los cupones/promos propios de la app GOGO (no de un restaurante),
  // para la pestaña "Promos".
  Future<void> _loadAppPromos() async {
    final promos = await SupabaseService.getActivePromos();
    if (mounted) setState(() => _allPromos = promos);
  }

  // ── Tab de "Promos" en la lista, con el mismo estilo de acordeón que un
  // restaurante (banda naranja + se expande hacia abajo) ──────────────────
  // Avanza sola la fila de cupones, una tarjeta a la vez, mientras la
  // pestaña "Promos" siga abierta — vuelve al principio al llegar al final.
  static const _promosCardStride = 232.0; // ancho de la tarjeta (220) + separación (12)

  void _startPromosAutoScroll() {
    _promosAutoScrollTimer?.cancel();
    if (_allPromos.length < 2) return;
    // Timer.periodic solo dispara su primer "tick" después de esperar el
    // intervalo completo (1.4s) — antes eso hacía que el carrusel se abriera
    // y se quedara quieto un rato antes de arrancar. Ahora se mueve desde el
    // primer cuadro en el que ya existe (justo cuando termina de
    // construirse, tras abrirse), y de ahí en adelante sigue el mismo ritmo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _advancePromosCarousel());
    _promosAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => _advancePromosCarousel(),
    );
  }

  void _advancePromosCarousel() {
    if (!_promosScrollCtrl.hasClients) return;
    final max = _promosScrollCtrl.position.maxScrollExtent;
    final next = _promosScrollCtrl.offset + _promosCardStride;
    _promosScrollCtrl.animateTo(
      next >= max ? 0 : next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPromosTile() {
    // Ovalada (radio grande) mientras está cerrada — al abrirse, la parte de
    // arriba se suaviza un poco menos para que se sienta pegada al carrusel
    // de abajo en vez de flotar como una píldora separada.
    const collapsedRadius = 28.0;
    const expandedTopRadius = 20.0;
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_promosExpanded ? expandedTopRadius : collapsedRadius),
      topRight: Radius.circular(_promosExpanded ? expandedTopRadius : collapsedRadius),
      bottomLeft: Radius.circular(_promosExpanded ? 0 : collapsedRadius),
      bottomRight: Radius.circular(_promosExpanded ? 0 : collapsedRadius),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(_promosExpanded ? expandedTopRadius : collapsedRadius),
          topRight: Radius.circular(_promosExpanded ? expandedTopRadius : collapsedRadius),
          // Antes esto se quedaba fijo en 20 aunque estuviera cerrada — con
          // las de arriba en 28 (ovaladas) y estas en 20, las cuatro
          // esquinas no coincidían y se veía disparejo, no un óvalo
          // limpio. Ahora sigue la misma lógica que las de arriba.
          bottomLeft: Radius.circular(_promosExpanded ? 20 : collapsedRadius),
          bottomRight: Radius.circular(_promosExpanded ? 20 : collapsedRadius),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), offset: const Offset(0, 6), blurRadius: 16),
        ],
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() {
            _promosExpanded = !_promosExpanded;
            if (_promosExpanded) {
              _startPromosAutoScroll();
            } else {
              _promosAutoScrollTimer?.cancel();
            }
          }),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: borderRadius),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Expanded(
                child: Text('Promos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConstants.primaryColor)),
              ),
            ]),
          ),
        ),
        if (_promosExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: _allPromos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: Text('No hay promociones activas por ahora', style: TextStyle(color: Colors.black45)),
                  )
                : SizedBox(
                    height: 190,
                    child: ListView.builder(
                      controller: _promosScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _allPromos.length,
                      itemBuilder: (_, i) => _buildPromoCard(_allPromos[i]),
                    ),
                  ),
          ),
      ]),
    );
  }

  Widget _buildPromoCard(AppPromo p) {
    return GestureDetector(
      // Si el banner tiene una promoción real enlazada, lleva a su detalle
      // (con botón de "Reclamar" de verdad) — si no, se queda igual que
      // siempre: solo abre la imagen en grande. Un banner nunca aplica un
      // descuento por sí mismo.
      onTap: p.linkedPromotionId != null
          ? () => context.push('/promotion-detail', extra: {'promotionId': p.linkedPromotionId})
          : () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(p.imageUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Image.network(p.imageUrl,
                width: double.infinity, height: 120, fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(height: 120, color: AppConstants.primaryColor.withValues(alpha: 0.12))),
            if (p.badge.isNotEmpty)
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: p.badgeColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(p.badge,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
          ]),
          if (p.title.isNotEmpty || p.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p.title.isNotEmpty)
                  Text(p.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A1A))),
                if (p.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(p.subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12)),
                ],
              ]),
            ),
        ]),
      ),
    );
  }

  // Adelanta (sin ocultar) los restaurantes cuyas categorías coinciden con
  // las que el cliente ya ha pedido antes — mantiene el orden relativo dentro
  // de cada grupo.
  List<Restaurant> _personalize(List<Restaurant> list) {
    if (_favoriteCategories.isEmpty) return list;
    final favored = <Restaurant>[];
    final rest = <Restaurant>[];
    for (final r in list) {
      (r.categorias.any(_favoriteCategories.contains) ? favored : rest).add(r);
    }
    return [...favored, ...rest];
  }

  // Dar like sí necesita cuenta (queda ligado a tu correo) — un invitado
  // que le da al corazón antes solo cambiaba el ícono en pantalla, pero el
  // guardado en Supabase fallaba en silencio por RLS (nunca se enteraba).
  void _toggleRestaurantLike(String restaurantId) {
    if (Supabase.instance.client.auth.currentUser == null) {
      showLoginRequiredSheet(context, message: 'Inicia sesión para guardar tus favoritos.');
      return;
    }
    context.read<AppDataProvider>().toggleLike(restaurantId).ignore();
  }

  void _toggleProductLikeGuarded(String productId) {
    if (Supabase.instance.client.auth.currentUser == null) {
      showLoginRequiredSheet(context, message: 'Inicia sesión para guardar tus favoritos.');
      return;
    }
    context.read<AppDataProvider>().toggleProductLike(productId);
  }

  // Vuelve a pedir los platillos de los restaurantes ya abiertos por el
  // cliente. getProducts() ya filtra is_available=true del lado del
  // servidor, así que esto es lo único que hace falta para que un platillo
  // que el dueño acaba de activar/desactivar aparezca o desaparezca solo,
  // sin que el cliente tenga que cerrar y volver a abrir el restaurante
  // (_loadMenu de por sí solo carga una vez y nunca se repite).
  Future<void> _refreshOpenMenus() async {
    for (final rid in _expandedIds.toList()) {
      final cats = _cats[rid];
      if (cats == null || cats.isEmpty) continue;
      final prodLists = await Future.wait(cats.map((c) => SupabaseService.getProducts(c.id)));
      if (!mounted) return;
      setState(() {
        _prods[rid] = {
          for (var i = 0; i < cats.length; i++) cats[i].id: prodLists[i],
        };
      });
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
      _selCat[restaurantId] = {0};
      _recomputeBannerDiscounts();
    });
  }

  // Reconstruye _bannerDiscounts desde cero a partir de los banners ya
  // cargados en memoria — a diferencia del cálculo anterior (que solo
  // agregaba entradas y nunca las quitaba), esto sí elimina los
  // descuentos cuyo banner ya expiró. Se llama al cargar el menú y
  // periódicamente desde _promoRefreshTimer.
  void _recomputeBannerDiscounts() {
    _bannerDiscounts.clear();
    for (final list in _banners.values) {
      for (final b in list) {
        if (b.productId != null && b.isDiscountActive) {
          _bannerDiscounts[b.productId!] = b.discountPercent!;
        }
      }
    }
  }

  void _jumpToProduct(String restaurantId, String productId) {
    final cats = _cats[restaurantId] ?? [];
    final prods = _prods[restaurantId] ?? {};
    for (int i = 0; i < cats.length; i++) {
      if ((prods[cats[i].id] ?? []).any((p) => p.id == productId)) {
        setState(() {
          _selCat[restaurantId] = {i};
          _expandedProductId = productId;
        });
        return;
      }
    }
  }

  void _toggleRestaurant(String id) {
    final opening = !_expandedIds.contains(id);
    setState(() {
      // Solo un restaurante abierto a la vez — al abrir uno nuevo se cierran
      // los demás (no aplica a la auto-expansión por búsqueda, que sí puede
      // abrir varios a propósito).
      _expandedIds.clear();
      if (opening) _expandedIds.add(id);
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
        leadingWidth: 60,
        titleSpacing: 4,
        // ── Usuario a la izquierda ───────────────────────────────────────────
        leading: GestureDetector(
          onTap: () async {
            await context.push('/profile');
            final n = await AuthService.getDisplayName();
            final p = await AuthService.getProfilePhoto();
            final z = await AuthService.getZona();
            if (mounted) setState(() { _displayName = n; _photoPath = p; _zona = z; });
          },
          child: Padding(
            // Alineado con el margen de 16px que usan las tarjetas de
            // restaurantes de la lista, en vez de quedar pegado al borde.
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 8),
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
    // SafeArea + margen abajo — sin esto quedaba pegado hasta el borde de
    // la pantalla (detrás del indicador de inicio en iPhone).
    return SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: GestureDetector(
        onTap: () => context.go('/tracking', extra: _activeOrder!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delivery_dining, color: AppConstants.primaryColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pedido en curso',
                      style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text(name,
                      style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.55),
                          fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Seguimiento',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                SizedBox(width: 2),
                Icon(Icons.chevron_right, color: Colors.white, size: 16),
              ]),
            ),
          ]),
        ),
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
          onTap: () async {
            Navigator.pop(context);
            if (Supabase.instance.client.auth.currentUser == null) {
              showLoginRequiredSheet(context,
                  message: 'Crea una cuenta para tener tu perfil.', returnTo: '/profile');
              return;
            }
            // Igual que el avatar del encabezado: al regresar de "Mi perfil"
            // hay que releer estos datos, si no se quedan con el valor viejo
            // hasta que se reinicie la pantalla.
            await context.push('/profile');
            final n = await AuthService.getDisplayName();
            final p = await AuthService.getProfilePhoto();
            final z = await AuthService.getZona();
            if (mounted) setState(() { _displayName = n; _photoPath = p; _zona = z; });
          },
        ),
        ListTile(
          leading: Icon(Icons.receipt_long_outlined, color: isDark ? AppConstants.primaryColor : Colors.white),
          title: Text('Mis pedidos', style: TextStyle(color: textColor)),
          onTap: () {
            Navigator.pop(context);
            if (Supabase.instance.client.auth.currentUser == null) {
              showLoginRequiredSheet(context,
                  message: 'Inicia sesión para ver tus pedidos.', returnTo: '/history');
              return;
            }
            context.push('/history');
          },
        ),
        ListTile(
          leading: Icon(Icons.local_offer_outlined, color: isDark ? AppConstants.primaryColor : Colors.white),
          title: Text('Mis promociones', style: TextStyle(color: textColor)),
          onTap: () {
            Navigator.pop(context);
            if (Supabase.instance.client.auth.currentUser == null) {
              showLoginRequiredSheet(context,
                  message: 'Inicia sesión para ver tus promociones.', returnTo: '/my-promotions');
              return;
            }
            context.push('/my-promotions');
          },
        ),
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined, color: isDark ? AppConstants.primaryColor : Colors.white),
          title: Text('Política de Privacidad', style: TextStyle(color: textColor)),
          onTap: () { Navigator.pop(context); context.push('/privacy-policy'); },
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

  Future<void> _refreshRestaurants() async {
    // No solo vuelve a pedir los restaurantes — también relee la zona (y el
    // nombre/foto) guardados en el perfil, por si el usuario los cambió y
    // llegó aquí sin pasar por alguno de los caminos que ya refrescan esto.
    final future = SupabaseService.getRestaurants();
    final zona   = await AuthService.getZona();
    final name   = await AuthService.getDisplayName();
    final photo  = await AuthService.getProfilePhoto();
    setState(() {
      _futureRestaurants = future;
      _zona = zona;
      _displayName = name;
      _photoPath = photo;
    });
    await future;
  }

  Widget _buildBody(AppDataProvider appData, bool isDark) {
    if (_locationResult?.status != LocationStatus.enMaravatio) {
      return _buildFueraDeZona(_locationResult?.status);
    }
    return RefreshIndicator(
      color: AppConstants.primaryColor,
      onRefresh: _refreshRestaurants,
      child: FutureBuilder<List<Restaurant>>(
      future: _futureRestaurants,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                  color: isDark ? AppConstants.primaryColor : Colors.white));
        }
        final zonaRestaurants = (snapshot.data ?? []).where((r) => r.zona == _zona).toList();
        final all = _personalize(zonaRestaurants
            .where((r) => _categoryFilter.isEmpty || _matchesCategoryFilter(r))
            .toList());
        final restaurants = _searchQuery.isEmpty
            ? all
            : (_searchResults ?? all.where((r) => r.name.toLowerCase().contains(_searchQuery)).toList());
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          // Con la lista vacía, sin el +1 extra el índice 1 (donde vive el
          // mensaje de "no hay restaurantes") nunca se llegaba a construir.
          itemCount: restaurants.isEmpty ? 3 : restaurants.length + 2,
          itemBuilder: (context, i) {
            if (i == 1) return _buildPromosTile();
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
                  // ── Buscador y filtro de categorías en la misma línea, de
                  // esquina a esquina — al expandirse uno, el otro se oculta.
                  _buildSearchCategoryRow(zonaRestaurants),
                ]),
              );
            }
            if (restaurants.isEmpty) {
              final zonaLabel = LocationService.zonaLabel(_zona);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'Todavía no hay restaurantes en $zonaLabel'
                        : 'No se encontró "$_searchQuery"',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                ),
              );
            }
            return _buildRestaurantTile(restaurants[i - 2], appData);
          },
        );
      },
      ),
    );
  }

  // Un restaurante cumple el filtro si tiene la categoría elegida, o si el
  // filtro es de precio y su platillo más barato cae dentro del rango.
  bool _matchesCategoryFilter(Restaurant r) {
    if (_categoryFilter.contains(kPriceFilterUnder100)) {
      return (_minPrices[r.id] ?? double.infinity) < 100;
    }
    if (_categoryFilter.contains(kPriceFilterUnder200)) {
      return (_minPrices[r.id] ?? double.infinity) < 200;
    }
    return r.categorias.any(_categoryFilter.contains);
  }

  // ── Buscador + filtro de categoría, en la misma línea ───────────────────
  // Colapsados van de esquina a esquina (categorías a la izquierda, buscador
  // a la derecha, solo íconos). Al abrir uno, ocupa toda la línea y el otro
  // se oculta por completo — no caben los dos expandidos a la vez.
  Widget _buildSearchCategoryRow(List<Restaurant> restaurantsInZona) {
    final realNames = restaurantsInZona.expand((r) => r.categorias).toSet().toList()..sort();
    final names = [...realNames, ...kPriceFilters];
    final hasCategories = names.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_categoryInlineOpen) return _buildCategoryBar(names, constraints.maxWidth);
        if (_searchExpanded) return _buildSearchBar(constraints.maxWidth);
        return Row(children: [
          if (hasCategories) _buildCategoryCollapsedIcon(),
          const Spacer(),
          _buildSearchCollapsedIcon(),
        ]);
      },
    );
  }

  Widget _buildCategoryCollapsedIcon() {
    return GestureDetector(
      onTap: () => setState(() => _categoryInlineOpen = true),
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Stack(children: [
          const Center(child: Icon(Icons.filter_list, color: AppConstants.primaryColor, size: 20)),
          if (_categoryFilter.isNotEmpty)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildSearchCollapsedIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: IconButton(
        icon: const Icon(Icons.search, color: Colors.white, size: 22),
        onPressed: () {
          setState(() => _searchExpanded = true);
          WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocusNode.requestFocus());
        },
      ),
    );
  }

  Widget _buildSearchBar(double fullWidth) {
    return Container(
      width: fullWidth,
      height: 46,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23)),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocusNode,
        onChanged: (v) async {
          final q = v.trim().toLowerCase();
          if (q.isEmpty) {
            // Al borrar la búsqueda con teclado (no solo con la X),
            // cierra los restaurantes que se habían auto-expandido.
            setState(() {
              for (final rid in _productMatchIds) { _expandedIds.remove(rid); }
              _searchQuery = '';
              _searchResults = null;
              _productMatchIds = {};
            });
            return;
          }
          setState(() { _searchQuery = q; _searchResults = null; });
          final all = (await _futureRestaurants).where((r) => r.zona == _zona).toList();
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
        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Busca un restaurante o platillo...',
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35), fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: AppConstants.primaryColor, size: 22),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, color: Colors.black45, size: 20),
            onPressed: () {
              _searchCtrl.clear();
              _searchFocusNode.unfocus();
              setState(() {
                for (final rid in _productMatchIds) { _expandedIds.remove(rid); }
                _searchExpanded = false;
                _searchQuery = ''; _searchResults = null; _productMatchIds = {};
              });
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCategoryBar(List<String> names, double fullWidth) {
    return Container(
      width: fullWidth,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23)),
      child: Row(children: [
        IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, color: AppConstants.primaryColor, size: 18),
          onPressed: () => setState(() => _categoryInlineOpen = false),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            children: names.map((name) {
              final selected = _categoryFilter.contains(name);
              return Padding(
                padding: const EdgeInsets.fromLTRB(0, 11, 6, 11),
                child: GestureDetector(
                  // Selección única: elegir otra reemplaza la anterior;
                  // volver a tocar la misma la quita (muestra todos).
                  onTap: () => setState(() {
                    if (selected) {
                      _categoryFilter.clear();
                    } else {
                      _categoryFilter
                        ..clear()
                        ..add(name);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppConstants.primaryColor : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        kRestaurantCategoryIcons[name] ?? kRestaurantCategoryIconDefault,
                        size: 13,
                        color: selected ? Colors.white : AppConstants.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(name,
                          style: TextStyle(
                            color: selected ? Colors.white : AppConstants.primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          )),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 6),
      ]),
    );
  }

  // ── Restaurant accordion tile ──────────────────────────────────────────

  Widget _buildRestaurantTile(Restaurant r, AppDataProvider appData) {
    final isExpanded = _expandedIds.contains(r.id);
    final isLoading = _loadingMenu[r.id] == true;
    final cats = _cats[r.id] ?? [];
    final selIdxs = _selCat[r.id] ?? {0};
    const headerColor = AppConstants.primaryColor;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(isExpanded ? 0 : 12),
      bottomRight: Radius.circular(isExpanded ? 0 : 12),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      clipBehavior: Clip.antiAlias,
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
                onTap: () => _toggleRestaurantLike(r.id),
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
              color: Color(0xFFF2F2F2),
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
                _buildCategoryTabs(r.id, cats, selIdxs),
                _buildProducts(r, cats, selIdxs, appData),
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
      String restaurantId, List<Category> cats, Set<int> selIdxs) {
    return _CategoryTabsRow(
      restaurantId: restaurantId,
      cats: cats,
      selIdxs: selIdxs,
      // Selección única: tocar una categoría cambia la pestaña activa.
      onSelect: (i) => setState(() {
        _selCat[restaurantId] = {i};
        _expandedProductId = null;
      }),
      categoryIcon: _categoryIcon,
    );
  }

  // ── Product accordion list ─────────────────────────────────────────────

  Widget _buildProducts(
      Restaurant r, List<Category> cats, Set<int> selIdxs, AppDataProvider appData) {
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

    // Varias categorías pueden estar activas a la vez — se juntan los
    // productos de todas, en el mismo orden en que aparecen las pestañas.
    final selectedCats = [for (var i = 0; i < cats.length; i++) if (selIdxs.contains(i)) cats[i]];
    final regular = <Product>[];
    final extras = <Product>[];
    for (final cat in selectedCats) {
      regular.addAll((_prods[r.id]?[cat.id] ?? [])
          .where((p) => appData.getProductAvailability(p.id, p.isAvailable)));
      extras.addAll(appData
          .extraProductsForCategory(r.id, cat.id)
          .where((p) => p.isAvailable)
          .map((p) => Product(
                id: p.id,
                categoryId: p.categoryIds.first,
                name: p.name,
                description: p.description.isEmpty ? null : p.description,
                price: p.price,
                imageUrl: p.imagePath,
              )));
    }

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
        return _buildProductTile(p, r.id, r.name, accent, isExpanded, qty);
      }),
    ]);
  }

  Widget _buildProductTile(Product p, String restaurantId, String restaurantName,
      Color accent, bool isExpanded, int qty, {bool isPromo = false, int? bannerDiscount}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useOrange = isPromo || isDark || bannerDiscount != null;
    final tileColor = useOrange ? const Color(0xFFF4510C) : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            offset: const Offset(0, 2),
            blurRadius: 8,
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
            height: isPromo ? 144 : (bannerDiscount != null ? 112 : 108),
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
                          _PromoCountdown(
                            expiresAt: p.promoExpiresAt!,
                            onExpired: () => setState(() {}),
                          ),
                        const SizedBox(height: 3),
                      ],
                      Text(_truncateTitle(p.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                      const SizedBox(height: 3),
                      if (bannerDiscount != null && !isPromo) ...[
                        _PromoBadge('-$bannerDiscount%'),
                        const SizedBox(height: 2),
                      ],
                      if (isPromo && p.promoDiscountPercent != null) ...[
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('\$${p.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.65),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white70)),
                          const SizedBox(width: 5),
                          Text('\$${p.promoPrice.toStringAsFixed(0)} MXN',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ]),
                      ] else if (bannerDiscount != null) ...[
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('\$${p.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.65),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white70)),
                          const SizedBox(width: 5),
                          Text('\$${(p.price * (1 - bannerDiscount / 100)).toStringAsFixed(0)} MXN',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ]),
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
                        onTap: () => _toggleProductLikeGuarded(p.id),
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
                      onTap: () => _toggleProductLikeGuarded(p.id),
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
                SizedBox(
                  width: double.infinity,
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
                      // El % de un banner (bannerDiscount) es solo texto
                      // publicitario ahora — ya no se resta del precio real
                      // al agregar al carrito. Para que un descuento aplique
                      // de verdad hace falta una promoción real, reclamada y
                      // validada por el servidor (ver checkout_screen.dart).
                      for (int i = 0; i < qty; i++) {
                        context.read<CartProvider>().addProduct(p, restaurantId, restaurantName);
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
          'Solo operamos en Maravatío, Acámbaro\ny Morelia, Mich.\n\nEstás a ${_locationResult?.distanciaKm?.toStringAsFixed(1)} km del centro más cercano.',
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
  final Set<int> selIdxs;
  final void Function(int) onSelect;
  final IconData Function(String, String?) categoryIcon;

  const _CategoryTabsRow({
    required this.restaurantId,
    required this.cats,
    required this.selIdxs,
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
            final isSelected = widget.selIdxs.contains(i);
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
                  Icon(isSelected ? Icons.check_circle : widget.categoryIcon(cat.name, cat.icon),
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
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
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
          child: NotificationListener<ScrollNotification>(
            // El usuario tocando y arrastrando el carrusel manda un
            // ScrollStartNotification con dragDetails != null (a diferencia
            // de nuestro propio animateToPage, que también dispara
            // notificaciones de scroll pero sin dragDetails) — se usa eso
            // para pausar el avance automático mientras el dedo está encima
            // y no le compita al swipe manual. Al soltar, se reinicia el
            // timer desde cero (mismos 4s) en vez de dejarlo corriendo con
            // el conteo viejo.
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _timer?.cancel();
              } else if (n is ScrollEndNotification) {
                _startAutoScroll();
              }
              return false;
            },
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
  final VoidCallback? onExpired;
  const _PromoCountdown({required this.expiresAt, this.onExpired});

  @override
  State<_PromoCountdown> createState() => _PromoCountdownState();
}

class _PromoCountdownState extends State<_PromoCountdown> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final r = widget.expiresAt.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _remaining = r.isNegative ? Duration.zero : r);
    if (_remaining == Duration.zero && !_expiredNotified) {
      _expiredNotified = true;
      _timer.cancel();
      widget.onExpired?.call();
    }
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
