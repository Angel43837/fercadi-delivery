// admin_screen.dart
// Panel del administrador de la plataforma Grupo Fercadi.
// Solo accesible con rol "admin" (email: admin@fercadi.com).
// Permite ver todos los pedidos de todos los restaurantes,
// gestionar restaurantes, usuarios y configuración general de la plataforma.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/app_data_provider.dart';
import '../../services/auth_service.dart';
import '../../models/withdrawal_status.dart';
import '../../repositories/rider_withdrawal_repository.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

// ── Pantalla principal ───────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  // Índices del IndexedStack. Los 5 primeros son las pestañas visibles en la
  // barra inferior (Fase 1 del rediseño); del 5 en adelante son las pantallas
  // "viejas" que por ahora solo se abren desde el menú "Más" (Fase 5 las
  // migrará a rutas propias) — nada se quitó, solo se reordenó el acceso.
  static const _tabInicio = 0;
  static const _tabPedidos = 1;
  static const _tabTienda = 2;
  static const _tabEstadisticas = 3;
  static const _tabMas = 4;
  static const _tabRestaurantes = 5;
  static const _tabUsuarios = 6;
  static const _tabEventos = 7;
  static const _tabAlertas = 8;
  static const _tabConfig = 9;

  int _tab = 0;
  AppOrderStatus? _filterStatus;
  List<Map<String, dynamic>> _realOrders = [];
  List<Map<String, dynamic>> _restaurants = [];
  // Cuentas reales (tengan o no pedidos) — a diferencia del enfoque viejo,
  // que solo contaba IDs que ya aparecían en orders.repartidor_id.
  List<Map<String, dynamic>> _clientUsers = [];
  List<Map<String, dynamic>> _repartidorUsers = [];
  bool _loadingUsuarios = true;
  bool _loadingOrders = false;
  bool _loadingRestaurants = false;
  Timer? _pollTimer;

  // Eventos tab
  String _eventSearch = '';
  String? _eventStatusFilter;

  // Alertas tab
  List<Map<String, dynamic>> _alerts = [];
  String? _alertStatusFilter;

  // Estadísticas (Dashboard)
  List<Map<String, dynamic>> _topLikedRestaurants = [];
  List<Map<String, dynamic>> _topLikedProducts = [];
  List<Map<String, dynamic>> _topOrderedProducts = [];
  List<Map<String, dynamic>> _topOrderedRestaurants = [];

  // Config tab
  final _tarifaBaseCtrl = TextEditingController();
  final _tarifaKmCtrl = TextEditingController();
  bool _savingConfig = false;

  // Tienda de riders
  List<Map<String, dynamic>> _storeItems = [];
  bool _loadingStoreItems = false;

  // Retiros (solo el conteo de pendientes, para el badge en "Más")
  int _retirosPendientes = 0;
  final _withdrawalRepo = RiderWithdrawalRepository();

  @override
  void initState() {
    super.initState();
    _loadStoreItems();
    _loadOrders();
    _loadRestaurants();
    _loadUsuarios();
    _loadAlerts();
    _loadStats();
    _loadRetirosPendientes();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOrders();
      _loadRestaurants();
      _loadAlerts();
      _loadStats();
      _loadRetirosPendientes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppDataProvider>().initRestaurantLikes();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (_loadingOrders) return;
    _loadingOrders = true;
    try {
      final data = await SupabaseService.getActiveOrders();
      if (mounted)
        setState(() {
          _realOrders = data;
          _loadingOrders = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingOrders = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando pedidos: $e'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _loadingOrders = false;
      }
    }
  }

  Future<void> _loadRestaurants() async {
    if (_loadingRestaurants) return;
    _loadingRestaurants = true;
    try {
      final data = await SupabaseService.getRestaurantsAdmin();
      if (mounted)
        setState(() {
          _restaurants = data;
          _loadingRestaurants = false;
        });
    } catch (_) {
      _loadingRestaurants = false;
    }
  }

  // Cuentas reales de clientes/repartidores — tengan o no pedidos todavía.
  Future<void> _loadUsuarios() async {
    try {
      final clients = await SupabaseService.listUsersByRole(['cliente']);
      final riders = await SupabaseService.listUsersByRole([
        'repartidor',
        'repartidor_plus',
      ]);
      if (mounted) {
        setState(() {
          _clientUsers = clients;
          _repartidorUsers = riders;
          _loadingUsuarios = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsuarios = false);
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final data = await SupabaseService.getAlerts();
      if (mounted) setState(() => _alerts = data);
    } catch (_) {}
  }

  Future<void> _loadRetirosPendientes() async {
    try {
      final data = await _withdrawalRepo.fetchAllForAdmin();
      final count = data.where((w) => w['status'] == WithdrawalStatus.pendiente).length;
      if (mounted) setState(() => _retirosPendientes = count);
    } catch (_) {}
  }

  Future<void> _setAlertStatus(String alertId, String status) async {
    await SupabaseService.updateAlertStatus(alertId, status);
    await _loadAlerts();
  }

  Future<void> _showNewAlertDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'media';
    String category = 'otro';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppConstants.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Nueva alerta',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Título',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      filled: true,
                      fillColor: AppConstants.surface2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Descripción',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      filled: true,
                      fillColor: AppConstants.surface2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    dropdownColor: AppConstants.surface2Color,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppConstants.surface2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'critica',
                        child: Text('Crítica'),
                      ),
                      DropdownMenuItem(value: 'alta', child: Text('Alta')),
                      DropdownMenuItem(value: 'media', child: Text('Media')),
                      DropdownMenuItem(value: 'baja', child: Text('Baja')),
                    ],
                    onChanged: (v) => setS(() => priority = v ?? 'media'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    dropdownColor: AppConstants.surface2Color,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppConstants.surface2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'servidor',
                        child: Text('Servidor / app'),
                      ),
                      DropdownMenuItem(value: 'pagos', child: Text('Pagos')),
                      DropdownMenuItem(
                        value: 'restaurante',
                        child: Text('Restaurante'),
                      ),
                      DropdownMenuItem(
                        value: 'base_datos',
                        child: Text('Base de datos'),
                      ),
                      DropdownMenuItem(
                        value: 'conexion',
                        child: Text('Conexión externa'),
                      ),
                      DropdownMenuItem(value: 'otro', child: Text('Otro')),
                    ],
                    onChanged: (v) => setS(() => category = v ?? 'otro'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                await SupabaseService.createAlert(
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  priority: priority,
                  category: category,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadAlerts();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
              ),
              child: const Text(
                'Crear',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    descCtrl.dispose();
  }

  // ── Tienda de riders ─────────────────────────────────────────────────────────

  Future<void> _loadStoreItems() async {
    if (_loadingStoreItems) return;
    _loadingStoreItems = true;
    try {
      final data = await SupabaseService.getRiderStoreItems(onlyActive: false);
      if (mounted)
        setState(() {
          _storeItems = data;
          _loadingStoreItems = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingStoreItems = false);
    }
  }

  Future<void> _deleteStoreItem(String id, String? imageUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Eliminar producto?',
          style: TextStyle(color: AdminColors.textPrimary),
        ),
        content: Text(
          'Los riders ya no podrán canjearlo.',
          style: TextStyle(color: AdminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AdminColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AdminColors.statusCancelled),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await SupabaseService.deleteRiderStoreItem(id);
      // Sin esto la foto del premio se quedaba huérfana en el bucket para
      // siempre — solo se borraba la fila de la tabla.
      unawaited(SupabaseService.deleteImageByUrl(imageUrl));
      await _loadStoreItems();
    }
  }

  Future<void> _showStoreItemForm({Map<String, dynamic>? existing}) async {
    final emojiCtrl = TextEditingController(
      text: existing?['emoji'] as String? ?? '🎁',
    );
    final nameCtrl = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final descCtrl = TextEditingController(
      text: existing?['description'] as String? ?? '',
    );
    final coinsCtrl = TextEditingController(
      text: existing?['cost_coins']?.toString() ?? '',
    );
    final imageCtrl = TextEditingController(
      text: existing?['image_url'] as String? ?? '',
    );
    bool activo = existing?['is_active'] as bool? ?? true;

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AdminColors.textFaint),
      filled: true,
      fillColor: AdminColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );

    final picker = ImagePicker();
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> pickImage(ImageSource source) async {
            final messenger = ScaffoldMessenger.of(context);
            final xfile = await picker.pickImage(
              source: source,
              imageQuality: 80,
            );
            if (xfile == null) return;
            final previousUrl = imageCtrl.text.trim();
            setS(() => uploading = true);
            final bytes = await xfile.readAsBytes();
            final url = await SupabaseService.uploadProductImageBytes(bytes);
            setS(() => uploading = false);
            if (url != null) {
              imageCtrl.text = url;
              setS(() {});
              // Cada foto se sube con nombre nuevo (timestamp) — sin este
              // borrado, la que se reemplaza se queda huérfana en el bucket.
              if (previousUrl.startsWith('http') && previousUrl != url) {
                unawaited(SupabaseService.deleteImageByUrl(previousUrl));
              }
            } else {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('No se pudo subir la foto (${SupabaseService.lastUploadError ?? "sin conexión"}).'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }

          void showPickerSheet() => showModalBottomSheet(
            context: ctx,
            backgroundColor: AdminColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(Icons.camera_alt, color: AdminColors.accent),
                    title: const Text(
                      'Tomar foto',
                      style: TextStyle(
                        color: AdminColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      pickImage(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.photo_library,
                      color: AdminColors.accent,
                    ),
                    title: const Text(
                      'Elegir de galería',
                      style: TextStyle(
                        color: AdminColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      pickImage(ImageSource.gallery);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );

          return AlertDialog(
            backgroundColor: AdminColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AdminRadii.card),
            ),
            title: Text(
              existing == null ? 'Nuevo producto' : 'Editar producto',
              style: const TextStyle(
                color: AdminColors.textPrimary,
                fontSize: 17,
              ),
            ),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: uploading ? null : showPickerSheet,
                      child: Container(
                        width: double.infinity,
                        height: 130,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AdminColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AdminColors.accent.withValues(
                              alpha: imageCtrl.text.isNotEmpty ? 0.5 : 0.15,
                            ),
                          ),
                        ),
                        child: uploading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AdminColors.accent,
                                  strokeWidth: 2,
                                ),
                              )
                            : imageCtrl.text.isNotEmpty
                            ? Image.network(
                                imageCtrl.text,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.broken_image_outlined,
                                  color: AdminColors.textFaint,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    color: AdminColors.textFaint,
                                    size: 26,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Agregar foto',
                                    style: TextStyle(
                                      color: AdminColors.textFaint,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emojiCtrl,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      decoration: deco('Emoji (ej. 🎁)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      decoration: deco('Nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      decoration: deco('Descripción'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: coinsCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AdminColors.textPrimary),
                      decoration: deco('Costo en coins'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Activo (visible en la tienda)',
                        style: TextStyle(
                          color: AdminColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      value: activo,
                      activeThumbColor: AdminColors.accent,
                      onChanged: (v) => setS(() => activo = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: AdminColors.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final coins = int.tryParse(coinsCtrl.text.trim());
                  if (name.isEmpty || coins == null) return;
                  final payload = {
                    'emoji': emojiCtrl.text.trim().isEmpty
                        ? '🎁'
                        : emojiCtrl.text.trim(),
                    'name': name,
                    'description': descCtrl.text.trim(),
                    'cost_coins': coins,
                    'image_url': imageCtrl.text.trim(),
                    'is_active': activo,
                  };
                  if (existing == null) {
                    await SupabaseService.createRiderStoreItem(payload);
                  } else {
                    await SupabaseService.updateRiderStoreItem(
                      existing['id'] as String,
                      payload,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadStoreItems();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.accent,
                ),
                child: Text(
                  existing == null ? 'Crear' : 'Guardar',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    emojiCtrl.dispose();
    nameCtrl.dispose();
    descCtrl.dispose();
    coinsCtrl.dispose();
    imageCtrl.dispose();
  }

  Widget _buildTiendaRiders() {
    if (_storeItems.isEmpty) {
      return Center(
        child: Text(
          'Sin productos en la tienda todavía',
          style: TextStyle(color: AdminColors.textFaint),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _storeItems.length,
      itemBuilder: (_, i) {
        final item = _storeItems[i];
        final id = item['id'] as String;
        final active = item['is_active'] as bool? ?? true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  item['emoji'] as String? ?? '🎁',
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name'] as String? ?? '',
                        style: const TextStyle(
                          color: AdminColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${item['cost_coins']} coins',
                            style: TextStyle(
                              color: AdminColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!active)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AdminColors.textFaint.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Inactivo',
                                style: TextStyle(
                                  color: AdminColors.textFaint,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: AdminColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => _showStoreItemForm(existing: item),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AdminColors.statusCancelled,
                    size: 20,
                  ),
                  onPressed: () => _deleteStoreItem(id, item['image_url'] as String?),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadStats() async {
    final results = await Future.wait([
      SupabaseService.getTopLikedRestaurants(),
      SupabaseService.getTopLikedProducts(),
      SupabaseService.getTopOrderedProducts(),
      SupabaseService.getTopOrderedRestaurants(),
    ]);
    if (!mounted) return;
    setState(() {
      _topLikedRestaurants = results[0];
      _topLikedProducts = results[1];
      _topOrderedProducts = results[2];
      _topOrderedRestaurants = results[3];
    });
  }

  Future<
    ({
      List<Map<String, dynamic>> orders,
      double? avgRating,
      List<Map<String, dynamic>> ratings,
    })
  >
  _loadClientDetail(String customerId) async {
    final orders = await SupabaseService.getOrdersByCustomerId(customerId);
    final orderIds = orders.map((o) => o['id'] as String).toList();
    final allRatings = await SupabaseService.getRatingsForOrders(orderIds);
    // El repartidor califica al cliente -> is_driver: true
    final driverRatings = allRatings
        .where((r) => r['is_driver'] == true)
        .toList();
    final avg = driverRatings.isEmpty
        ? null
        : driverRatings.fold<int>(0, (s, r) => s + (r['stars'] as int? ?? 0)) /
              driverRatings.length;
    return (orders: orders, avgRating: avg, ratings: driverRatings);
  }

  Future<
    ({
      List<Map<String, dynamic>> orders,
      double? avgRating,
      List<Map<String, dynamic>> ratings,
    })
  >
  _loadRepartidorDetail(String repartidorId) async {
    final orders = await SupabaseService.getOrdersByRepartidor(repartidorId);
    final orderIds = orders.map((o) => o['id'] as String).toList();
    final allRatings = await SupabaseService.getRatingsForOrders(orderIds);
    // El cliente califica al repartidor -> is_driver: false
    final clientRatings = allRatings
        .where((r) => r['is_driver'] == false)
        .toList();
    final avg = clientRatings.isEmpty
        ? null
        : clientRatings.fold<int>(0, (s, r) => s + (r['stars'] as int? ?? 0)) /
              clientRatings.length;
    return (orders: orders, avgRating: avg, ratings: clientRatings);
  }

  void _showClientDetail(String customerId, String name, {String? avatarUrl}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UserDetailSheet(
        userId: customerId,
        title: name,
        subtitle: 'Historial y calificaciones',
        icon: Icons.person_outline,
        color: AppConstants.primaryColor,
        avatarUrl: avatarUrl,
        future: _loadClientDetail(customerId),
      ),
    );
  }

  void _showRepartidorDetail(
    String repartidorId,
    String name,
    Color color, {
    String? avatarUrl,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UserDetailSheet(
        userId: repartidorId,
        title: name,
        subtitle: 'Historial y calificaciones',
        icon: Icons.delivery_dining,
        color: color,
        avatarUrl: avatarUrl,
        isRider: true,
        future: _loadRepartidorDetail(repartidorId),
      ),
    );
  }

  Future<void> _changeOrderStatus(String orderId, String status) async {
    try {
      await SupabaseService.adminUpdateOrderStatus(orderId, status);
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appData = context.watch<AppDataProvider>();
    return Scaffold(
      backgroundColor: AdminColors.bg,
      // padding para que el FAB no quede encima de la barra inferior propia
      // (no es un BottomNavigationBar real, así que Scaffold no la conoce).
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: switch (_tab) {
          _tabAlertas => FloatingActionButton.extended(
            onPressed: _showNewAlertDialog,
            backgroundColor: AdminColors.accent,
            icon: const Icon(Icons.add_alert_outlined, color: Colors.white),
            label: const Text(
              'Nueva alerta',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _tabTienda => FloatingActionButton.extended(
            onPressed: () => _showStoreItemForm(),
            backgroundColor: AdminColors.accent,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Nuevo producto',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_tab > _tabMas) _buildVolverAMasBar(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _buildDashboard(appData),
                _buildPedidos(),
                _buildTiendaRiders(),
                _buildEstadisticasPlaceholder(),
                _buildMasMenu(),
                _buildRestaurantes(appData),
                _buildUsuarios(),
                _buildEventos(),
                _buildAlertas(),
                _buildConfig(),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  String _labelForTab(int i) => switch (i) {
    _tabRestaurantes => 'Restaurantes',
    _tabUsuarios => 'Clientes y repartidores',
    _tabEventos => 'Eventos',
    _tabAlertas => 'Alertas',
    _tabConfig => 'Configuración',
    _ => '',
  };

  Widget _buildVolverAMasBar() {
    return GestureDetector(
      onTap: () => setState(() => _tab = _tabMas),
      child: Container(
        width: double.infinity,
        color: AdminColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            const Icon(
              Icons.arrow_back_ios_new,
              color: AdminColors.accent,
              size: 14,
            ),
            const SizedBox(width: 8),
            Text(
              _labelForTab(_tab),
              style: const TextStyle(
                color: AdminColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Placeholders (Fase 1) ───────────────────────────────────────────────────
  // Flota (Fase 3) y Estadísticas (Fase 4) todavía no tienen pantalla propia;
  // esto evita mostrar una pestaña rota mientras se construyen por fases.

  Widget _buildProximamente(String titulo, String descripcion, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AdminColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AdminColors.accent, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              style: const TextStyle(
                color: AdminColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticasPlaceholder() => _buildProximamente(
    'Estadísticas',
    'Gráficas de ventas, horas pico y los rankings de la plataforma.',
    Icons.bar_chart_rounded,
  );

  // ── Más ──────────────────────────────────────────────────────────────────────

  Widget _buildMasMenu() {
    final alertasPendientes = _alerts
        .where((a) => a['status'] != 'resuelta')
        .length;
    final items = <(IconData, String, String, int, VoidCallback)>[
      (
        Icons.storefront_outlined,
        'Restaurantes',
        'Menús, horarios y estado',
        0,
        () => setState(() => _tab = _tabRestaurantes),
      ),
      (
        Icons.people_outline,
        'Clientes y repartidores',
        'Historial y calificaciones',
        0,
        () => setState(() => _tab = _tabUsuarios),
      ),
      (
        Icons.event_note_outlined,
        'Eventos',
        'Feed de actividad de pedidos',
        0,
        () => setState(() => _tab = _tabEventos),
      ),
      (
        Icons.notifications_active_outlined,
        'Alertas',
        'Incidentes de la plataforma',
        alertasPendientes,
        () => setState(() => _tab = _tabAlertas),
      ),
      (
        Icons.star_outline_rounded,
        'Reseñas',
        'Moderación de calificaciones',
        0,
        () => context.push('/admin/resenas'),
      ),
      (
        Icons.account_balance_wallet_outlined,
        'Retiros',
        'Solicitudes de pago a repartidores',
        _retirosPendientes,
        () => context.push('/admin/retiros'),
      ),
      (
        Icons.local_offer_outlined,
        'Promociones',
        'Cupones y descuentos reales',
        0,
        () => context.push('/admin/promociones'),
      ),
      (
        Icons.tune_outlined,
        'Configuración',
        'Tarifas y comisiones',
        0,
        () => setState(() => _tab = _tabConfig),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (icon, title, subtitle, badge, onTap) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: onTap,
              child: AdminSectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AdminColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AdminColors.accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AdminColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: AdminColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badge > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AdminColors.statusCancelled,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Icon(
                      Icons.chevron_right,
                      color: AdminColors.textFaint,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Finanzas, Promociones, Soporte y Reportes llegan más adelante.',
            style: TextStyle(color: AdminColors.textFaint, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: AdminColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                color: AdminColors.accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Panel de Administrador',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Grupo Fercadi • Maravatío',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'En línea',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.logout,
                color: Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              tooltip: 'Cerrar sesión',
              onPressed: () async {
                final router = GoRouter.of(context);
                await AuthService.clearSession();
                router.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Dashboard ────────────────────────────────────────────────────────────────

  Widget _buildDashboard(AppDataProvider appData) {
    final ventasHoy = _realOrders
        .where((o) => o['status'] == 'delivered')
        .fold<double>(0, (s, o) => s + ((o['total'] as num?)?.toDouble() ?? 0));
    final pedidosHoy = _realOrders.length;
    final entregados = _realOrders
        .where((o) => o['status'] == 'delivered')
        .length;
    final pendientes = _realOrders
        .where((o) => o['status'] == 'pending')
        .length;
    final enCamino = _realOrders
        .where((o) => o['status'] == 'delivering' || o['status'] == 'accepted' || o['status'] == 'restaurant_accepted')
        .length;
    final cancelados = _realOrders
        .where((o) => o['status'] == 'cancelled')
        .length;

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
            AdminStatCard(
              label: 'Ventas hoy',
              value: '\$${ventasHoy.toStringAsFixed(0)}',
              icon: Icons.attach_money,
              color: AdminColors.statusDelivered,
            ),
            AdminStatCard(
              label: 'Pedidos hoy',
              value: '$pedidosHoy',
              icon: Icons.receipt_long,
              color: AdminColors.accent,
            ),
            AdminStatCard(
              label: 'Entregados',
              value: '$entregados',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF00BFA5),
            ),
            AdminStatCard(
              label: 'Restaurantes',
              value: '${_restaurants.length}',
              icon: Icons.storefront,
              color: const Color(0xFFFFB300),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AdminSectionCard(
          title: 'Estado de pedidos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pedidosHoy > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      if (pendientes > 0)
                        Expanded(
                          flex: pendientes,
                          child: Container(
                            height: 10,
                            color: AdminColors.statusPending,
                          ),
                        ),
                      if (enCamino > 0)
                        Expanded(
                          flex: enCamino,
                          child: Container(
                            height: 10,
                            color: AdminColors.accent,
                          ),
                        ),
                      if (entregados > 0)
                        Expanded(
                          flex: entregados,
                          child: Container(
                            height: 10,
                            color: AdminColors.statusDelivered,
                          ),
                        ),
                      if (cancelados > 0)
                        Expanded(
                          flex: cancelados,
                          child: Container(
                            height: 10,
                            color: AdminColors.statusCancelled,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatusLegend(
                    'Pendiente',
                    AdminColors.statusPending,
                    pendientes,
                  ),
                  _StatusLegend('En camino', AdminColors.accent, enCamino),
                  _StatusLegend(
                    'Entregado',
                    AdminColors.statusDelivered,
                    entregados,
                  ),
                  _StatusLegend(
                    'Cancelado',
                    AdminColors.statusCancelled,
                    cancelados,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Últimos pedidos',
              style: TextStyle(
                color: AdminColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _tab = _tabPedidos),
              child: const Text(
                'Ver todos',
                style: TextStyle(color: AdminColors.accent, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._realOrders.take(4).map((o) => _RealOrderMiniRow(order: o)),
        const SizedBox(height: 24),
        const Text(
          'Estadísticas de la plataforma',
          style: TextStyle(
            color: AdminColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tendencias de todo el histórico de la plataforma',
          style: TextStyle(color: AdminColors.textFaint, fontSize: 12),
        ),
        const SizedBox(height: 14),
        _RankingCard(
          icon: Icons.storefront,
          iconColor: const Color(0xFFFFB300),
          title: 'Top restaurantes por likes',
          items: _topLikedRestaurants,
          suffix: 'likes',
        ),
        const SizedBox(height: 14),
        _RankingCard(
          icon: Icons.favorite,
          iconColor: Colors.pinkAccent,
          title: 'Top platillos por likes',
          items: _topLikedProducts,
          suffix: 'likes',
        ),
        const SizedBox(height: 14),
        _RankingCard(
          icon: Icons.restaurant_menu,
          iconColor: const Color(0xFF00BFA5),
          title: 'Platillos más pedidos',
          items: _topOrderedProducts,
          suffix: 'pedidos',
        ),
        const SizedBox(height: 14),
        _RankingCard(
          icon: Icons.trending_up,
          iconColor: AdminColors.accent,
          title: 'Restaurantes con más pedidos',
          items: _topOrderedRestaurants,
          suffix: 'pedidos',
        ),
      ],
    );
  }

  // ── Pedidos ──────────────────────────────────────────────────────────────────

  Widget _buildPedidos() {
    final filtered = _filterStatus == null
        ? _realOrders
        : _realOrders.where((o) {
            final s = o['status'] as String? ?? '';
            switch (_filterStatus) {
              case AppOrderStatus.pendiente:
                return s == 'pending';
              case AppOrderStatus.enCamino:
                return s == 'delivering' || s == 'accepted' || s == 'restaurant_accepted';
              case AppOrderStatus.entregado:
                return s == 'delivered';
              case AppOrderStatus.cancelado:
                return s == 'cancelled';
              default:
                return true;
            }
          }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _FilterChip(
                'Todos',
                null,
                _filterStatus,
                (v) => setState(() => _filterStatus = v),
              ),
              _FilterChip(
                'Pendiente',
                AppOrderStatus.pendiente,
                _filterStatus,
                (v) => setState(() => _filterStatus = v),
              ),
              _FilterChip(
                'En camino',
                AppOrderStatus.enCamino,
                _filterStatus,
                (v) => setState(() => _filterStatus = v),
              ),
              _FilterChip(
                'Entregado',
                AppOrderStatus.entregado,
                _filterStatus,
                (v) => setState(() => _filterStatus = v),
              ),
              _FilterChip(
                'Cancelado',
                AppOrderStatus.cancelado,
                _filterStatus,
                (v) => setState(() => _filterStatus = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Sin pedidos',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _RealOrderCard(
                    order: filtered[i],
                    onStatusChange: _changeOrderStatus,
                  ),
                ),
        ),
      ],
    );
  }

  // ── Restaurantes ─────────────────────────────────────────────────────────────

  Widget _buildRestaurantes(AppDataProvider appData) {
    if (_restaurants.isEmpty) {
      return Center(
        child: Text(
          'Sin restaurantes registrados',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _restaurants.length,
      itemBuilder: (_, i) {
        final r = _restaurants[i];
        final id = r['id'] as String? ?? '';
        final icon = r['emoji_icon'] as String? ?? '🍽️';
        final logoUrl = r['image_url'] as String?;
        final name = r['name'] as String? ?? 'Restaurante';
        final address = r['address'] as String? ?? '';
        final isOpen = appData.isRestaurantOpen(id);
        final likes = appData.getLikes(id);
        final ordersToday = _realOrders
            .where((o) => o['restaurant_id'] == id)
            .length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppConstants.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: isOpen
                ? Border.all(color: Colors.green.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Antes solo se mostraba el emoji genérico, aunque el
                  // restaurante ya tuviera un logo real subido (desde la
                  // app o desde el registro web) — ahora se prefiere la
                  // foto real cuando existe, con el emoji de respaldo para
                  // los restaurantes que todavía no tienen una.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (logoUrl != null && logoUrl.isNotEmpty)
                        ? Image.network(
                            logoUrl,
                            width: 36, height: 36, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Text(icon, style: const TextStyle(fontSize: 30)),
                          )
                        : Text(icon, style: const TextStyle(fontSize: 30)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          address,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => appData.setRestaurantOpen(id, !isOpen),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isOpen
                            ? Colors.green.withValues(alpha: 0.12)
                            : AppConstants.surface2Color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOpen
                              ? Colors.green.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        isOpen ? 'Abierto' : 'Cerrado',
                        style: TextStyle(
                          color: isOpen
                              ? Colors.green
                              : Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: AppConstants.surfaceColor,
                          title: const Text(
                            '¿Eliminar restaurante?',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: Text(
                            'Esto eliminará "$name" y todos sus productos, categorías y pedidos. Esta acción no se puede deshacer.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Eliminar',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await SupabaseService.deleteRestaurant(id);
                        _loadRestaurants();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(
                    label: 'Pedidos hoy',
                    value: '$ordersToday',
                    icon: Icons.receipt_long_outlined,
                    color: AppConstants.primaryColor,
                  ),
                  _MiniStat(
                    label: 'Likes',
                    value: '$likes',
                    icon: Icons.thumb_up,
                    color: AppConstants.primaryColor,
                  ),
                  _MiniStat(
                    label: 'Estado',
                    value: isOpen ? 'Activo' : 'Inactivo',
                    icon: Icons.circle,
                    color: isOpen ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Usuarios ─────────────────────────────────────────────────────────────────

  Widget _buildUsuarios() {
    // Pedidos/gasto por cliente real (orders.customer_id) y entregas por
    // repartidor real (orders.repartidor_id) — solo para la cifra que se
    // muestra en cada tarjeta. La LISTA en sí ahora sale de las cuentas
    // reales (_clientUsers/_repartidorUsers), no de quién ya hizo un
    // pedido, así que una cuenta nueva sin actividad todavía aparece.
    final Map<String, int> ordersByClient = {};
    final Map<String, double> totalByClient = {};
    final Map<String, int> entregasByRider = {};
    for (final o in _realOrders) {
      final cid = o['customer_id'] as String?;
      if (cid != null) {
        ordersByClient[cid] = (ordersByClient[cid] ?? 0) + 1;
        totalByClient[cid] =
            (totalByClient[cid] ?? 0) + ((o['total'] as num?)?.toDouble() ?? 0);
      }
      final rid = o['repartidor_id'] as String?;
      if (rid != null) entregasByRider[rid] = (entregasByRider[rid] ?? 0) + 1;
    }

    final repartidoreColors = [
      const Color(0xFF00BFA5),
      const Color(0xFF7C4DFF),
      const Color(0xFFFF6D00),
      const Color(0xFF2196F3),
      const Color(0xFFFFB300),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(
          icon: Icons.people_outline,
          label: 'Clientes (${_clientUsers.length})',
        ),
        const SizedBox(height: 10),
        if (_loadingUsuarios)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: AppConstants.primaryColor),
            ),
          )
        else if (_clientUsers.isEmpty)
          _EmptyHint('Sin clientes registrados aún')
        else
          ..._clientUsers.map((u) {
            final id = u['id'] as String;
            final orders = ordersByClient[id] ?? 0;
            final total = totalByClient[id] ?? 0.0;
            final rawName = (u['name'] as String?)?.trim();
            final name = (rawName != null && rawName.isNotEmpty)
                ? rawName
                : (u['email'] as String? ?? u['phone'] as String? ?? 'Cliente');
            return _UserTile(
              name: name,
              subtitle: (u['email'] as String?) ?? (u['phone'] as String?) ?? '—',
              trailing:
                  '$orders pedido${orders != 1 ? 's' : ''} • \$${total.toStringAsFixed(0)}',
              color: AppConstants.primaryColor,
              icon: Icons.person_outline,
              avatarUrl: u['avatarUrl'] as String?,
              onTap: () => _showClientDetail(
                id,
                name,
                avatarUrl: u['avatarUrl'] as String?,
              ),
            );
          }),
        const SizedBox(height: 24),

        _SectionTitle(
          icon: Icons.delivery_dining,
          label: 'Repartidores (${_repartidorUsers.length})',
        ),
        const SizedBox(height: 10),
        if (_loadingUsuarios)
          const SizedBox.shrink()
        else if (_repartidorUsers.isEmpty)
          _EmptyHint('Sin repartidores registrados aún')
        else
          ..._repartidorUsers.asMap().entries.map((entry) {
            final i = entry.key;
            final u = entry.value;
            final id = u['id'] as String;
            final entregas = entregasByRider[id] ?? 0;
            final color = repartidoreColors[i % repartidoreColors.length];
            final rawName = (u['name'] as String?)?.trim();
            final name = (rawName != null && rawName.isNotEmpty)
                ? rawName
                : 'Repartidor ${adminShortId(id)}';
            return _UserTile(
              name: name,
              subtitle: '$entregas entrega${entregas != 1 ? 's' : ''} totales',
              trailing: '$entregas entregas',
              color: color,
              icon: Icons.delivery_dining,
              avatarUrl: u['avatarUrl'] as String?,
              onTap: () => _showRepartidorDetail(
                id,
                name,
                color,
                avatarUrl: u['avatarUrl'] as String?,
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Eventos ──────────────────────────────────────────────────────────────────

  Widget _buildEventos() {
    final statuses = [
      'pending',
      'restaurant_accepted',
      'accepted',
      'delivering',
      'delivered',
      'cancelled',
    ];
    final statusLabels = {
      'pending': 'Pendiente',
      'restaurant_accepted': 'Confirmado',
      'accepted': 'Aceptado',
      'delivering': 'En camino',
      'delivered': 'Entregado',
      'cancelled': 'Cancelado',
    };
    final statusColors = {
      'pending': const Color(0xFFFFB300),
      'restaurant_accepted': const Color(0xFF00BFA5),
      'accepted': AppConstants.primaryColor,
      'delivering': const Color(0xFF2196F3),
      'delivered': Colors.green,
      'cancelled': Colors.red,
    };

    var filtered = _realOrders.where((o) {
      Map<String, dynamic> delivery = {};
      try {
        delivery =
            jsonDecode(o['customer_name'] as String? ?? '{}')
                as Map<String, dynamic>;
      } catch (_) {}
      final name = (delivery['name'] as String? ?? '').toLowerCase();
      final matchSearch =
          _eventSearch.isEmpty || name.contains(_eventSearch.toLowerCase());
      final matchStatus =
          _eventStatusFilter == null || o['status'] == _eventStatusFilter;
      return matchSearch && matchStatus;
    }).toList();

    return Column(
      children: [
        // buscador + filtro
        Container(
          color: AppConstants.surfaceColor,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              // buscador
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre de cliente...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 18,
                  ),
                  filled: true,
                  fillColor: AppConstants.surface2Color,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _eventSearch = v),
              ),
              const SizedBox(height: 8),
              // filtros de estado
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _EventChip(
                      label: 'Todos',
                      selected: _eventStatusFilter == null,
                      color: AppConstants.primaryColor,
                      onTap: () => setState(() => _eventStatusFilter = null),
                    ),
                    ...statuses.map(
                      (s) => _EventChip(
                        label: statusLabels[s]!,
                        selected: _eventStatusFilter == s,
                        color: statusColors[s]!,
                        onTap: () => setState(
                          () => _eventStatusFilter = _eventStatusFilter == s
                              ? null
                              : s,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // lista
        Expanded(
          child: _loadingOrders
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryColor,
                  ),
                )
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'Sin eventos',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final o = filtered[i];
                    final status = o['status'] as String? ?? 'pending';
                    Map<String, dynamic> delivery = {};
                    try {
                      delivery =
                          jsonDecode(o['customer_name'] as String? ?? '{}')
                              as Map<String, dynamic>;
                    } catch (_) {}
                    final name = delivery['name'] as String? ?? 'Cliente';
                    final address = delivery['address'] as String? ?? '—';
                    final total = (o['total'] as num?)?.toDouble() ?? 0;
                    final color = statusColors[status] ?? Colors.grey;
                    final label = statusLabels[status] ?? status;
                    final createdAt = o['created_at'] as String? ?? '';
                    String timeStr = '';
                    try {
                      final dt = DateTime.parse(createdAt).toLocal();
                      timeStr =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {}

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: color, width: 3),
                        ),
                      ),
                      child: Row(
                        children: [
                          // estado
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              status == 'pending'
                                  ? Icons.hourglass_top
                                  : status == 'restaurant_accepted'
                                  ? Icons.storefront_outlined
                                  : status == 'accepted'
                                  ? Icons.check_circle_outline
                                  : status == 'delivering'
                                  ? Icons.delivery_dining
                                  : status == 'delivered'
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (timeStr.isNotEmpty)
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Alertas ──────────────────────────────────────────────────────────────────

  Widget _buildAlertas() {
    final filtered = _alertStatusFilter == null
        ? _alerts
        : _alerts.where((a) => a['status'] == _alertStatusFilter).toList();
    final pendientes = _alerts.where((a) => a['status'] == 'pendiente').length;
    final enProceso = _alerts.where((a) => a['status'] == 'en_proceso').length;
    final criticas = _alerts
        .where((a) => a['priority'] == 'critica' && a['status'] != 'resuelta')
        .length;

    return Column(
      children: [
        Container(
          color: AppConstants.surfaceColor,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Pendientes',
                      value: '$pendientes',
                      icon: Icons.hourglass_top,
                      color: const Color(0xFFFFB300),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'En proceso',
                      value: '$enProceso',
                      icon: Icons.autorenew,
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'Críticas',
                      value: '$criticas',
                      icon: Icons.priority_high,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _EventChip(
                      label: 'Todas',
                      selected: _alertStatusFilter == null,
                      color: AppConstants.primaryColor,
                      onTap: () => setState(() => _alertStatusFilter = null),
                    ),
                    _EventChip(
                      label: 'Pendientes',
                      selected: _alertStatusFilter == 'pendiente',
                      color: const Color(0xFFFFB300),
                      onTap: () =>
                          setState(() => _alertStatusFilter = 'pendiente'),
                    ),
                    _EventChip(
                      label: 'En proceso',
                      selected: _alertStatusFilter == 'en_proceso',
                      color: const Color(0xFF2196F3),
                      onTap: () =>
                          setState(() => _alertStatusFilter = 'en_proceso'),
                    ),
                    _EventChip(
                      label: 'Resueltas',
                      selected: _alertStatusFilter == 'resuelta',
                      color: Colors.green,
                      onTap: () =>
                          setState(() => _alertStatusFilter = 'resuelta'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyHint(
                  'Sin alertas${_alertStatusFilter == null ? '' : ' en este estado'}',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _AlertCard(
                    alert: filtered[i],
                    onStatusChange: _setAlertStatus,
                  ),
                ),
        ),
      ],
    );
  }

  // ── Config ───────────────────────────────────────────────────────────────────

  Widget _buildConfig() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppConstants.surfaceColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    color: AppConstants.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Tarifas de Envío',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Costo = Tarifa base + (Tarifa por km × distancia)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              _ConfigField(
                label: 'Tarifa base (MXN)',
                hint: 'Ej. 15.0',
                controller: _tarifaBaseCtrl,
                current: '\$${LocationService.tarifaBase.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 14),
              _ConfigField(
                label: 'Tarifa por km (MXN/km)',
                hint: 'Ej. 5.0',
                controller: _tarifaKmCtrl,
                current:
                    '\$${LocationService.tarifaPorKm.toStringAsFixed(2)}/km',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _savingConfig ? null : _saveConfig,
                  child: _savingConfig
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Guardar tarifas',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    final base = double.tryParse(_tarifaBaseCtrl.text.trim());
    final km = double.tryParse(_tarifaKmCtrl.text.trim());
    if (base == null && km == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa al menos un valor válido'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _savingConfig = true);
    try {
      if (base != null) {
        await SupabaseService.setPlatformConfig('tarifa_base', base.toString());
        LocationService.tarifaBase = base;
      }
      if (km != null) {
        await SupabaseService.setPlatformConfig('tarifa_por_km', km.toString());
        LocationService.tarifaPorKm = km;
      }
      if (mounted) {
        _tarifaBaseCtrl.clear();
        _tarifaKmCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarifas actualizadas'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  // ── Bottom Nav ───────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    // Si _tab está en una de las pantallas "viejas" (>= _tabMas) abiertas
    // desde el menú Más, ese botón se muestra resaltado como "Más" activo.
    final current = _tab >= _tabMas ? _tabMas : _tab;
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Inicio',
              index: _tabInicio,
              current: current,
              onTap: (i) => setState(() => _tab = i),
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              label: 'Pedidos',
              index: _tabPedidos,
              current: current,
              onTap: (i) => setState(() => _tab = i),
            ),
            _NavItem(
              icon: Icons.card_giftcard_rounded,
              label: 'Tienda',
              index: _tabTienda,
              current: current,
              onTap: (i) => setState(() => _tab = i),
            ),
            _NavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Estadísticas',
              index: _tabEstadisticas,
              current: current,
              onTap: (i) => setState(() => _tab = i),
            ),
            _NavItem(
              icon: Icons.menu_rounded,
              label: 'Más',
              index: _tabMas,
              current: current,
              onTap: (i) => setState(() => _tab = i),
              badge: _alerts.where((a) => a['status'] != 'resuelta').length,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _RealOrderMiniRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _RealOrderMiniRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try {
      delivery =
          jsonDecode(order['customer_name'] as String? ?? '{}')
              as Map<String, dynamic>;
    } catch (_) {}
    final name = delivery['name'] as String? ?? 'Cliente';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final items = (order['order_items'] as List<dynamic>? ?? []);
    final itemNames = items
        .map((i) {
          final qty = i['quantity'] as int? ?? 1;
          final product = i['products'] as Map<String, dynamic>?;
          return '$qty× ${product?['name'] ?? 'Producto'}';
        })
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card - 6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AdminColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  itemNames.isEmpty ? 'Sin productos' : itemNames,
                  style: TextStyle(color: AdminColors.textFaint, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: AdminColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              AdminStatusBadge(status: status),
            ],
          ),
        ],
      ),
    );
  }
}

class _RealOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(String orderId, String status)? onStatusChange;
  const _RealOrderCard({required this.order, this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    Map<String, dynamic> delivery = {};
    try {
      delivery =
          jsonDecode(order['customer_name'] as String? ?? '{}')
              as Map<String, dynamic>;
    } catch (_) {}

    final name = delivery['name'] as String? ?? 'Cliente';
    final phone = delivery['phone'] as String? ?? '—';
    final address = delivery['address'] as String? ?? 'Sin dirección';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final items = (order['order_items'] as List<dynamic>? ?? []);
    final orderId = order['id'] as String? ?? '';

    final (statusLabel, statusColor) = switch (status) {
      'pending' => ('Pendiente', const Color(0xFFFFB300)),
      'restaurant_accepted' => ('Confirmado', const Color(0xFF00BFA5)),
      'accepted' => ('Aceptado', AppConstants.primaryColor),
      'delivering' => ('En camino', const Color(0xFF2196F3)),
      'delivered' => ('Entregado', Colors.green),
      'cancelled' => ('Cancelado', Colors.red),
      _ => ('Desconocido', Colors.grey),
    };

    final shortId = orderId.length >= 6
        ? orderId.substring(0, 6).toUpperCase()
        : orderId.toUpperCase();

    // Botones de acción según el estado actual
    final nextStatus = switch (status) {
      'pending' => 'restaurant_accepted',
      'restaurant_accepted' => 'accepted',
      'accepted' => 'delivering',
      'delivering' => 'delivered',
      _ => null,
    };
    final nextLabel = switch (status) {
      'pending' => 'Confirmar',
      'restaurant_accepted' => 'Aceptar',
      'accepted' => 'En camino',
      'delivering' => 'Entregado',
      _ => null,
    };
    final canCancel =
        status == 'pending' || status == 'restaurant_accepted' || status == 'accepted' || status == 'delivering';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$shortId',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            phone,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            address,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((i) {
            final qty = i['quantity'] as int? ?? 1;
            final product = i['products'] as Map<String, dynamic>?;
            final pname = product?['name'] as String? ?? 'Producto';
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 5,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$qty× $pname',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '\$${total.toStringAsFixed(0)} MXN',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (canCancel)
                GestureDetector(
                  onTap: () => onStatusChange?.call(orderId, 'cancelled'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (nextStatus != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onStatusChange?.call(orderId, nextStatus),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      nextLabel!,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String suffix;
  final List<Map<String, dynamic>> items;
  const _RankingCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.suffix,
    required this.items,
  });

  static const _medalColors = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin datos suficientes aún',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...items.take(10).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final rankColor = i < 3
                  ? _medalColors[i]
                  : Colors.white.withValues(alpha: 0.25);
              final restaurantName = item['restaurant_name'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: rankColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] as String? ?? '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (restaurantName.isNotEmpty)
                            Text(
                              restaurantName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${item['value']} $suffix',
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final Future<void> Function(String alertId, String status)? onStatusChange;
  const _AlertCard({required this.alert, this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final id = alert['id'] as String? ?? '';
    final title = alert['title'] as String? ?? 'Alerta';
    final description = alert['description'] as String?;
    final priority = alert['priority'] as String? ?? 'media';
    final status = alert['status'] as String? ?? 'pendiente';
    final createdAt = DateTime.tryParse(
      alert['created_at'] as String? ?? '',
    )?.toLocal();

    final (priorityLabel, priorityColor) = switch (priority) {
      'critica' => ('Crítica', Colors.red),
      'alta' => ('Alta', const Color(0xFFFF6D00)),
      'media' => ('Media', const Color(0xFFFFB300)),
      'baja' => ('Baja', Colors.grey),
      _ => (priority, Colors.grey),
    };
    final (statusLabel, statusColor) = switch (status) {
      'pendiente' => ('Pendiente', const Color(0xFFFFB300)),
      'en_proceso' => ('En proceso', const Color(0xFF2196F3)),
      'resuelta' => ('Resuelta', Colors.green),
      _ => (status, Colors.grey),
    };

    var timeStr = '';
    if (createdAt != null) {
      timeStr =
          '${createdAt.day}/${createdAt.month}/${createdAt.year} · '
          '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: priorityColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  priorityLabel,
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
          if (status != 'resuelta') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (status == 'pendiente') ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onStatusChange?.call(id, 'en_proceso'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2196F3),
                        side: const BorderSide(color: Color(0xFF2196F3)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'En proceso',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onStatusChange?.call(id, 'resuelta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      foregroundColor: Colors.green,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Marcar resuelta',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => onStatusChange?.call(id, 'pendiente'),
              child: Text(
                'Reabrir',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
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
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppConstants.primaryColor, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String name, subtitle, trailing;
  final Color color;
  final IconData icon;
  final String? avatarUrl;
  final VoidCallback? onTap;
  const _UserTile({
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.color,
    required this.icon,
    this.avatarUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipOval(
              child: Container(
                width: 40,
                height: 40,
                color: color.withValues(alpha: 0.15),
                child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                    ? Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(icon, color: color, size: 20),
                      )
                    : Icon(icon, color: color, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              trailing,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.25),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserDetailSheet extends StatelessWidget {
  final String userId;
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final String? avatarUrl;
  final bool isRider;
  final Future<
    ({
      List<Map<String, dynamic>> orders,
      double? avgRating,
      List<Map<String, dynamic>> ratings,
    })
  >
  future;
  const _UserDetailSheet({
    required this.userId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.avatarUrl,
    this.isRider = false,
    required this.future,
  });

  Future<void> _showDocs(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DriverDocsSheet(riderId: userId),
    );
  }

  Future<void> _sendMessage(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: const Text('Mandar mensaje', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Título',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Mensaje',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (sent != true) return;
    if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
    await SupabaseService.sendAdminMessage(
      recipientId: userId,
      title: titleCtrl.text.trim(),
      body: bodyCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje enviado'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: FutureBuilder(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryColor,
                  ),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error al cargar: ${snapshot.error}',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final data = snapshot.data!;
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Container(
                            width: 48,
                            height: 48,
                            color: color.withValues(alpha: 0.15),
                            child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                                ? Image.network(
                                    avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(icon, color: color, size: 24),
                                  )
                                : Icon(icon, color: color, size: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isRider)
                          IconButton(
                            onPressed: () => _showDocs(context),
                            icon: const Icon(Icons.badge_outlined, color: AppConstants.primaryColor),
                            tooltip: 'Ver documentos',
                          ),
                        IconButton(
                          onPressed: () => _sendMessage(context),
                          icon: const Icon(Icons.send_outlined, color: AppConstants.primaryColor),
                          tooltip: 'Mandar mensaje',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        if (data.avgRating != null) ...[
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < data.avgRating!.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: const Color(0xFFFFB300),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${data.avgRating!.toStringAsFixed(1)} (${data.ratings.length})',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ] else
                          Text(
                            'Sin calificaciones aún',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        if (data.ratings.isNotEmpty) ...[
                          Text(
                            'Reseñas (${data.ratings.length})',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...data.ratings.map(
                            (r) => _RatingRow(
                              stars: r['stars'] as int? ?? 0,
                              comment: r['comment'] as String?,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Historial de pedidos (${data.orders.length})',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (data.orders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'Sin pedidos',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                          )
                        else
                          ...data.orders.map(
                            (o) => _RealOrderMiniRow(order: o),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// Documentos del registro web de un repartidor (identificación, comprobante
// de domicilio) — null si la cuenta nunca pasó por ese registro (ej. los
// de flota, dados de alta directo en Supabase). Las imágenes llegan como
// URLs firmadas de corta duración, generadas por la Edge Function con
// service_role — el bucket es privado a propósito.
class _DriverDocsSheet extends StatelessWidget {
  final String riderId;
  const _DriverDocsSheet({required this.riderId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppConstants.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: SupabaseService.getDriverDocs(riderId),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: AppConstants.primaryColor),
                );
              }
              final driver = snapshot.data;
              if (driver == null) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Esta cuenta no se registró por la página web, así que '
                      'no tiene identificación ni comprobante guardados aquí.',
                      style: TextStyle(color: Colors.white60),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${driver['first_name'] ?? ''} ${driver['last_name'] ?? ''}'.trim(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${driver['vehicle'] ?? '—'} · ${driver['city'] ?? '—'}, ${driver['state'] ?? '—'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tipo de identificación: ${driver['id_type'] ?? '—'} · Estado: ${driver['status'] ?? '—'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _DocImage(title: 'Identificación — frente', url: driver['idFrontUrl'] as String?),
                  const SizedBox(height: 16),
                  _DocImage(title: 'Identificación — reverso', url: driver['idBackUrl'] as String?),
                  const SizedBox(height: 16),
                  _DocImage(title: 'Comprobante de domicilio', url: driver['proofUrl'] as String?),
                  const SizedBox(height: 16),
                  _DocImage(title: 'Foto de perfil', url: driver['photo_url'] as String?),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DocImage extends StatelessWidget {
  final String title;
  final String? url;
  const _DocImage({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: (url != null && url!.isNotEmpty)
              ? Image.network(
                  url!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 140,
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Text('No se pudo cargar', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                )
              : Container(
                  height: 100,
                  width: double.infinity,
                  color: Colors.white10,
                  alignment: Alignment.center,
                  child: const Text('No disponible', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
        ),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final int stars;
  final String? comment;
  const _RatingRow({required this.stars, this.comment});

  @override
  Widget build(BuildContext context) {
    final hasComment = comment != null && comment!.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: const Color(0xFFFFB300),
                size: 16,
              ),
            ),
          ),
          if (hasComment) ...[
            const SizedBox(height: 6),
            Text(
              comment!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final AppOrderStatus? value, current;
  final ValueChanged<AppOrderStatus?> onTap;
  const _FilterChip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final color = value == null
        ? AppConstants.primaryColor
        : appOrderStatusStyle(value!).color;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _EventChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _EventChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final String label, hint, current;
  final TextEditingController controller;
  const _ConfigField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'Actual: $current',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, current;
  final ValueChanged<int> onTap;
  final int badge;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    color: active
                        ? AppConstants.primaryColor
                        : Colors.white.withValues(alpha: 0.3),
                    size: 22,
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(minWidth: 15),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? AdminColors.accent
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
