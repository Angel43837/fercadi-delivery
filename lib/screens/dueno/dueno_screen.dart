// dueno_screen.dart
// Panel del dueño del restaurante.
// Permite al dueño:
//   - Ver y gestionar pedidos en tiempo real (pendientes, aceptados, en camino, entregados)
//   - Activar/desactivar productos del menú
//   - Agregar, editar y eliminar platillos con fotos
//   - Configurar la información del restaurante (nombre, foto, dirección, teléfono)
// Los pedidos se actualizan en tiempo real usando Supabase Realtime (subscribeToOrders).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants.dart';
import '../../core/restaurant_categories.dart';
import '../../providers/app_data_provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/restaurant_banner.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../map_picker_screen.dart';

class _Product {
  final String id;
  String name;
  String description;
  double price;
  bool isAvailable;
  List<String> categoryIds;
  String? imagePath;
  int? promoDiscountPercent;
  bool promoIs2x1;
  DateTime? promoExpiresAt;

  _Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
    required this.categoryIds,
    this.imagePath,
    this.promoDiscountPercent,
    this.promoIs2x1 = false,
    this.promoExpiresAt,
  });

  bool get isPromoActive =>
      promoExpiresAt != null &&
      promoExpiresAt!.isAfter(DateTime.now()) &&
      (promoDiscountPercent != null || promoIs2x1);
}

class _Category {
  final String id;
  final String name;
  final String emoji;
  const _Category({required this.id, required this.name, required this.emoji});
}

class DuenoScreen extends StatefulWidget {
  const DuenoScreen({super.key});

  @override
  State<DuenoScreen> createState() => _DuenoScreenState();
}

class _DuenoScreenState extends State<DuenoScreen> {
  int _tab = 0;
  AppOrderStatus? _filterStatus;
  bool _isDark = false;

