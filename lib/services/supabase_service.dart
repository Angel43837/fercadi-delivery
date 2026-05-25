import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // Cambia a false cuando configures Supabase con tus credenciales reales
  static const bool useMock = false;

  // ── Crear buckets de Storage automáticamente ─────────────────────────────────

  static Future<void> ensureStorageBuckets() async {
    if (useMock) return;
    final key = AppConstants.supabaseServiceRoleKey;
    if (key.isEmpty) return; // Sin service key no podemos crear buckets
    for (final bucket in ['product-images', 'profile-photos']) {
      try {
        await http.post(
          Uri.parse('${AppConstants.supabaseUrl}/storage/v1/bucket'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: '{"id":"$bucket","name":"$bucket","public":true}',
        );
      } catch (_) {}
    }
  }

  // ── Mock data ──────────────────────────────────────────────────────────────

  static final _mockRestaurants = [
    const Restaurant(
      id: '1',
      name: 'McDonalds',
      description: 'La mejor comida rápida',
      address: 'Av. Principal #123, Maravatío',
      rating: 4.5,
    ),
    const Restaurant(
      id: '2',
      name: 'Starbucks',
      description: 'Café de especialidad',
      address: 'Centro Histórico, Maravatío',
      rating: 4.8,
    ),
    const Restaurant(
      id: '3',
      name: 'Sushi Roll',
      description: 'Lo mejor del Japón en tu ciudad',
      address: 'Plaza Comercial, Maravatío',
      rating: 4.2,
    ),
  ];

  static final _mockCategories = <String, List<Category>>{
    '1': [
      const Category(id: 'c1', restaurantId: '1', name: 'Hamburguesas', icon: '🍔'),
      const Category(id: 'c2', restaurantId: '1', name: 'Papas', icon: '🍟'),
      const Category(id: 'c3', restaurantId: '1', name: 'Bebidas', icon: '🥤'),
      const Category(id: 'c10', restaurantId: '1', name: 'Postres', icon: '🍦'),
      const Category(id: 'c11', restaurantId: '1', name: 'Ensaladas', icon: '🥗'),
      const Category(id: 'c12', restaurantId: '1', name: 'Desayunos', icon: '🥞'),
    ],
    '2': [
      const Category(id: 'c4', restaurantId: '2', name: 'Cafés', icon: '☕'),
      const Category(id: 'c5', restaurantId: '2', name: 'Frappés', icon: '🧋'),
      const Category(id: 'c6', restaurantId: '2', name: 'Comida', icon: '🥐'),
    ],
    '3': [
      const Category(id: 'c7', restaurantId: '3', name: 'Rolls', icon: '🍣'),
      const Category(id: 'c8', restaurantId: '3', name: 'Entradas', icon: '🥢'),
      const Category(id: 'c9', restaurantId: '3', name: 'Postres', icon: '🍮'),
    ],
  };

  static final _mockProducts = <String, List<Product>>{
    'c1': [
      const Product(id: 'p1', categoryId: 'c1', name: 'Big Mac', description: 'La hamburguesa clásica con doble carne y salsa especial', price: 89),
      const Product(id: 'p2', categoryId: 'c1', name: 'Quarter Pounder', description: 'Jugosa y deliciosa con queso cheddar', price: 95),
      const Product(id: 'p3', categoryId: 'c1', name: 'McPollo Crispy', description: 'Pechuga crujiente con lechuga y mayo', price: 79),
    ],
    'c2': [
      const Product(id: 'p4', categoryId: 'c2', name: 'Papas Medianas', description: 'Crujientes y bien saladas', price: 35),
      const Product(id: 'p5', categoryId: 'c2', name: 'Papas Grandes', description: 'Para compartir o para ti solo', price: 45),
    ],
    'c3': [
      const Product(id: 'p6', categoryId: 'c3', name: 'Coca-Cola Grande', description: 'Refresco bien frío con hielo', price: 30),
      const Product(id: 'p7', categoryId: 'c3', name: 'Milkshake Chocolate', description: 'Cremoso y delicioso', price: 55),
    ],
    'c4': [
      const Product(id: 'p8', categoryId: 'c4', name: 'Café Americano', description: 'Clásico y aromático, doble shot', price: 65),
      const Product(id: 'p9', categoryId: 'c4', name: 'Café Latte', description: 'Suave y cremoso con leche vaporizada', price: 75),
    ],
    'c5': [
      const Product(id: 'p10', categoryId: 'c5', name: 'Frappé Oreo', description: 'Frío, cremoso y cargado de Oreos', price: 95),
      const Product(id: 'p11', categoryId: 'c5', name: 'Smoothie Tropical', description: 'Mango, piña y maracuyá', price: 85),
    ],
    'c6': [
      const Product(id: 'p12', categoryId: 'c6', name: 'Croissant de Jamón', description: 'Recién horneado con jamón y queso', price: 55),
    ],
    'c7': [
      const Product(id: 'p13', categoryId: 'c7', name: 'California Roll', description: '8 piezas de camarón, aguacate y pepino', price: 120),
      const Product(id: 'p14', categoryId: 'c7', name: 'Dragon Roll', description: '8 piezas premium con tuna y aguacate', price: 145),
    ],
    'c8': [
      const Product(id: 'p15', categoryId: 'c8', name: 'Edamame', description: 'Frijoles japoneses con sal de mar', price: 55),
      const Product(id: 'p16', categoryId: 'c8', name: 'Gyozas', description: '6 piezas de dumplings al vapor', price: 85),
    ],
    'c9': [
      const Product(id: 'p17', categoryId: 'c9', name: 'Mochi de Fresa', description: 'Postre japonés suave y dulce', price: 45),
    ],
  };

  // ── Métodos públicos ───────────────────────────────────────────────────────

  static Future<List<Restaurant>> getRestaurants() async {
    if (useMock) return _mockRestaurants;
    final data = await _client.from('restaurants').select().eq('is_open', true);
    return (data as List).map((e) => Restaurant.fromJson(e)).toList();
  }

  static Future<List<Category>> getCategories(String restaurantId) async {
    if (useMock) return _mockCategories[restaurantId] ?? [];
    final data = await _client
        .from('categories')
        .select()
        .eq('restaurant_id', restaurantId);
    return (data as List).map((e) => Category.fromJson(e)).toList();
  }

  static Future<List<Product>> getProducts(String categoryId) async {
    if (useMock) return _mockProducts[categoryId] ?? [];
    final data = await _client
        .from('products')
        .select()
        .eq('category_id', categoryId)
        .eq('is_available', true);
    return (data as List).map((e) => Product.fromJson(e)).toList();
  }

  static Future<List<({String name, String icon, List<Product> products})>>
      getMenuSections(String restaurantId) async {
    if (useMock) {
      final cats = _mockCategories[restaurantId] ?? [];
      return [
        for (final cat in cats)
          (name: cat.name, icon: cat.icon ?? '🍽️', products: _mockProducts[cat.id] ?? []),
      ];
    }
    final catsData = await _client
        .from('categories')
        .select()
        .eq('restaurant_id', restaurantId);
    final sections =
        <({String name, String icon, List<Product> products})>[];
    for (final cat in catsData as List) {
      final prodsData = await _client
          .from('products')
          .select()
          .eq('category_id', cat['id'])
          .eq('is_available', true);
      sections.add((
        name: cat['name'] as String,
        icon: cat['emoji_icon'] as String? ?? '🍽️',
        products:
            (prodsData as List).map((e) => Product.fromJson(e)).toList(),
      ));
    }
    return sections;
  }

  static Future<List<Product>> getProductsForRestaurant(String restaurantId) async {
    if (useMock) return [];
    final data = await _client
        .from('products')
        .select()
        .eq('restaurant_id', restaurantId);
    return (data as List).map((e) => Product.fromJson(e)).toList();
  }

  static Future<String?> uploadProductImage(String localPath) async {
    if (useMock) return null;
    try {
      final file     = File(localPath);
      final bytes    = await file.readAsBytes();
      final ext      = localPath.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('product-images').uploadBinary(
        fileName, bytes,
        fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
      );
      return _client.storage.from('product-images').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfilePhotoBytes(Uint8List bytes, String userId) async {
    if (useMock) return null;
    try {
      final fileName = 'profile_$userId.jpg';
      await _client.storage.from('profile-photos').uploadBinary(
        fileName, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfilePhoto(String localPath, String userId) async {
    if (useMock) return null;
    try {
      final file     = File(localPath);
      final bytes    = await file.readAsBytes();
      final ext      = localPath.split('.').last.toLowerCase();
      final fileName = 'profile_$userId.$ext';
      await _client.storage.from('profile-photos').uploadBinary(
        fileName, bytes,
        fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
      );
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  // ── Likes de productos (realtime) ────────────────────────────────────────────

  static Future<Map<String, int>> getProductLikeCounts() async {
    if (useMock) return {};
    try {
      final data = await _client.from('product_likes').select('product_id');
      final counts = <String, int>{};
      for (final row in data as List) {
        final id = row['product_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (_) { return {}; }
  }

  static Future<Set<String>> getUserLikedProducts(String email) async {
    if (useMock || email.isEmpty) return {};
    try {
      final data = await _client
          .from('product_likes')
          .select('product_id')
          .eq('user_email', email);
      return {for (final r in data as List) r['product_id'] as String};
    } catch (_) { return {}; }
  }

  static Future<void> toggleProductLike(String productId, String email) async {
    if (useMock || email.isEmpty) return;
    try {
      final existing = await _client
          .from('product_likes')
          .select()
          .eq('product_id', productId)
          .eq('user_email', email)
          .maybeSingle();
      if (existing == null) {
        await _client.from('product_likes').insert({
          'product_id': productId,
          'user_email': email,
        });
      } else {
        await _client.from('product_likes')
            .delete()
            .eq('product_id', productId)
            .eq('user_email', email);
      }
    } catch (_) {}
  }

  static RealtimeChannel subscribeToProductLikes(void Function() onUpdate) {
    return _client
        .channel('product_likes_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_likes',
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  // ── Likes de restaurantes (realtime) ─────────────────────────────────────────

  static Future<Map<String, int>> getRestaurantLikeCounts() async {
    if (useMock) return {};
    try {
      final data = await _client.from('restaurant_likes').select('restaurant_id');
      final counts = <String, int>{};
      for (final row in data as List) {
        final id = row['restaurant_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (_) { return {}; }
  }

  static Future<Set<String>> getUserLikedRestaurants(String email) async {
    if (useMock || email.isEmpty) return {};
    try {
      final data = await _client
          .from('restaurant_likes')
          .select('restaurant_id')
          .eq('user_email', email);
      return {for (final r in data as List) r['restaurant_id'] as String};
    } catch (_) { return {}; }
  }

  static Future<void> toggleRestaurantLike(String restaurantId, String email) async {
    if (useMock || email.isEmpty) return;
    try {
      final existing = await _client
          .from('restaurant_likes')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('user_email', email)
          .maybeSingle();
      if (existing == null) {
        await _client.from('restaurant_likes').insert({
          'restaurant_id': restaurantId,
          'user_email': email,
        });
      } else {
        await _client.from('restaurant_likes')
            .delete()
            .eq('restaurant_id', restaurantId)
            .eq('user_email', email);
      }
    } catch (_) {}
  }

  static RealtimeChannel subscribeToRestaurantLikes(void Function() onUpdate) {
    return _client
        .channel('restaurant_likes_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_likes',
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  static Future<void> saveProduct({
    required String id,
    required String name,
    required String description,
    required double price,
    required bool isAvailable,
    required String categoryId,
    required String restaurantId,
    String? imageUrl,
  }) async {
    if (useMock) return;
    await _client.from('products').upsert({
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'is_available': isAvailable,
      'category_id': categoryId,
      'restaurant_id': restaurantId,
      'image_url': imageUrl,
    });
  }

  static Future<void> setProductAvailability(String productId, bool isAvailable) async {
    if (useMock) return;
    await _client.from('products').update({'is_available': isAvailable}).eq('id', productId);
  }

  // ── Tracking en tiempo real ────────────────────────────────────────────────

  static RealtimeChannel? _broadcastChannel;

  static Future<void> startLocationBroadcast(String orderId) async {
    _broadcastChannel = _client.channel('tracking:$orderId');
    _broadcastChannel!.subscribe();
  }

  static void broadcastLocation(double lat, double lng) {
    _broadcastChannel?.sendBroadcastMessage(
      event: 'location',
      payload: {'lat': lat, 'lng': lng},
    );
  }

  static void stopLocationBroadcast() {
    _broadcastChannel?.unsubscribe();
    _broadcastChannel = null;
  }

  static RealtimeChannel subscribeToLocation(
    String orderId,
    void Function(double lat, double lng) onUpdate,
  ) {
    final channel = _client.channel('tracking:$orderId');
    channel
        .onBroadcast(
          event: 'location',
          callback: (payload) {
            final lat = (payload['lat'] as num).toDouble();
            final lng = (payload['lng'] as num).toDouble();
            onUpdate(lat, lng);
          },
        )
        .subscribe();
    return channel;
  }

  // ── Pedidos ───────────────────────────────────────────────────────────────

  static Future<String> createOrder({
    required String restaurantId,
    required double total,
    required String customerName,
    required String customerPhone,
    required String address,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    double? lat,
    double? lng,
  }) async {
    final orderId = 'ord_${DateTime.now().millisecondsSinceEpoch}';
    final deliveryJson = jsonEncode({
      'name': customerName,
      'phone': customerPhone,
      'address': address,
      'payment': paymentMethod,
      'lat': lat,
      'lng': lng,
    });
    await _client.from('orders').insert({
      'id': orderId,
      'restaurant_id': restaurantId,
      'total': total,
      'status': 'pending',
      'customer_name': deliveryJson,
    });
    if (items.isNotEmpty) {
      await _client.from('order_items').insert(
        items.map((i) => {'order_id': orderId, ...i}).toList(),
      );
    }
    return orderId;
  }

  static Future<List<Map<String, dynamic>>> getActiveOrders() async {
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, products(id, name))')
        .inFilter('status', ['pending', 'accepted', 'delivering', 'delivered', 'cancelled'])
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getOrdersForRepartidor() async {
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, products(id, name))')
        .inFilter('status', ['pending', 'accepted'])
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateOrderStatus(String orderId, String status) async {
    await _client.from('orders').update({'status': status}).eq('id', orderId);
  }

  static Future<String?> getOrderStatus(String orderId) async {
    final data = await _client
        .from('orders')
        .select('status')
        .eq('id', orderId)
        .single();
    return data['status'] as String?;
  }

  static RealtimeChannel subscribeToOrders(void Function() onUpdate) {
    final channel = _client.channel('db_orders');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => onUpdate(),
        )
        .subscribe();
    return channel;
  }
}