  Color get _bg       => _isDark ? const Color(0xFF121212) : const Color(0xFFFF5722);
  Color get _surface  => _isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE64A19);
  Color get _surface2 => _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD84315);
  Color get _text     => Colors.white;
  Color get _textMid  => Colors.white.withValues(alpha: 0.75);
  Color get _textLow  => Colors.white.withValues(alpha: 0.45);
  Color get _inputFill => _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD84315);

  // Pedidos reales de Supabase
  List<Map<String, dynamic>> _realOrders = [];
  final Set<String> _notifiedIds = {};
  Timer? _orderPollTimer;
  RealtimeChannel? _ordersChannel;

  // ID del restaurante de este dueño
  String _restaurantId = '1';
  bool   _isPremium    = false;

  // Estado de aprobación (fase 1 del sistema de registro/aprobación de restaurantes)
  String  _approvalStatus   = 'aprobado';
  String? _rejectionReason;
  String? _correctionNotes;
  bool    _approvalLoaded   = false;

  // Límites del plan gratuito — con premium se amplían.
  static const int _maxProductosGratis   = 7;
  static const int _maxProductosPremium  = 20;
  int get _maxProductos => _isPremium ? _maxProductosPremium : _maxProductosGratis;

  // Configuración del restaurante
  String _restName    = '';
  String _restDesc    = '';
  String _restPhone   = '';
  String _restAddress = '';
  String _restPhoto   = '';
  String _restEmoji   = '🍴';
  String _restZona    = 'maravatio';
  final Set<String> _restCategorias = {};
  LatLng? _restLatLng;

  final _restNameCtrl    = TextEditingController();
  final _restDescCtrl    = TextEditingController();
  final _restPhoneCtrl   = TextEditingController();
  final _restAddressCtrl = TextEditingController();

  // Banners
  List<RestaurantBanner> _bannerList = [];
  bool _loadingBanners = false;

  List<_Category> _categories = const [
    _Category(id: 'c1',  name: 'Platillos',  emoji: '🍽️'),
    _Category(id: 'c2',  name: 'Botanas',    emoji: '🍟'),
    _Category(id: 'c3',  name: 'Bebidas',    emoji: '🥤'),
    _Category(id: 'c10', name: 'Postres',    emoji: '🍰'),
    _Category(id: 'c11', name: 'Desayunos',  emoji: '🌅'),
    _Category(id: 'c12', name: 'Especiales', emoji: '⭐'),
  ];

  List<_Product> _products = [
    _Product(id: 'p1', name: 'Big Mac',         description: 'Dos carnes, lechuga, queso, cebolla y salsa especial', price: 89,  isAvailable: true,  categoryIds: ['c1']),
    _Product(id: 'p2', name: 'Quarter Pounder', description: 'Carne 100% res, queso americano, cebolla y mostaza',   price: 95,  isAvailable: true,  categoryIds: ['c1']),
    _Product(id: 'p3', name: 'McPollo Crispy',  description: 'Pollo crujiente, lechuga y mayonesa en pan tostado',   price: 79,  isAvailable: false, categoryIds: ['c1']),
    _Product(id: 'p4', name: 'Papas Medianas',  description: 'Papas fritas crujientes con sal',                      price: 35,  isAvailable: true,  categoryIds: ['c2']),
    _Product(id: 'p5', name: 'Papas Grandes',   description: 'Porción grande de papas fritas',                       price: 45,  isAvailable: true,  categoryIds: ['c2']),
    _Product(id: 'p6', name: 'Coca-Cola 500ml', description: 'Refresco frío en vaso',                                price: 30,  isAvailable: true,  categoryIds: ['c3']),
    _Product(id: 'p7', name: 'Café Americano',  description: 'Café negro recién preparado',                          price: 40,  isAvailable: true,  categoryIds: ['c3']),
    _Product(id: 'p8', name: 'McFlurry Oreo',   description: 'Helado suave con trozos de galleta Oreo',              price: 55,  isAvailable: true,  categoryIds: ['c10']),
  ];

  @override
  void initState() {
    super.initState();
    _initRestaurant();
  }

  Future<void> _initRestaurant() async {
    _restaurantId = await AuthService.getRestaurantId();
    if (!SupabaseService.useMock) {
      _loadApprovalStatus();
      _loadCategories();
      _loadProductsFromSupabase();
      _loadBanners();
      final zona = await SupabaseService.getRestaurantZona(_restaurantId);
      if (mounted) setState(() => _restZona = zona);
      final categorias = await SupabaseService.getRestaurantCategorias(_restaurantId);
      if (mounted) setState(() { _restCategorias.clear(); _restCategorias.addAll(categorias); });
      final premium = await SupabaseService.getRestaurantIsPremium(_restaurantId);
      if (mounted) setState(() => _isPremium = premium);
    }
    _loadRealOrders();
    _ordersChannel = SupabaseService.subscribeToOrders(_loadRealOrders);
    _orderPollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadRealOrders());
    _loadRestaurantSettings();
  }

  Future<void> _loadApprovalStatus() async {
    try {
      final data = await SupabaseService.getRestaurantApprovalStatus(_restaurantId);
      if (!mounted || data == null) return;
      setState(() {
        _approvalStatus  = data['approval_status'] as String? ?? 'aprobado';
        _rejectionReason = data['rejection_reason'] as String?;
        _correctionNotes = data['correction_notes'] as String?;
        _approvalLoaded  = true;
      });
    } catch (_) {
      if (mounted) setState(() => _approvalLoaded = true);
    }
  }

  // Carga las categorías reales del restaurante desde Supabase.
  // Sin esto, el menú usaba siempre la lista fija de IDs c1/c2/c3... y los
  // platillos de restaurantes con categorías propias (ej. Tacos Chuy) no
  // coincidían con ningún ID, así que no se mostraban.
  Future<void> _loadCategories() async {
    final cats = await SupabaseService.getCategories(_restaurantId);
    if (!mounted || cats.isEmpty) return;
    setState(() {
      _categories = cats
          .map((c) => _Category(id: c.id, name: c.name, emoji: c.icon ?? '🍽️'))
          .toList();
    });
  }

  Future<void> _loadRestaurantSettings() async {
    final local = await AuthService.getRestaurantSettings();
    // Supabase es la fuente de verdad para nombre/descripción/dirección/
    // emoji/foto — el caché local (local) se usa solo si falla la consulta
    // (ej. sin internet) o en modo mock. El teléfono no tiene columna en
    // la tabla "restaurants" todavía, así que ese sigue siendo local-only.
    final remote = await SupabaseService.getRestaurantProfile(_restaurantId);
    final s = remote ?? local;
    if (remote != null) {
      // Refresca el caché local con lo real, para que la próxima vez que
      // se abra (incluso sin internet) ya tenga lo correcto a la mano.
      await AuthService.saveRestaurantSettings(
        name: remote['name'], desc: remote['desc'], address: remote['address'],
        photo: remote['photo'], emoji: remote['emoji'],
      );
    }
    if (!mounted) return;
    setState(() {
      _restName    = s['name']!;
      _restDesc    = s['desc']!;
      _restPhone   = local['phone']!;
      _restAddress = s['address']!;
      _restPhoto   = s['photo']!;
      _restEmoji   = s['emoji']!.isNotEmpty ? s['emoji']! : '🍴';
    });
    _restNameCtrl.text    = _restName;
    _restDescCtrl.text    = _restDesc;
    _restPhoneCtrl.text   = _restPhone;
    _restAddressCtrl.text = _restAddress;
  }

  @override
  void dispose() {
    _orderPollTimer?.cancel();
    _ordersChannel?.unsubscribe();
    _restNameCtrl.dispose();
    _restDescCtrl.dispose();
    _restPhoneCtrl.dispose();
    _restAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRealOrders() async {
    try {
      final data = await SupabaseService.getActiveOrders(restaurantId: _restaurantId);
      if (!mounted) return;

      // Detectar pedidos nuevos pendientes para notificar
      final nuevos = data.where((o) {
        final id = o['id'] as String;
        final status = o['status'] as String? ?? '';
        return status == 'pending' && !_notifiedIds.contains(id);
      }).toList();

      setState(() => _realOrders = data);

      for (final order in nuevos) {
        _notifiedIds.add(order['id'] as String);
        _showNewOrderAlert(order);
        Map<String, dynamic> d = {};
        try { d = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}
        NotificationService.nuevoPedido(
          d['name'] as String? ?? 'Cliente',
          (order['total'] as num?)?.toDouble() ?? 0,
        );
      }
    } catch (_) {}
  }

  void _showNewOrderAlert(Map<String, dynamic> order) {
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}
    final name = delivery['name'] as String? ?? 'Cliente';
    final total = (order['total'] as num?)?.toDouble() ?? 0;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🔔 ¡Nuevo pedido!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text(
          '$name realizó un pedido por \$${total.toStringAsFixed(0)} MXN',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cerrar', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _tab = 1);
            },
            child: const Text('Ver pedido',
                style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadProductsFromSupabase() async {
    final data = await SupabaseService.getProductsForRestaurant(_restaurantId);
    if (!mounted) return;
    setState(() {
      _products = data.map((p) => _Product(
        id: p.id,
        name: p.name,
        description: p.description ?? '',
        price: p.price,
        isAvailable: p.isAvailable,
        categoryIds: [p.categoryId],
        imagePath: p.imageUrl,
        promoDiscountPercent: p.promoDiscountPercent,
        promoIs2x1: p.promoIs2x1,
        promoExpiresAt: p.promoExpiresAt,
      )).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.useMock && !_approvalLoaded) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!SupabaseService.useMock && _approvalStatus != 'aprobado') {
      return _buildApprovalGate();
    }

    final appData = context.watch<AppDataProvider>();
    final isOpen = appData.isRestaurantOpen(_restaurantId);
    final pendingCount = _realOrders.where((o) => o['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(appData, isOpen),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildDashboard(),
              _buildPedidos(),
              _buildMenu(appData),
              _buildPerfilRestaurante(),
              _buildBanners(),
            ],
          ),
        ),
        _buildBottomNav(pendingCount),
      ]),
    );
  }

  Widget _buildApprovalGate() {
    final ({IconData icon, String title, String body}) info = switch (_approvalStatus) {
      'en_revision' => (
        icon: Icons.hourglass_top_rounded,
        title: 'Tu restaurante está en revisión',
        body: 'Un administrador ya está revisando la información de tu restaurante. '
            'Te avisaremos en cuanto termine.',
      ),
      'correcciones_solicitadas' => (
        icon: Icons.edit_note_rounded,
        title: 'Se solicitaron correcciones',
        body: _correctionNotes?.isNotEmpty == true
            ? _correctionNotes!
            : 'El administrador pidió corregir algo de tu registro. Contáctanos para más detalles.',
      ),
      'rechazado' => (
        icon: Icons.cancel_outlined,
        title: 'Registro rechazado',
        body: _rejectionReason?.isNotEmpty == true
            ? _rejectionReason!
            : 'Tu solicitud de registro no fue aprobada.',
      ),
      _ => (
        icon: Icons.hourglass_empty_rounded,
        title: 'Tu restaurante está pendiente de aprobación',
        body: 'Estamos revisando la información de tu registro. '
            'En cuanto un administrador lo apruebe, podrás empezar a operar.',
      ),
    };

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(info.icon, color: Colors.white, size: 72),
              const SizedBox(height: 24),
              Text(
                info.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 12),
              Text(
                info.body,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () async {
                  await AuthService.clearDuenoSession();
                  if (!mounted) return;
                  context.go(kIsWeb ? '/restaurante' : '/login');
                },
                child: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppDataProvider appData, bool isOpen) {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _tab = 3),
            child: _restPhoto.isNotEmpty
                ? ClipOval(child: Image.network(_restPhoto, width: 40, height: 40, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Text(_restEmoji, style: const TextStyle(fontSize: 32))))
                : Text(_restEmoji.isNotEmpty ? _restEmoji : '🍴', style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _restName.isNotEmpty ? _restName : 'Mi Restaurante',
                style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Panel del restaurante',
                  style: TextStyle(color: _textMid, fontSize: 12)),
            ]),
          ),
          IconButton(
            icon: Icon(
              _isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              color: _isDark ? const Color(0xFFFFB300) : const Color(0xFF5C6BC0),
              size: 22,
            ),
            tooltip: _isDark ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => setState(() => _isDark = !_isDark),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: _textMid, size: 20),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await AuthService.clearDuenoSession();
              if (!mounted) return;
              // En la app móvil el dueño vuelve al login general del cliente
              // (misma app, un rol más). En web sí regresa al portal
              // dedicado "Mi Restaurante" (/restaurante).
              context.go(kIsWeb ? '/restaurante' : '/login');
            },
          ),
          GestureDetector(
            onTap: () => appData.setRestaurantOpen(_restaurantId, !isOpen),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOpen ? Colors.green.withValues(alpha: 0.12) : _surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOpen ? Colors.green.withValues(alpha: 0.5) : _textLow,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: isOpen ? Colors.green : _textLow,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOpen ? 'Abierto' : 'Cerrado',
                  style: TextStyle(
                    color: isOpen ? Colors.green : _textMid,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDashboard() {
    // Ganancia neta del restaurante — ya con la comisión de la plataforma
    // (GOGO) descontada de sus ventas, antes se mostraba el bruto completo.
    final ventasHoyBruto = _realOrders
        .where((o) => o['status'] == 'delivered')
        .fold<double>(0, (s, o) => s + ((o['total'] as num?)?.toDouble() ?? 0));
    final ventasHoy = ventasHoyBruto * (1 - LocationService.comisionRestaurantePct / 100);
    final entregados = _realOrders.where((o) => o['status'] == 'delivered').length;
    final pendientes = _realOrders.where((o) => o['status'] == 'pending').length;
    final enCamino   = _realOrders.where((o) => o['status'] == 'delivering' || o['status'] == 'accepted' || o['status'] == 'restaurant_accepted').length;
    final cancelados = _realOrders.where((o) => o['status'] == 'cancelled').length;
    final total = _realOrders.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard(label: 'Ventas hoy',   value: '\$${ventasHoy.toStringAsFixed(0)}', suffix: 'MXN',        icon: Icons.attach_money,       color: Colors.green,                  isDark: _isDark),
            _StatCard(label: 'Pedidos hoy',  value: '$total',                             suffix: 'total',       icon: Icons.receipt_long,        color: AppConstants.primaryColor,     isDark: _isDark),
            _StatCard(label: 'Entregados',   value: '$entregados',                        suffix: 'completados', icon: Icons.check_circle_outline, color: const Color(0xFF00BFA5),       isDark: _isDark),
            _StatCard(label: 'Pendientes',   value: '$pendientes',                        suffix: 'en espera',   icon: Icons.hourglass_bottom,    color: const Color(0xFFFFB300),       isDark: _isDark),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estado de pedidos',
                style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 14),
            if (total > 0) ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(children: [
                if (pendientes > 0) Expanded(flex: pendientes, child: Container(height: 10, color: const Color(0xFFFFB300))),
                if (enCamino   > 0) Expanded(flex: enCamino,   child: Container(height: 10, color: AppConstants.primaryColor)),
                if (entregados > 0) Expanded(flex: entregados, child: Container(height: 10, color: Colors.green)),
                if (cancelados > 0) Expanded(flex: cancelados, child: Container(height: 10, color: Colors.red)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _StatusLegend('Pendiente', const Color(0xFFFFB300),   pendientes),
              _StatusLegend('En camino', AppConstants.primaryColor, enCamino),
              _StatusLegend('Entregado', Colors.green,              entregados),
              _StatusLegend('Cancelado', Colors.red,                cancelados),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Últimos pedidos',
              style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 15)),
          TextButton(
            onPressed: () => setState(() => _tab = 1),
            child: const Text('Ver todos', style: TextStyle(color: AppConstants.primaryColor, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        ..._realOrders.take(4).map((o) => _RealOrderMiniRow(order: o, isDark: _isDark)),
      ],
    );
  }

  Widget _buildPedidos() {
    final filtered = _filterStatus == null
        ? _realOrders
        : _realOrders.where((o) {
            final s = o['status'] as String? ?? '';
            switch (_filterStatus) {
              case AppOrderStatus.pendiente: return s == 'pending';
              case AppOrderStatus.enCamino:  return s == 'delivering' || s == 'accepted' || s == 'restaurant_accepted';
              case AppOrderStatus.entregado: return s == 'delivered';
              default: return true;
            }
          }).toList();

    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          _FilterChip('Todos',     null,                      _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Pendiente', AppOrderStatus.pendiente,  _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('En camino', AppOrderStatus.enCamino,   _filterStatus, (v) => setState(() => _filterStatus = v)),
          _FilterChip('Entregado', AppOrderStatus.entregado,  _filterStatus, (v) => setState(() => _filterStatus = v)),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long_outlined, size: 56, color: _textLow),
                  const SizedBox(height: 12),
                  Text('Sin pedidos por ahora',
                      style: TextStyle(color: _textLow, fontSize: 15)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _RealOrderCard(
                  order: filtered[i],
                  isDark: _isDark,
                  onAccept: () async {
                    // Confirma el pedido de parte del restaurante — a partir
                    // de aquí ya se vuelve visible/tomable para repartidores
                    // (antes esto marcaba directo 'accepted', el mismo
                    // estado que usa un repartidor al reclamarlo — un
                    // repartidor ya podía tomar el pedido ANTES de que el
                    // restaurante confirmara nada).
                    await SupabaseService.adminUpdateOrderStatus(
                        filtered[i]['id'] as String, 'restaurant_accepted');
                    _loadRealOrders();
                  },
                  onCancel: () async {
                    await SupabaseService.updateOrderStatus(
                        filtered[i]['id'] as String, 'cancelled');
                    _loadRealOrders();
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _buildMenu(AppDataProvider appData) {
    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: _categories.map((cat) {
          final preseeded = _products.where((p) => p.categoryIds.contains(cat.id)).toList();
          final extra = appData.extraProductsForCategory(_restaurantId, cat.id);
          if (preseeded.isEmpty && extra.isEmpty) return const SizedBox();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(cat.name,
                      style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  Text('(${preseeded.length + extra.length})',
                      style: TextStyle(color: _textLow, fontSize: 13)),
                ]),
              ),
              ...preseeded.map((p) {
                final avail = appData.getProductAvailability(p.id, p.isAvailable);
                return _ProductTile(
                  product: p,
                  isAvailable: avail,
                  isDark: _isDark,
                  onToggle: () {
                    appData.setProductAvailability(p.id, !avail);
                    SupabaseService.setProductAvailability(p.id, !avail);
                  },
                  onEdit: () => _showProductForm(p, isExtra: false),
                );
              }),
              ...extra.map((sp) {
                final p = _Product(
                  id: sp.id, name: sp.name, description: sp.description,
                  price: sp.price, isAvailable: sp.isAvailable,
                  categoryIds: sp.categoryIds, imagePath: sp.imagePath,
                );
                final avail = appData.getProductAvailability(sp.id, sp.isAvailable);
                return _ProductTile(
                  product: p,
                  isAvailable: avail,
                  isDark: _isDark,
                  onToggle: () {
                    appData.setProductAvailability(sp.id, !avail);
                    SupabaseService.setProductAvailability(sp.id, !avail);
                  },
                  onEdit: () => _showProductForm(p, isExtra: true),
                );
              }),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton.extended(
          backgroundColor: Colors.blue,
          onPressed: () {
            if (_products.length >= _maxProductos) {
              _showLimiteProductosDialog();
              return;
            }
            _showProductForm(null, isExtra: false);
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Nuevo platillo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }

  void _showPromoLockedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Promociones por platillo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Pon descuentos o 2x1 en tus platillos con GOGO Premium.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendido', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
        ],
      ),
    );
  }

  void _showLimiteProductosDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Llegaste al límite de platillos',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          _isPremium
              ? 'Con GOGO Premium puedes tener hasta $_maxProductosPremium platillos, y ya los usaste todos.'
              : 'El plan gratuito permite hasta $_maxProductosGratis platillos. Con GOGO Premium puedes tener hasta $_maxProductosPremium.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendido', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
        ],
      ),
    );
  }

  void _showProductForm(_Product? existing, {bool isExtra = false}) {
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final descCtrl  = TextEditingController(text: existing?.description ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? existing.price.toStringAsFixed(0) : '');
    List<String> selectedCatIds = existing?.categoryIds.toList() ?? [_categories.first.id];
    bool available = existing?.isAvailable ?? true;
    String? pickedImagePath = existing?.imagePath;
    // Se guarda aparte (inmutable) porque más abajo pickedImagePath/existing.imagePath
    // se sobreescriben con la foto nueva ANTES de decidir qué URL mandar a Supabase —
    // sin esto no había forma de recuperar la foto buena si la subida nueva fallaba.
    final String? originalImageUrl = existing?.imagePath;
    final picker = ImagePicker();

    // Promo state
    // hadPromoData: ya tenía descuento/2x1 configurado (activo o ya expirado).
    // promoTouched: el dueño interactuó con la sección de promo en esta sesión de edición.
    // Si NO se toca la sección de promo, al guardar se conserva tal cual lo que ya
    // había en Supabase (aunque haya expirado) — así el dueño puede editar otros
    // campos del platillo sin borrar sin querer un descuento vencido que quería reactivar después.
    final bool hadPromoData = existing != null &&
        (existing.promoDiscountPercent != null || existing.promoIs2x1);
    bool isPromoMode = existing?.isPromoActive ?? false;
    int? selectedDiscount = existing?.promoDiscountPercent;
    bool is2x1 = existing?.promoIs2x1 ?? false;
    int selectedDurationHours = 2;
    bool promoTouched = false;

    Future<void> pickImage(ImageSource source, StateSetter setModal) async {
      final messenger = ScaffoldMessenger.of(context);
      final xfile = await picker.pickImage(source: source, imageQuality: 80);
      if (xfile == null) return;
      final previousUrl = pickedImagePath;
      setModal(() => pickedImagePath = xfile.path);

      // Leer bytes directamente del XFile (más confiable que File(path) en Android)
      final bytes = await xfile.readAsBytes();
      final uploaded = await SupabaseService.uploadProductImageBytes(bytes, ownerId: _restaurantId);
      if (uploaded != null) {
        setModal(() => pickedImagePath = uploaded);
        // Cada foto se sube con nombre nuevo (timestamp) — sin este borrado,
        // la que se reemplaza se queda huérfana en el bucket para siempre.
        if (previousUrl != null && previousUrl.startsWith('http') && previousUrl != uploaded) {
          unawaited(SupabaseService.deleteImageByUrl(previousUrl));
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Foto subida correctamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Fallback: copiar a directorio permanente (solo funciona en el mismo celular)
      if (!kIsWeb) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final permanent = await File(xfile.path).copy('${dir.path}/$fileName');
          setModal(() => pickedImagePath = permanent.path);
        } catch (_) {}
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo subir a la nube. Verifica conexión.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFF5722),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20,
            MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 24,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text(
                existing == null ? 'Nuevo platillo' : 'Editar platillo',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ]),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: ctx,
                backgroundColor: AppConstants.surfaceColor,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 12),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: AppConstants.primaryColor),
                      ),
                      title: const Text('Tomar foto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text('Abre la cámara', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                      onTap: () { Navigator.pop(ctx); pickImage(ImageSource.camera, setModal); },
                    ),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library, color: Color(0xFF2196F3)),
                      ),
                      title: const Text('Elegir de galería', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text('Selecciona una foto', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                      onTap: () { Navigator.pop(ctx); pickImage(ImageSource.gallery, setModal); },
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
              child: Container(
                width: double.infinity, height: 150,
                decoration: BoxDecoration(
                  color: AppConstants.surface2Color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pickedImagePath != null
                        ? AppConstants.primaryColor.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: pickedImagePath != null
                    ? Stack(fit: StackFit.expand, children: [
                        (kIsWeb || pickedImagePath!.startsWith('http'))
                            ? Image.network(pickedImagePath!, fit: BoxFit.cover)
                            : Image.file(File(pickedImagePath!), fit: BoxFit.cover),
                        Positioned(
                          bottom: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.edit, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text('Cambiar', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ]),
                          ),
                        ),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined,
                            color: Colors.white.withValues(alpha: 0.3), size: 36),
                        const SizedBox(height: 8),
                        Text('Agregar foto del platillo',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Cámara o galería',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                      ]),
              ),
            ),
            const SizedBox(height: 14),

            // ── Normal / Promo toggle ────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setModal(() { isPromoMode = false; promoTouched = true; }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: !isPromoMode ? Colors.white : Colors.white12,
                      child: Text('Normal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: !isPromoMode ? AppConstants.primaryColor : Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!_isPremium) {
                        _showPromoLockedDialog();
                        return;
                      }
                      setModal(() { isPromoMode = true; promoTouched = true; });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: isPromoMode ? Colors.white : Colors.white12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!_isPremium) ...[
                            Icon(Icons.lock, size: 13,
                                color: isPromoMode ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.6)),
                            const SizedBox(width: 5),
                          ],
                          Text('Promo',
                            style: TextStyle(
                              color: isPromoMode ? AppConstants.primaryColor : Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),

            // ── Promo config (solo cuando isPromoMode == true) ──────────────
            if (isPromoMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Preview del platillo
                  Row(children: [
                    if (pickedImagePath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 54, height: 54,
                          child: (kIsWeb || pickedImagePath!.startsWith('http'))
                              ? Image.network(pickedImagePath!, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(color: Colors.white12))
                              : Image.file(File(pickedImagePath!), fit: BoxFit.cover),
                        ),
                      )
                    else
                      Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.fastfood, color: Colors.white38, size: 28),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          nameCtrl.text.trim().isEmpty ? 'Nombre del platillo' : nameCtrl.text.trim(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedCatIds.map((id) {
                            try { return _categories.firstWhere((c) => c.id == id).name; } catch (_) { return ''; }
                          }).where((s) => s.isNotEmpty).join(', '),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                        ),
                      ]),
                    ),
                  ]),

                  const SizedBox(height: 14),
                  Text('Descuento', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  // Botones de descuento 5%…50% + 2x1
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      ...[5, 10, 15, 20, 25, 30, 35, 40, 45, 50].map((pct) {
                        final sel = selectedDiscount == pct;
                        return GestureDetector(
                          onTap: () => setModal(() {
                            selectedDiscount = sel ? null : pct;
                            promoTouched = true;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? Colors.white : Colors.white12,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? Colors.white : Colors.white38),
                            ),
                            child: Text('-$pct%',
                              style: TextStyle(
                                color: sel ? AppConstants.primaryColor : Colors.white,
                                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }),
                      GestureDetector(
                        onTap: () => setModal(() { is2x1 = !is2x1; promoTouched = true; }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: is2x1 ? Colors.white : Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: is2x1 ? Colors.white : Colors.white38),
                          ),
                          child: Text('2x1',
                            style: TextStyle(
                              color: is2x1 ? AppConstants.primaryColor : Colors.white,
                              fontWeight: is2x1 ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Text('Duración', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      {'h': 1, 'label': '1h'},
                      {'h': 2, 'label': '2h'},
                      {'h': 3, 'label': '3h'},
                      {'h': 5, 'label': '5h'},
                      {'h': 12, 'label': '12h'},
                      {'h': 24, 'label': '1 día'},
                      {'h': 48, 'label': '2 días'},
                      {'h': 120, 'label': '5 días'},
                    ].map((opt) {
                      final h = opt['h'] as int;
                      final label = opt['label'] as String;
                      final sel = selectedDurationHours == h;
                      return GestureDetector(
                        onTap: () => setModal(() {
                          selectedDurationHours = h;
                          promoTouched = true;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? Colors.white : Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? Colors.white : Colors.white38),
                          ),
                          child: Text(label,
                            style: TextStyle(
                              color: sel ? AppConstants.primaryColor : Colors.white,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 14),

            Text('Categorías', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _categories.map((c) {
                final selected = selectedCatIds.contains(c.id);
                return GestureDetector(
                  onTap: () => setModal(() {
                    if (selected) {
                      if (selectedCatIds.length > 1) selectedCatIds.remove(c.id);
                    } else {
                      selectedCatIds.add(c.id);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? Colors.white : Colors.white38),
                    ),
                    child: Text(
                      '${c.emoji} ${c.name}',
                      style: TextStyle(
                        color: selected ? AppConstants.primaryColor : Colors.white,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _FormField(controller: nameCtrl,  label: 'Nombre del platillo', icon: Icons.fastfood_outlined, maxLength: 15, isDark: false),
            const SizedBox(height: 12),
            _FormField(controller: descCtrl,  label: 'Descripción',         icon: Icons.notes, maxLines: 2, maxLength: 30, isDark: false),
            const SizedBox(height: 12),
            _FormField(controller: priceCtrl, label: 'Precio (MXN)',        icon: Icons.attach_money, keyboardType: TextInputType.number, isDark: false),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.storefront_outlined, color: Colors.white.withValues(alpha: 0.5), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Disponible en el menú',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                ),
                Switch(
                  value: available,
                  activeThumbColor: Colors.blue,
                  onChanged: (v) => setModal(() => available = v),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                  if (nameCtrl.text.trim().isEmpty || price <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('El nombre y precio son obligatorios (precio > 0)'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }
                  final appData = context.read<AppDataProvider>();
                  final newId = existing?.id ?? 'ep${DateTime.now().millisecondsSinceEpoch}';
                  final name = nameCtrl.text.trim();
                  final desc = descCtrl.text.trim();

                  if (existing == null) {
                    if (SupabaseService.useMock) {
                      appData.addExtraProduct(SharedProduct(
                        id: newId, name: name, description: desc,
                        price: price, isAvailable: available,
                        categoryIds: List<String>.from(selectedCatIds), restaurantId: _restaurantId,
                        imagePath: pickedImagePath,
                      ));
                    }
                  } else if (isExtra) {
                    appData.updateExtraProduct(SharedProduct(
                      id: existing.id, name: name, description: desc,
                      price: price, isAvailable: available,
                      categoryIds: List<String>.from(selectedCatIds), restaurantId: _restaurantId,
                      imagePath: pickedImagePath,
                    ));
                    appData.setProductAvailability(existing.id, available);
                  } else {
                    setState(() {
                      existing.name = name; existing.description = desc;
                      existing.price = price; existing.isAvailable = available;
                      existing.imagePath = pickedImagePath;
                    });
                    appData.setProductAvailability(existing.id, available);
                  }

                  // Solo guardar URL pública en Supabase (no ruta local) — si la
                  // foto nueva no se subió (pickedImagePath quedó como ruta
                  // local), se conserva la que ya estaba guardada en vez de
                  // borrarla con null.
                  final urlForDb = (pickedImagePath?.startsWith('http') == true)
                      ? pickedImagePath
                      : (originalImageUrl?.startsWith('http') == true ? originalImageUrl : null);

                  final int? promoDiscount;
                  final bool promo2x1;
                  final DateTime? promoExpires;
                  if (!promoTouched && hadPromoData) {
                    // El dueño no tocó la sección de promo: conserva tal cual
                    // lo que ya había (aunque haya expirado), para que un
                    // descuento vencido no se borre solo al editar otra cosa
                    // del platillo — así se puede reactivar después sin
                    // volver a configurarlo desde cero.
                    promoDiscount = existing.promoDiscountPercent;
                    promo2x1      = existing.promoIs2x1;
                    promoExpires  = existing.promoExpiresAt;
                  } else {
                    promoDiscount = isPromoMode ? selectedDiscount : null;
                    promo2x1      = isPromoMode && is2x1;
                    promoExpires  = isPromoMode && (promoDiscount != null || promo2x1)
                        ? DateTime.now().add(Duration(hours: selectedDurationHours))
                        : null;
                  }

                  await SupabaseService.saveProduct(
                    id: newId, name: name, description: desc,
                    price: price, isAvailable: available,
                    categoryId: selectedCatIds.first,
                    restaurantId: _restaurantId,
                    imageUrl: urlForDb,
                    promoDiscountPercent: promoDiscount,
                    promoIs2x1: promo2x1,
                    promoExpiresAt: promoExpires,
                  );
                  if (!SupabaseService.useMock) await _loadProductsFromSupabase();

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  existing == null ? 'AGREGAR PLATILLO' : 'GUARDAR CAMBIOS',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _loadBanners() async {
    if (!mounted) return;
    setState(() => _loadingBanners = true);
    final banners = await SupabaseService.getBanners(_restaurantId);
    if (!mounted) return;
    setState(() { _bannerList = banners; _loadingBanners = false; });
  }

  // Pantalla de "función bloqueada" para lo que solo viene con GOGO Premium.
  Widget _buildPremiumLocked({required IconData icon, required String title, required String description}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Text(description,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.workspace_premium, color: AppConstants.primaryColor, size: 18),
              const SizedBox(width: 8),
              Text('Disponible con GOGO Premium',
                  style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildBanners() {
    if (!_isPremium) {
      return _buildPremiumLocked(
        icon: Icons.campaign_outlined,
        title: 'Banners promocionales',
        description: 'Destaca tus platillos y promociones en la pantalla de inicio de los clientes. Disponible con GOGO Premium.',
      );
    }
    final colors = [
      const Color(0xFFE53935), const Color(0xFF43A047),
      const Color(0xFF1E88E5), const Color(0xFFFF6F00),
    ];
    Future<void> showAddSheet([RestaurantBanner? existing]) async {
      String imageUrl     = existing?.imageUrl ?? '';
      String title        = existing?.title ?? '';
      String subtitle     = existing?.subtitle ?? '';
      String badge        = existing?.badge ?? '';
      Color  badgeColor   = existing?.badgeColor ?? colors[0];
      String? productId   = existing?.productId;
      int? discount       = existing?.discountPercent;
      // null = "No expira" (el comportamiento de siempre). Si ya traía una
      // fecha futura, no se puede reconstruir en cuántas horas se puso
      // originalmente — se deja en "No expira" hasta que el dueño elija
      // una duración nueva a propósito.
      int? bannerDurationHours;

      final titleCtrl    = TextEditingController(text: title);
      final subtitleCtrl = TextEditingController(text: subtitle);
      final badgeCtrl    = TextEditingController(text: badge);
      final imageCtrl    = TextEditingController(text: imageUrl);
      final discountCtrl = TextEditingController(text: discount?.toString() ?? '');

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: _surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(existing == null ? 'Nuevo banner' : 'Editar banner',
                    style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Preview de imagen
                if (imageCtrl.text.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(imageCtrl.text, height: 120, width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                const SizedBox(height: 8),

                // URL de imagen
                _field(imageCtrl, 'URL de imagen', _inputFill, _text, _textMid,
                    onChanged: (v) { setModal(() {}); }),
                const SizedBox(height: 10),

                // Subir imagen
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(
                        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
                    if (xfile == null) return;
                    final previousUrl = imageCtrl.text.trim();
                    final bytes = await xfile.readAsBytes();
                    final url = await SupabaseService.uploadProfilePhotoBytes(
                        bytes, 'banner_${_restaurantId}_${DateTime.now().millisecondsSinceEpoch}');
                    if (url == null) {
                      // Antes fallaba en silencio — el dueño no se enteraba
                      // de que la foto del banner nunca se subió.
                      messenger.showSnackBar(SnackBar(
                          content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError ?? "sin conexión"}).'),
                          backgroundColor: Colors.redAccent));
                      return;
                    }
                    setModal(() => imageCtrl.text = url);
                    // Cada foto se sube con nombre nuevo (timestamp) — sin
                    // este borrado, la que se reemplaza se queda huérfana.
                    if (previousUrl.startsWith('http') && previousUrl != url) {
                      unawaited(SupabaseService.deleteImageByUrl(previousUrl));
                    }
                  },
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Subir foto', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: BorderSide(color: Colors.white30)),
                ),
                const SizedBox(height: 10),

                _field(titleCtrl, 'Título', _inputFill, _text, _textMid),
                const SizedBox(height: 10),
                _field(subtitleCtrl, 'Subtítulo', _inputFill, _text, _textMid),
                const SizedBox(height: 10),
                // Con producto vinculado el badge se genera solo a partir del
                // % de descuento (más abajo) — aquí solo se pide texto libre
                // para banners sin producto (ej. "NUEVO").
                if (productId == null) ...[
                  _field(badgeCtrl, 'Badge (ej. "20% OFF", "NUEVO")', _inputFill, _text, _textMid),
                  const SizedBox(height: 14),
                ],

                // Color del badge
                Text('Color del badge', style: TextStyle(color: _textMid, fontSize: 12)),
                const SizedBox(height: 6),
                Row(children: List.generate(4, (i) => GestureDetector(
                  onTap: () => setModal(() => badgeColor = colors[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 10),
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: badgeColor == colors[i] ? Colors.white : Colors.transparent,
                          width: 3),
                    ),
                    child: badgeColor == colors[i]
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ))),
                const SizedBox(height: 14),

                // Duración — antes este formulario no tenía forma de ponerle
                // tiempo límite a un banner, así que se quedaban activos
                // para siempre aunque el dueño pensara que ya se iban a
                // quitar solos.
                Text('Duración', style: TextStyle(color: _textMid, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    {'h': null, 'label': 'No expira'},
                    {'h': 1, 'label': '1h'},
                    {'h': 2, 'label': '2h'},
                    {'h': 3, 'label': '3h'},
                    {'h': 5, 'label': '5h'},
                    {'h': 12, 'label': '12h'},
                    {'h': 24, 'label': '1 día'},
                    {'h': 48, 'label': '2 días'},
                    {'h': 120, 'label': '5 días'},
                  ].map((opt) {
                    final h = opt['h'] as int?;
                    final label = opt['label'] as String;
                    final sel = bannerDurationHours == h;
                    return GestureDetector(
                      onTap: () => setModal(() => bannerDurationHours = h),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? AppConstants.primaryColor : _inputFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppConstants.primaryColor : Colors.white24),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                color: sel ? Colors.white : _textMid,
                                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Producto vinculado
                Text('Producto vinculado (opcional)', style: TextStyle(color: _textMid, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  value: productId,
                  dropdownColor: _surface2,
                  style: TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true, fillColor: _inputFill,
                    hintText: 'Sin producto vinculado',
                    hintStyle: TextStyle(color: _textLow, fontSize: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  items: [
                    DropdownMenuItem<String?>(value: null,
                        child: Text('— Sin producto —', style: TextStyle(color: _textLow))),
                    ..._products.map((p) => DropdownMenuItem<String?>(
                        value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setModal(() { productId = v; }),
                ),
                const SizedBox(height: 10),

                // Descuento — este mismo número arma el badge visual (ej. "-10%"),
                // ya no hace falta escribirlo dos veces.
                if (productId != null) ...[
                  _field(discountCtrl, 'Descuento % (ej. 10)', _inputFill, _text, _textMid,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 6),
                  Text('Deja vacío si no hay descuento', style: TextStyle(color: _textLow, fontSize: 11)),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 6),
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder()),
                    onPressed: () async {
                      if (imageCtrl.text.trim().isEmpty) return;
                      final discountValue = int.tryParse(discountCtrl.text.trim());
                      // Con producto vinculado el badge se deriva del % de descuento;
                      // sin producto se usa el texto libre que escribió el dueño.
                      final resolvedBadge = productId != null
                          ? (discountValue != null ? '-$discountValue%' : '')
                          : badgeCtrl.text.trim();
                      final banner = RestaurantBanner(
                        id: existing?.id ?? '',
                        restaurantId: _restaurantId,
                        imageUrl: imageCtrl.text.trim(),
                        title: titleCtrl.text.trim(),
                        subtitle: subtitleCtrl.text.trim(),
                        badge: resolvedBadge,
                        badgeColor: badgeColor,
                        productId: productId,
                        discountPercent: discountValue,
                        expiresAt: bannerDurationHours == null
                            ? null
                            : DateTime.now().add(Duration(hours: bannerDurationHours!)),
                        sortOrder: existing?.sortOrder ?? _bannerList.length,
                      );
                      Navigator.pop(ctx);
                      await SupabaseService.upsertBanner(banner);
                      _loadBanners();
                    },
                    child: const Text('Guardar banner',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )),
          );
        }),
      );
    }

    return Stack(children: [
      _loadingBanners
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _bannerList.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.campaign_outlined, size: 64, color: Colors.white30),
                    const SizedBox(height: 16),
                    Text('Sin banners todavía',
                        style: TextStyle(color: _textMid, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Toca + para agregar tu primer banner promocional',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textLow, fontSize: 13)),
                  ]),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _bannerList.length,
                  itemBuilder: (_, i) {
                    final b = _bannerList[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: _surface2, borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Imagen
                        Stack(children: [
                          Image.network(b.imageUrl, height: 110, width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                  height: 110, color: Colors.white10,
                                  child: const Center(child: Icon(Icons.broken_image, color: Colors.white30)))),
                          // Badge overlay
                          if (b.badge.isNotEmpty)
                            Positioned(top: 10, left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: b.badgeColor, borderRadius: BorderRadius.circular(6)),
                                child: Text(b.badge,
                                    style: const TextStyle(color: Colors.white,
                                        fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ]),
                        // Info
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (b.title.isNotEmpty)
                                Text(b.title, style: TextStyle(color: _text,
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                              if (b.subtitle.isNotEmpty)
                                Text(b.subtitle, style: TextStyle(color: _textMid, fontSize: 12)),
                              if (b.productId != null) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.link, size: 12, color: _textLow),
                                  const SizedBox(width: 4),
                                  Text(
                                    _products.firstWhere((p) => p.id == b.productId,
                                        orElse: () => _Product(id: '', name: '—', description: '',
                                            price: 0, isAvailable: true, categoryIds: [])).name,
                                    style: TextStyle(color: _textLow, fontSize: 11)),
                                  if (b.discountPercent != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4)),
                                      child: Text('-${b.discountPercent}%',
                                          style: const TextStyle(color: Colors.greenAccent,
                                              fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ]),
                              ],
                            ])),
                            Row(children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: _textMid, size: 20),
                                onPressed: () => showAddSheet(b),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () async {
                                  await SupabaseService.deleteBanner(b.id);
                                  // Antes solo se borraba la fila — la foto
                                  // se quedaba huérfana en el bucket.
                                  unawaited(SupabaseService.deleteImageByUrl(b.imageUrl));
                                  _loadBanners();
                                },
                              ),
                            ]),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
      Positioned(
        bottom: 20, right: 20,
        child: FloatingActionButton(
          backgroundColor: Colors.blue,
          onPressed: () => showAddSheet(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    ]);
  }

  static Widget _field(TextEditingController ctrl, String hint, Color fill, Color text, Color hintColor,
      {void Function(String)? onChanged, TextInputType keyboardType = TextInputType.text}) =>
      TextField(
        controller: ctrl,
        style: TextStyle(color: text, fontSize: 14),
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          filled: true, fillColor: fill,
          hintText: hint, hintStyle: TextStyle(color: hintColor, fontSize: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  Widget _buildPerfilRestaurante() {
    Future<void> pickPhoto() async {
      final messenger = ScaffoldMessenger.of(context);
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final url = await SupabaseService.uploadProfilePhotoBytes(bytes, 'restaurant_$_restaurantId');
      if (url == null) {
        // Antes fallaba en silencio — el dueño no se enteraba de que su
        // logo/foto nunca se guardó.
        messenger.showSnackBar(SnackBar(
            content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError ?? "sin conexión"}).'),
            backgroundColor: Colors.redAccent));
        return;
      }
      try {
        await AuthService.saveRestaurantSettings(photo: url);
        await SupabaseService.updateRestaurantLogo(_restaurantId, url);
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('La foto se subió pero no se pudo guardar en tu restaurante: $e'),
            backgroundColor: Colors.redAccent));
        return;
      }
      if (mounted) setState(() => _restPhoto = url);
    }

    Future<void> pickAddress() async {
      final result = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(initial: _restLatLng),
        ),
      );
      if (result == null || !mounted) return;
      final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
      setState(() {
        _restLatLng  = result;
        _restAddress = addr ?? '${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)}';
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        // ── Foto/logo del restaurante — un solo control (antes había otro
        // recuadro grande arriba que hacía exactamente lo mismo) ────────────
        Center(
          child: GestureDetector(
            onTap: pickPhoto,
            child: Stack(
              children: [
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _surface,
                    border: Border.all(color: AppConstants.primaryColor, width: 2.5),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _restPhoto.isNotEmpty
                      ? Image.network(_restPhoto, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(child: Text(_restEmoji, style: const TextStyle(fontSize: 50))))
                      : Center(child: Text(_restEmoji, style: const TextStyle(fontSize: 50))),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 32, height: 32,
                    decoration: const BoxDecoration(
                      color: AppConstants.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 28),

        // ── Campos de texto — fondo blanco (antes usaban el naranja oscuro
        // del panel del dueño, ya no hace juego con el resto de la pantalla) ──
        _RestField(controller: _restNameCtrl,  label: 'Nombre del restaurante', icon: Icons.storefront_outlined,
            fill: Colors.white, text: const Color(0xFF1A1A1A), textMid: Colors.black54),
        const SizedBox(height: 12),
        _RestField(controller: _restDescCtrl,  label: 'Descripción',            icon: Icons.notes_outlined, maxLines: 3,
            fill: Colors.white, text: const Color(0xFF1A1A1A), textMid: Colors.black54),
        const SizedBox(height: 12),
        _RestField(controller: _restPhoneCtrl, label: 'Teléfono de contacto',   icon: Icons.phone_outlined, keyboardType: TextInputType.phone,
            fill: Colors.white, text: const Color(0xFF1A1A1A), textMid: Colors.black54),
        const SizedBox(height: 12),

        // ── Dirección ───────────────────────────────────────────────────────
        // Web: campo de texto libre (el mapa no funciona en navegador)
        // Móvil: toca para abrir el mapa
        if (kIsWeb)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _restAddressCtrl,
              style: const TextStyle(color: Color(0xFF1A1A1A)),
              onChanged: (v) => _restAddress = v,
              decoration: InputDecoration(
                labelText: 'Dirección del local',
                labelStyle: const TextStyle(color: Colors.black54),
                prefixIcon: const Icon(Icons.location_on_outlined, color: AppConstants.primaryColor),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                hintText: 'Ej: Calle Morelos 45, Col. Centro',
                hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
              ),
            ),
          )
        else
          GestureDetector(
            onTap: pickAddress,
            child: AbsorbPointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: TextEditingController(text: _restAddress),
                  readOnly: true,
                  style: const TextStyle(color: Color(0xFF1A1A1A)),
                  decoration: InputDecoration(
                    labelText: 'Dirección del local',
                    labelStyle: const TextStyle(color: Colors.black54),
                    prefixIcon: const Icon(Icons.location_on_outlined, color: AppConstants.primaryColor),
                    suffixIcon: const Icon(Icons.map_outlined, color: AppConstants.primaryColor, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'Toca para ubicar en el mapa',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),

        // ── Zona — se detecta sola según la dirección, no se elige a mano ──────
        Row(children: [
          Icon(Icons.location_on, color: AppConstants.primaryColor, size: 16),
          const SizedBox(width: 6),
          Text('Zona: ${LocationService.zonaLabel(_restZona)}',
              style: TextStyle(color: _textMid, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text('Se detecta sola según la dirección del local',
            style: TextStyle(color: _textLow, fontSize: 11)),
        const SizedBox(height: 24),

        // ── Categoría del restaurante — lista fija, para el filtro del cliente ──
        Text('Categoría de tu restaurante',
            style: TextStyle(color: _textMid, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Así te encuentran los clientes que filtran por categoría',
            style: TextStyle(color: _textLow, fontSize: 11)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kRestaurantCategories.map((cat) {
            final selected = _restCategorias.contains(cat);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _restCategorias.remove(cat);
                } else {
                  _restCategorias.add(cat);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? AppConstants.primaryColor : _surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cat,
                    style: TextStyle(
                      color: selected ? Colors.white : _textMid,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                    )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),

        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.privacy_tip_outlined, color: AppConstants.primaryColor),
            ),
            title: const Text('Política de Privacidad',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4)),
            onTap: () => context.push('/privacy-policy'),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: () async {
              await AuthService.saveRestaurantSettings(
                name:    _restNameCtrl.text.trim(),
                desc:    _restDescCtrl.text.trim(),
                phone:   _restPhoneCtrl.text.trim(),
                address: _restAddress,
                emoji:   _restEmoji,
              );
              if (!SupabaseService.useMock) {
                final zona = _restLatLng != null
                    ? LocationService.zonaFromCoords(_restLatLng!.latitude, _restLatLng!.longitude)
                    : await LocationService.detectZona(_restAddress);
                await SupabaseService.updateRestaurantZona(_restaurantId, zona);
                if (mounted) setState(() => _restZona = zona);
                await SupabaseService.updateRestaurantCategorias(_restaurantId, _restCategorias.toList());
                // Antes esto solo se guardaba en el caché local del
                // dispositivo — nunca llegaba a Supabase, así que un
                // cliente nunca veía el nombre/descripción/dirección
                // actualizados, y se perdía todo al reinstalar la app.
                await SupabaseService.updateRestaurantProfile(
                  restaurantId: _restaurantId,
                  name: _restNameCtrl.text.trim(),
                  description: _restDescCtrl.text.trim(),
                  address: _restAddress,
                  emoji: _restEmoji,
                );
              }
              if (!mounted) return;
              setState(() {
                _restName  = _restNameCtrl.text.trim();
                _restDesc  = _restDescCtrl.text.trim();
                _restPhone = _restPhoneCtrl.text.trim();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('¡Cambios guardados!'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            icon: const Icon(Icons.save_outlined),
            label: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(int pendingCount) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            _NavItem(icon: Icons.dashboard_outlined,     index: 0, current: _tab, onTap: (i) => setState(() => _tab = i)),
            _NavItem(icon: Icons.receipt_long_outlined,  index: 1, current: _tab, onTap: (i) => setState(() => _tab = i), badge: pendingCount),
            _NavItem(icon: Icons.menu_book_outlined,     index: 2, current: _tab, onTap: (i) => setState(() => _tab = i)),
            _NavItem(icon: Icons.campaign_outlined,      index: 4, current: _tab, onTap: (i) => setState(() => _tab = i)),
            _NavItem(icon: Icons.storefront_outlined,    index: 3, current: _tab, onTap: (i) => setState(() => _tab = i)),
          ]),
        ),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value, suffix;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _StatCard({required this.label, required this.value, required this.suffix, required this.icon, required this.color, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textLow = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black54;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const Spacer(),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
        Text(label, style: TextStyle(color: textLow, fontSize: 11)),
      ]),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  const _StatusLegend(this.label, this.color, this.count);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 10)),
    ]);
  }
}

class _RealOrderMiniRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isDark;
  const _RealOrderMiniRow({required this.order, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}
    final name  = delivery['name'] as String? ?? 'Cliente';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final items = (order['order_items'] as List<dynamic>? ?? []);
    final itemNames = items.map((i) {
      final qty = i['quantity'] as int? ?? 1;
      final product = i['products'] as Map<String, dynamic>?;
      return '$qty× ${product?['name'] ?? 'Producto'}';
    }).join(', ');

    final (statusLabel, statusColor) = switch (status) {
      'pending'             => ('Pendiente',   const Color(0xFFFFB300)),
      'restaurant_accepted' => ('Confirmado',  const Color(0xFF00BFA5)),
      'accepted'            => ('Aceptado',    AppConstants.primaryColor),
      'delivering'          => ('En camino',   const Color(0xFF2196F3)),
      'delivered'           => ('Entregado',   Colors.green),
      'cancelled'           => ('Cancelado',   Colors.red),
      _                     => ('Desconocido', Colors.grey),
    };

    final surface = isDark ? const Color(0xFFE64A19) : Colors.white;
    final text    = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textLow = isDark ? Colors.white38 : Colors.black38;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 13)),
            Text(itemNames.isEmpty ? 'Sin productos' : itemNames,
                style: TextStyle(color: textLow, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${total.toStringAsFixed(0)}',
              style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 13)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _RealOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAccept;
  final VoidCallback? onCancel;
  final bool isDark;
  const _RealOrderCard({required this.order, required this.onAccept, this.onCancel, this.isDark = true});

  void _showDetail(BuildContext context) {
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}

    final status  = order['status'] as String? ?? 'pending';
    final name    = delivery['name']    as String? ?? 'Cliente';
    final phone   = delivery['phone']   as String? ?? '—';
    final address = delivery['address'] as String? ?? 'Sin dirección';
    final payment = delivery['payment'] as String? ?? 'cash';
    final total   = (order['total'] as num?)?.toDouble() ?? 0;
    final items   = (order['order_items'] as List<dynamic>? ?? []);

    const modalBg   = Color(0xFFFF5722);
    const cardBg    = Color(0xFFE64A19);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: modalBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx2, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(status == 'pending' ? 'Pendiente' : (status == 'restaurant_accepted' ? 'Confirmado' : 'Aceptado'),
                  style: TextStyle(
                    color: status == 'pending' ? const Color(0xFFFFE082) : const Color(0xFFB9F6CA),
                    fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(phone,   style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
          const SizedBox(height: 2),
          Text(address, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
          const SizedBox(height: 2),
          Text('Pago: ${payment == 'cash' ? '💵 Efectivo' : payment == 'card' ? '💳 Tarjeta' : 'OXXO'}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 16),
          const Text('Productos pedidos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          ...items.map((i) {
            final qty     = i['quantity'] as int? ?? 1;
            final product = i['products'] as Map<String, dynamic>?;
            final pname   = product?['name'] as String? ?? 'Producto';
            final price   = (i['price'] as num?)?.toDouble() ?? 0;
            final notes   = i['notes'] as String? ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text('$qty', style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(pname,
                        style: const TextStyle(color: Colors.white, fontSize: 14))),
                    Text('\$${(price * qty).toStringAsFixed(0)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ]),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.notes, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(notes,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11, fontStyle: FontStyle.italic)),
                      ),
                    ]),
                  ],
                ],
              ),
            );
          }),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
            Text('\$${total.toStringAsFixed(0)} MXN',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
        ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try { delivery = jsonDecode(order['customer_name'] as String? ?? '{}') as Map<String, dynamic>; } catch (_) {}

    final name    = delivery['name']    as String? ?? 'Cliente';
    final phone   = delivery['phone']   as String? ?? '—';
    final address = delivery['address'] as String? ?? 'Sin dirección';
    final total   = (order['total'] as num?)?.toDouble() ?? 0;
    final items   = (order['order_items'] as List<dynamic>? ?? []);

    final (statusLabel, statusColor) = switch (status) {
      'pending'             => ('Pendiente',   const Color(0xFFFFB300)),
      'restaurant_accepted' => ('Confirmado',  const Color(0xFF00BFA5)),
      'accepted'            => ('Aceptado',    AppConstants.primaryColor),
      'delivering'          => ('En camino',   const Color(0xFF2196F3)),
      'delivered'           => ('Entregado',   Colors.green),
      _                     => ('Desconocido', Colors.grey),
    };

    final surface = isDark ? const Color(0xFFE64A19) : Colors.white;
    final text    = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textLow = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black45;
    final textMin = isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black26;

    final itemCount = items.fold<int>(0, (s, i) => s + ((i['quantity'] as int?) ?? 1));

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${(order['id'] as String).substring(4, 10)}',
              style: TextStyle(color: textMin, fontSize: 11)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(name, style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text(phone, style: TextStyle(color: textLow, fontSize: 12)),
        const SizedBox(height: 2),
        Text(address, style: TextStyle(color: textLow, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Text('\$${total.toStringAsFixed(0)} MXN',
              style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long_outlined, size: 14, color: statusColor),
              const SizedBox(width: 5),
              Text('Ver $itemCount producto${itemCount != 1 ? 's' : ''}',
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
        // "Aceptar"/"Rechazar" solo mientras el pedido sigue pendiente — antes
        // estos callbacks existían (onAccept/onCancel) pero no había ningún
        // botón real en esta tarjeta que los llamara, así que el restaurante
        // no tenía manera de confirmar/rechazar un pedido desde aquí.
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Rechazar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Aceptar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ]),
        ],
      ]),
    ),
  );
  }
}

class _ProductTile extends StatelessWidget {
  final _Product product;
  final bool isAvailable;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _ProductTile({required this.product, required this.isAvailable, required this.onToggle, required this.onEdit, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    final surface  = isDark ? const Color(0xFFE64A19) : Colors.white;
    final surface2 = isDark ? const Color(0xFFD84315) : const Color(0xFFEEEEEE);
    final text     = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textLow  = isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black45;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isAvailable ? null : Border.all(color: textLow.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: product.imagePath != null
              ? ((kIsWeb || product.imagePath!.startsWith('http'))
                  ? Image.network(product.imagePath!, width: 60, height: 60, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(width: 60, height: 60, color: surface2, child: Icon(Icons.fastfood_outlined, color: textLow, size: 26)))
                  : Image.file(File(product.imagePath!), width: 60, height: 60, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(width: 60, height: 60, color: surface2, child: Icon(Icons.fastfood_outlined, color: textLow, size: 26))))
              : Container(width: 60, height: 60, color: surface2, child: Icon(Icons.fastfood_outlined, color: textLow, size: 26)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name,
                style: TextStyle(
                    color: isAvailable ? text : textLow,
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(product.description,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textLow, fontSize: 12)),
            const SizedBox(height: 6),
            Text('\$${product.price.toStringAsFixed(0)} MXN',
                style: TextStyle(
                    color: isAvailable ? AppConstants.primaryColor : textLow,
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.edit_outlined, color: textLow, size: 20),
          onPressed: onEdit,
        ),
        Switch(
          value: isAvailable,
          activeThumbColor: Colors.blue,
          onChanged: (_) => onToggle(),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final AppOrderStatus? value;
  final AppOrderStatus? current;
  final ValueChanged<AppOrderStatus?> onTap;
  const _FilterChip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final color = value == null ? AppConstants.primaryColor : appOrderStatusStyle(value!).color;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : color.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index, current;
  final int badge;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.index, required this.current, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final color = active ? Colors.blue : AppConstants.primaryColor;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, color: color, size: 24),
            if (badge > 0)
              Positioned(
                right: 20, top: 6,
                child: Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// Campo de texto con el color naranja del panel del dueño (a juego con
// el campo de dirección), en vez del gris oscuro genérico de _FormField.
class _RestField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final Color fill;
  final Color text;
  final Color textMid;
  const _RestField({
    required this.controller, required this.label, required this.icon,
    this.maxLines = 1, this.keyboardType,
    required this.fill, required this.text, required this.textMid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: TextStyle(color: text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: textMid),
          prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
          filled: true,
          fillColor: fill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool isDark;
  const _FormField({required this.controller, required this.label, required this.icon, this.maxLines = 1, this.maxLength, this.keyboardType, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    final text     = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textMid  = isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54;
    final fillColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: TextStyle(color: text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textMid),
        prefixIcon: Icon(icon, color: textMid, size: 20),
        counterStyle: TextStyle(color: textMid, fontSize: 11),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.primaryColor)),
      ),
    );
  }
}
