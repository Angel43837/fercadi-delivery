import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/restaurant_banner.dart';
import 'auth_service.dart';

// supabase_service.dart
// Capa de acceso a datos — conecta la app con la base de datos de Supabase.
// Tiene dos modos:
//   useMock = true  → usa datos falsos hardcodeados (para desarrollo sin internet)
//   useMock = false → lee/escribe datos reales en Supabase
//
// Organización:
//   - Mock data: restaurantes, categorías y productos de prueba
//   - Restaurantes / Categorías / Productos: CRUD básico
//   - Likes: sistema de likes en tiempo real con Supabase Realtime
//   - Pedidos: crear pedidos, actualizar estado, notificar por FCM
//   - Tracking: el repartidor transmite su GPS y el cliente lo recibe por polling

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

  // Obtiene la lista de restaurantes abiertos
  // Si el dueño configuró su restaurante (nombre, foto, etc.), sobreescribe el primer restaurante con esos datos
  static Future<List<Restaurant>> getRestaurants() async {
    List<Restaurant> list;
    if (useMock) {
      list = List.from(_mockRestaurants);
    } else {
      final data = await _client.from('restaurants').select().eq('is_open', true);
      list = (data as List).map((e) => Restaurant.fromJson(e)).toList();
    }

    // Aplica la configuración guardada del dueño al primer restaurante
    if (list.isNotEmpty) {
      final s = await AuthService.getRestaurantSettings();
      if (s['name']!.isNotEmpty) {
        final r = list[0];
        list[0] = Restaurant(
          id: r.id,
          name: s['name']!,
          description: s['desc']!.isNotEmpty ? s['desc']! : r.description,
          address: s['address']!.isNotEmpty ? s['address']! : r.address,
          imageUrl: s['photo']!.isNotEmpty ? s['photo']! : r.imageUrl,
          lat: r.lat,
          lng: r.lng,
          rating: r.rating,
          isOpen: r.isOpen,
        );
      }
    }

    return list;
  }

  static Future<Restaurant?> getRestaurantById(String restaurantId) async {
    if (useMock) {
      final matches = _mockRestaurants.where((r) => r.id == restaurantId);
      return matches.isEmpty ? null : matches.first;
    }
    final data = await _client
        .from('restaurants')
        .select()
        .eq('id', restaurantId)
        .maybeSingle();
    return data == null ? null : Restaurant.fromJson(data);
  }

  static Future<List<Category>> getCategories(String restaurantId) async {
    if (useMock) return _mockCategories[restaurantId] ?? [];
    final data = await _client
        .from('categories')
        .select()
        .eq('restaurant_id', restaurantId);
    return (data as List).map((e) => Category.fromJson(e)).toList();
  }

  // Imágenes override para productos cuya URL en la BD no carga en Flutter web
  static const _imgFood1 = 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&h=300&fit=crop&q=80';
  static const _imgFood2 = 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&h=300&fit=crop&q=80';
  static const _imgFood3 = 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400&h=300&fit=crop&q=80';
  static const _imgPollo1 = 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?w=400&h=300&fit=crop&q=80';
  static const _imgPollo2 = 'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=400&h=300&fit=crop&q=80';
  static const _imgNieve      = 'https://images.unsplash.com/photo-1501443762994-82bd5dace89a?w=400&h=300&fit=crop&q=80';
  static const _imgNieveLimon = 'https://images.unsplash.com/photo-1559181567-c3190ca9959b?w=400&h=300&fit=crop&q=80';
  static const _imgPaleta  = 'https://images.unsplash.com/photo-1488900128323-21503983a07e?w=400&h=300&fit=crop&q=80';
  static const _imgHotDog1   = 'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgHotDog2   = 'https://images.pexels.com/photos/4518641/pexels-photo-4518641.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgArrozFrito = 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=400&h=300&fit=crop&q=80';
  static const _imgChowMein   = 'https://images.unsplash.com/photo-1555126634-323283e090fa?w=400&h=300&fit=crop&q=80';
  static const _imgAgridulce  = 'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=400&h=300&fit=crop&q=80';
  static const _imgAlitas1    = 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400&h=300&fit=crop&q=80';
  static const _imgAlitas2    = 'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?w=400&h=300&fit=crop&q=80';
  static const _imgPastelChoc = 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=400&h=300&fit=crop&q=80';
  static const _imgTresLeches = 'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400&h=300&fit=crop&q=80';
  static const _imgCapuchino  = 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&h=300&fit=crop&q=80';
  static const _imgFrappe      = 'https://images.unsplash.com/photo-1572490122747-3e9197aa5d6a?w=400&h=300&fit=crop&q=80';
  static const _imgCalRoll     = 'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400&h=300&fit=crop&q=80';
  static const _imgCarnitas1   = 'https://images.unsplash.com/photo-1504544750208-dc0358e63f7f?w=400&h=300&fit=crop&q=80';
  static const _imgCarnitas2   = 'https://images.unsplash.com/photo-1529543544282-ea669407fca3?w=400&h=300&fit=crop&q=80';
  static const _imgPizzaHaw    = 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&h=300&fit=crop&q=80';
  static const _imgBirriaTaco  = 'https://images.pexels.com/photos/7613568/pexels-photo-7613568.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgBirriaStew  = 'https://images.pexels.com/photos/6896379/pexels-photo-6896379.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgConsome      = 'https://images.unsplash.com/photo-1547592180-85f173990554?w=400&h=300&fit=crop&q=80';
  static const _imgTortaPierna = 'https://images.unsplash.com/photo-1639667911189-700bd2029f5b?w=400&h=300&fit=crop&q=80';
  static const _imgTortaMilan  = 'https://images.unsplash.com/photo-1702119614788-bae35a7be313?w=400&h=300&fit=crop&q=80';
  static const _imgTortaCubana = 'https://images.unsplash.com/photo-1642694325494-9b3c23b80cc3?w=400&h=300&fit=crop&q=80';
  static const _imgCamarones   = 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400&h=300&fit=crop&q=80';
  static const _imgFilete      = 'https://images.unsplash.com/photo-1510130387422-82bed34b37e9?w=400&h=300&fit=crop&q=80';
  static const _imgTacoPastor  = 'https://images.unsplash.com/photo-1624726175512-19b9baf9fbd1?w=400&h=300&fit=crop&q=80';
  static const _imgTacoBistec  = 'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?w=400&h=300&fit=crop&q=80';
  static const _imgTacoChorizo = 'https://images.pexels.com/photos/2092507/pexels-photo-2092507.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgQuesadilla  = 'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=400&h=300&fit=crop&q=80';

  static const Map<String, String> _productImageFix = {
    // Carnita
    'ep1781496944163': 'https://images.pexels.com/photos/1639557/pexels-photo-1639557.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop',
    // Hot Dogs
    'p_hd_1': _imgHotDog1, 'p_hd_2': _imgHotDog2,
    // Nieves
    'p_nieves_1': _imgNieveLimon, 'p_nieves_2': _imgNieve, 'p_nieves_3': _imgPaleta,
    // Sushi
    'p13': _imgCalRoll,
    // Tacos Chuy
    'p_chuy_1': _imgTacoPastor, 'p_chuy_2': _imgTacoBistec, 'p_chuy_3': _imgTacoChorizo,
    'p_chuy_4': _imgQuesadilla, 'p_chuy_5': _imgQuesadilla,
    // Carnitas
    'p_carnitas_1': _imgCarnitas1, 'p_carnitas_2': _imgCarnitas2,
    'p_carnitas_3': _imgFood3, 'p_carnitas_4': _imgFood2,
    // Birria
    'p_birria_1': _imgBirriaTaco, 'p_birria_2': _imgBirriaStew, 'p_birria_3': _imgConsome,
    // Pizza
    'p_pizza_2': _imgPizzaHaw,
    // Mariscos
    'p_mar_1': _imgCamarones, 'p_mar_2': _imgFood3, 'p_mar_3': _imgFilete,
    // Tortas
    'p_tortas_1': _imgTortaPierna, 'p_tortas_2': _imgTortaMilan, 'p_tortas_3': _imgTortaCubana,
    // Wok
    'p_wok_1': _imgArrozFrito, 'p_wok_2': _imgChowMein, 'p_wok_3': _imgAgridulce,
    // Alitas
    'p_alitas_1': _imgAlitas1, 'p_alitas_2': _imgAlitas2,
    'p_alitas_3': 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&h=300&fit=crop&q=80',
    // Pastelería
    'p_past_1': _imgPastelChoc, 'p_past_2': _imgTresLeches, 'p_past_4': _imgCapuchino,
    // Starbucks
    'p10': _imgFrappe,
    // Pollo Feliz
    'p_pollo_1': _imgPollo1, 'p_pollo_2': _imgPollo2,
  };

  // Repara URLs de Unsplash que no tienen los parámetros de crop necesarios para Flutter web
  static String _repairUrl(String url) {
    if (!url.contains('unsplash.com')) return url;
    if (url.contains('fit=crop') && url.contains('h=')) return url;
    final base = url.contains('?') ? url.split('?')[0] : url;
    return '$base?w=400&h=300&fit=crop&q=80';
  }

  // Imagen genérica por nombre del platillo (fallback cuando no hay URL en la BD)
  static String? _imageByName(String name) {
    final n = name.toLowerCase();
    if (n.contains('pastor'))                              return _imgTacoPastor;
    if (n.contains('bistec') || n.contains('bistek'))     return _imgTacoBistec;
    if (n.contains('chorizo') && n.contains('taco'))      return _imgTacoChorizo;
    if (n.contains('quesadilla'))                         return _imgQuesadilla;
    if (n.contains('taco') || n.contains('taquiza'))      return _imgTacoPastor;
    if (n.contains('consomé') || n.contains('consome'))   return _imgConsome;
    if (n.contains('birria'))                             return _imgBirriaStew;
    if (n.contains('carnitas'))                           return _imgCarnitas1;
    if (n.contains('hot dog') || n.contains('hotdog'))    return _imgHotDog1;
    if (n.contains('nieve') && (n.contains('limón') || n.contains('limon'))) return _imgNieveLimon;
    if (n.contains('nieve') || n.contains('helado') || n.contains('nieves')) return _imgNieve;
    if (n.contains('paleta'))                             return _imgPaleta;
    if (n.contains('pizza'))                              return _imgPizzaHaw;
    if (n.contains('arroz') && n.contains('frito'))       return _imgArrozFrito;
    if (n.contains('chow mein') || n.contains('chowmein'))return _imgChowMein;
    if (n.contains('agridulce'))                          return _imgAgridulce;
    if (n.contains('alita') || n.contains('wing'))        return _imgAlitas1;
    if (n.contains('camarón') || n.contains('camaron') || n.contains('ceviche')) return _imgCamarones;
    if (n.contains('filete') || n.contains('pescado'))    return _imgFilete;
    if (n.contains('milanesa'))                           return _imgTortaMilan;
    if (n.contains('cubana'))                             return _imgTortaCubana;
    if (n.contains('torta') || n.contains('cemita'))      return _imgTortaPierna;
    if (n.contains('california') || n.contains('roll'))   return _imgCalRoll;
    if (n.contains('sushi'))                              return _imgCalRoll;
    if (n.contains('frappé') || n.contains('frappe') || n.contains('frapé')) return _imgFrappe;
    if (n.contains('capuchino') || n.contains('cappuccino') || n.contains('café') || n.contains('cafe') || n.contains('latte')) return _imgCapuchino;
    if (n.contains('tres leches'))                        return _imgTresLeches;
    if (n.contains('pastel') || n.contains('torta de') || n.contains('cake')) return _imgPastelChoc;
    if (n.contains('pollo') && (n.contains('frito') || n.contains('crispy'))) return _imgPollo1;
    if (n.contains('pollo') || n.contains('chicken'))     return _imgPollo2;
    return null;
  }

  static Product _fixProductImage(Product p) {
    // 1. Override específico por ID de producto
    String? imageUrl = _productImageFix[p.id];

    // 2. Reparar URL de Unsplash si el formato está incompleto
    if (imageUrl == null && p.imageUrl != null && p.imageUrl!.contains('unsplash.com')) {
      imageUrl = _repairUrl(p.imageUrl!);
    }

    // 3. Fallback por nombre si no hay imagen válida
    if ((imageUrl == null || imageUrl.isEmpty) &&
        (p.imageUrl == null || p.imageUrl!.isEmpty)) {
      imageUrl = _imageByName(p.name);
    }

    if (imageUrl == null) return p;
    return Product(
      id: p.id, categoryId: p.categoryId, name: p.name,
      description: p.description, price: p.price, imageUrl: imageUrl,
      isAvailable: p.isAvailable, images: p.images,
      promoDiscountPercent: p.promoDiscountPercent,
      promoIs2x1: p.promoIs2x1,
      promoExpiresAt: p.promoExpiresAt,
    );
  }

  static Future<List<Product>> getProducts(String categoryId) async {
    if (useMock) return _mockProducts[categoryId] ?? [];
    final data = await _client
        .from('products')
        .select()
        .eq('category_id', categoryId)
        .eq('is_available', true);
    return (data as List).map((e) => _fixProductImage(Product.fromJson(e))).toList();
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

  // ── Flota de repartidores ──────────────────────────────────────────────────

  // Crea una cuenta de jefe_flota o rider_flota desde el admin
  static Future<void> createFlotaUser({
    required String email,
    required String password,
    required String name,
    required String role, // 'jefe_flota' | 'rider_flota'
    String? jefeId, // solo para rider_flota
  }) async {
    try {
      final res = await _client.auth.admin.createUser(AdminUserAttributes(
        email: email,
        password: password,
        userMetadata: {'role': role, 'name': name},
        emailConfirm: true,
      ));
      if (jefeId != null && res.user != null) {
        await _client.from('flota_members').insert({
          'jefe_id': jefeId,
          'rider_id': res.user!.id,
          'rider_name': name,
          'rider_email': email,
        });
      }
    } catch (_) {}
  }

  // Devuelve los riders vinculados a un jefe
  static Future<List<Map<String, dynamic>>> getFlotaRiders(String jefeId) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('flota_members')
          .select()
          .eq('jefe_id', jefeId);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) { return []; }
  }

  // Rider transmite su ubicación (funciona con o sin pedido activo)
  static Future<void> broadcastRiderPresence(double lat, double lng) async {
    if (useMock) return;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('rider_locations').upsert({
        'rider_id': uid,
        'lat': lat,
        'lng': lng,
        'is_active': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  // Marca al rider como inactivo al cerrar sesión
  static Future<void> setRiderInactive() async {
    if (useMock) return;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client.from('rider_locations')
          .update({'is_active': false})
          .eq('rider_id', uid);
    } catch (_) {}
  }

  // Obtiene las ubicaciones actuales de una lista de riders
  static Future<Map<String, Map<String, dynamic>>> getRiderLocations(
      List<String> riderIds) async {
    if (useMock || riderIds.isEmpty) return {};
    try {
      final data = await _client
          .from('rider_locations')
          .select()
          .inFilter('rider_id', riderIds);
      return {
        for (final r in (data as List))
          r['rider_id'] as String: r as Map<String, dynamic>
      };
    } catch (_) { return {}; }
  }

  // Pedidos de hoy de un rider específico
  static Future<List<Map<String, dynamic>>> getRiderOrdersToday(
      String riderId) async {
    if (useMock) return [];
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();
      final data = await _client
          .from('orders')
          .select('id, total, delivery_fee, status, created_at')
          .eq('repartidor_id', riderId)
          .gte('created_at', start)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) { return []; }
  }

  // Pedido activo actual de un rider
  static Future<Map<String, dynamic>?> getRiderActiveOrder(String riderId) async {
    if (useMock) return null;
    try {
      final data = await _client
          .from('orders')
          .select('id, status, address, restaurant_id')
          .eq('repartidor_id', riderId)
          .inFilter('status', ['accepted', 'delivering'])
          .maybeSingle();
      return data;
    } catch (_) { return null; }
  }

  // ── Banners promocionales ──────────────────────────────────────────────────

  static Future<List<RestaurantBanner>> getBanners(String restaurantId) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('restaurant_banners')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('is_active', true)
          .order('sort_order');
      return (data as List).map((e) => RestaurantBanner.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<RestaurantBanner?> upsertBanner(RestaurantBanner banner) async {
    try {
      final json = banner.toJson();
      if (banner.id.isNotEmpty) json['id'] = banner.id;
      final data = await _client
          .from('restaurant_banners')
          .upsert(json)
          .select()
          .single();
      return RestaurantBanner.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteBanner(String bannerId) async {
    try {
      await _client.from('restaurant_banners').delete().eq('id', bannerId);
    } catch (_) {}
  }

  // Busca restaurantes y platillos por nombre. Devuelve {restaurants, productRestaurantIds}
  static Future<({List<Restaurant> restaurants, Set<String> productRestaurantIds})>
      searchByQuery(String query, List<Restaurant> allRestaurants) async {
    final q = query.toLowerCase();
    final matchRestaurants = allRestaurants
        .where((r) => r.name.toLowerCase().contains(q))
        .toList();

    final Set<String> productRestaurantIds = {};
    if (!useMock) {
      try {
        final data = await _client
            .from('products')
            .select('restaurant_id, name')
            .ilike('name', '%$query%');
        for (final row in (data as List)) {
          final rid = row['restaurant_id'] as String?;
          if (rid != null) productRestaurantIds.add(rid);
        }
      } catch (_) {}
    }
    // Incluir restaurantes que tienen productos que coinciden (aunque su nombre no coincida)
    final extra = allRestaurants
        .where((r) => productRestaurantIds.contains(r.id) &&
            !matchRestaurants.any((m) => m.id == r.id))
        .toList();
    return (restaurants: [...matchRestaurants, ...extra], productRestaurantIds: productRestaurantIds);
  }

  static Future<String?> uploadProductImage(String localPath) async {
    if (useMock) return null;
    try {
      final bytes = await File(localPath).readAsBytes();
      return uploadProductImageBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  // Comprime a WebP con calidad 82. En web no hay soporte nativo, regresa los bytes sin cambio.
  static Future<Uint8List> _compressToWebP(Uint8List bytes) async {
    if (kIsWeb) return bytes;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 82,
        format: CompressFormat.webp,
      );
      // Solo usar la versión comprimida si es más pequeña
      return compressed.length < bytes.length ? compressed : bytes;
    } catch (_) {
      return bytes;
    }
  }

  static Future<String?> uploadProductImageBytes(Uint8List bytes) async {
    if (useMock) return null;
    try {
      final compressed = await _compressToWebP(bytes);
      final ext      = kIsWeb ? 'jpg' : 'webp';
      final mimeType = kIsWeb ? 'image/jpeg' : 'image/webp';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('product-images').uploadBinary(
        fileName, compressed,
        fileOptions: FileOptions(contentType: mimeType, upsert: true),
      );
      return _client.storage.from('product-images').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfilePhotoBytes(Uint8List bytes, String userId) async {
    if (useMock) return null;
    try {
      final compressed = await _compressToWebP(bytes);
      final ext      = kIsWeb ? 'jpg' : 'webp';
      final mimeType = kIsWeb ? 'image/jpeg' : 'image/webp';
      final fileName = 'profile_$userId.$ext';
      await _client.storage.from('profile-photos').uploadBinary(
        fileName, compressed,
        fileOptions: FileOptions(contentType: mimeType, upsert: true),
      );
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfilePhoto(String localPath, String userId) async {
    if (useMock) return null;
    try {
      final bytes      = await File(localPath).readAsBytes();
      final compressed = await _compressToWebP(bytes);
      final ext        = kIsWeb ? localPath.split('.').last.toLowerCase() : 'webp';
      final mimeType   = kIsWeb ? 'image/${localPath.split('.').last.toLowerCase()}' : 'image/webp';
      final fileName   = 'profile_$userId.$ext';
      await _client.storage.from('profile-photos').uploadBinary(
        fileName, compressed,
        fileOptions: FileOptions(contentType: mimeType, upsert: true),
      );
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateRestaurantLogo(String restaurantId, String imageUrl) async {
    if (useMock) return;
    await _client.from('restaurants').update({'image_url': imageUrl}).eq('id', restaurantId);
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
    int? promoDiscountPercent,
    bool promoIs2x1 = false,
    DateTime? promoExpiresAt,
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
      'promo_discount_percent': promoDiscountPercent,
      'promo_is_2x1': promoIs2x1,
      'promo_expires_at': promoExpiresAt?.toUtc().toIso8601String(),
    });
  }

  static Future<void> setProductAvailability(String productId, bool isAvailable) async {
    if (useMock) return;
    await _client.from('products').update({'is_available': isAvailable}).eq('id', productId);
  }

  // ── Tracking por base de datos (más confiable que Realtime broadcast) ────────

  static String? _activeOrderId;

  static Future<void> startLocationBroadcast(String orderId) async {
    _activeOrderId = orderId;
  }

  // El repartidor llama esto cada vez que su GPS se mueve — guarda coords en la BD
  static Future<void> broadcastLocation(double lat, double lng) async {
    if (_activeOrderId == null) return;
    try {
      await _client.from('orders').update({
        'current_lat': lat,
        'current_lng': lng,
      }).eq('id', _activeOrderId!);
    } catch (_) {}
  }

  static void stopLocationBroadcast() {
    _activeOrderId = null;
  }

  // El cliente llama esto para obtener la ubicación del repartidor
  static Future<({double lat, double lng})?> getRepartidorLocation(String orderId) async {
    try {
      final data = await _client
          .from('orders')
          .select('current_lat, current_lng')
          .eq('id', orderId)
          .single();
      final lat = data['current_lat'];
      final lng = data['current_lng'];
      if (lat == null || lng == null) return null;
      return (lat: (lat as num).toDouble(), lng: (lng as num).toDouble());
    } catch (_) {
      return null;
    }
  }

  // Mantener compatibilidad — ya no usamos Realtime, el cliente hace polling
  static RealtimeChannel? subscribeToLocation(
    String orderId,
    void Function(double lat, double lng) onUpdate,
  ) {
    return null;
  }

  // ── Pedidos ───────────────────────────────────────────────────────────────

  // Crea un nuevo pedido en la BD y sus ítems asociados
  // Retorna el ID del pedido generado (ej. "ord_1717800000000")
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
    double deliveryFee = 0,
    String? clientFcmToken,
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
      'id':            orderId,
      'restaurant_id': restaurantId,
      'total':         total,
      'delivery_fee':  deliveryFee,
      'status':        'pending',
      'customer_name': deliveryJson,
    });
    if (items.isNotEmpty) {
      await _client.from('order_items').insert(
        items.map((i) => {'order_id': orderId, ...i}).toList(),
      );
    }
    return orderId;
  }

  static Future<List<Map<String, dynamic>>> getRestaurantsAdmin() async {
    if (useMock) {
      return _mockRestaurants.map((r) => {
        'id':          r.id,
        'name':        r.name,
        'description': r.description,
        'address':     r.address,
        'emoji_icon':  '🍽️',
        'is_open':     true,
        'rating':      r.rating,
      }).toList();
    }
    final data = await _client.from('restaurants').select().order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getActiveOrders({String? restaurantId}) async {
    if (useMock) return [];
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    var query = _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .inFilter('status', ['pending', 'accepted', 'delivering', 'delivered', 'cancelled'])
        .gte('created_at', startOfDay);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      query = query.eq('restaurant_id', restaurantId);
    }
    final data = await query.order('created_at', ascending: false).limit(200);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> adminUpdateOrderStatus(String orderId, String status) async {
    if (useMock) return;
    await _client.from('orders').update({'status': status}).eq('id', orderId);
    await _sendFcmForStatus(orderId, status);
  }

  static Future<List<Map<String, dynamic>>> getRepartidores() async {
    if (useMock) return [];
    final data = await _client
        .from('orders')
        .select('repartidor_id')
        .not('repartidor_id', 'is', null);
    final orders = (data as List).cast<Map<String, dynamic>>();
    final Map<String, int> counts = {};
    for (final o in orders) {
      final id = o['repartidor_id'] as String? ?? '';
      if (id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
    }
    final result = counts.entries
        .map((e) => <String, dynamic>{'id': e.key, 'entregas': e.value})
        .toList()
      ..sort((a, b) => (b['entregas'] as int).compareTo(a['entregas'] as int));
    return result;
  }

  static Future<void> setRestaurantOpen(String restaurantId, bool isOpen) async {
    if (useMock) return;
    await _client.from('restaurants').update({'is_open': isOpen}).eq('id', restaurantId);
  }

  static Future<void> deleteRestaurant(String restaurantId) async {
    if (useMock) return;
    // Obtiene IDs de categorías y productos para borrar en cascada
    final catRows = await _client.from('categories').select('id').eq('restaurant_id', restaurantId);
    final catIds  = (catRows as List).map((r) => r['id'] as String).toList();

    if (catIds.isNotEmpty) {
      final prodRows = await _client.from('products').select('id').inFilter('category_id', catIds);
      final prodIds  = (prodRows as List).map((r) => r['id'] as String).toList();
      if (prodIds.isNotEmpty) {
        await _client.from('product_images').delete().inFilter('product_id', prodIds);
        await _client.from('product_likes').delete().inFilter('product_id', prodIds);
        await _client.from('order_items').delete().inFilter('product_id', prodIds);
        await _client.from('products').delete().inFilter('category_id', catIds);
      }
      await _client.from('categories').delete().eq('restaurant_id', restaurantId);
    }

    await _client.from('orders').delete().eq('restaurant_id', restaurantId);
    await _client.from('restaurants').delete().eq('id', restaurantId);
  }

  static Future<List<Map<String, dynamic>>> getOrdersForRepartidor() async {
    final userId = _client.auth.currentUser?.id;
    // Muestra pedidos sin repartidor asignado (pending) + pedidos asignados a este repartidor
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .or('status.eq.pending,and(status.eq.accepted,repartidor_id.eq.$userId)')
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateOrderStatus(String orderId, String status) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');
    final updates = <String, dynamic>{'status': status};
    if (status == 'accepted') updates['repartidor_id'] = userId;
    await _client.from('orders').update(updates).eq('id', orderId);
    await _sendFcmForStatus(orderId, status);
  }

  static Future<void> _sendFcmForStatus(String orderId, String status) async {
    try {
      final data = await _client
          .from('orders')
          .select('client_fcm_token')
          .eq('id', orderId)
          .single();
      final token = data['client_fcm_token'] as String?;
      if (token == null || token.isEmpty) return;
      final (title, body) = switch (status) {
        'accepted'   => ('🍳 ¡Pedido aceptado!',      'Tu pedido está siendo preparado.'),
        'delivering' => ('🛵 ¡Repartidor en camino!', 'Tu pedido ya viene para acá.'),
        'delivered'  => ('✅ ¡Pedido entregado!',      '¡Buen provecho!'),
        _            => ('', ''),
      };
      if (title.isEmpty) return;
      await _client.functions.invoke('send-order-notification', body: {
        'token': token,
        'title': title,
        'body':  body,
      });
    } catch (_) {}
  }

  static Future<String?> getOrderStatus(String orderId) async {
    final data = await _client
        .from('orders')
        .select('status')
        .eq('id', orderId)
        .single();
    return data['status'] as String?;
  }

  // Inserta calificación en tabla `ratings` (crear en Supabase si no existe):
  // CREATE TABLE ratings (id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  //   order_id text, stars int, comment text, tip numeric, is_driver bool,
  //   created_at timestamptz DEFAULT now());
  static Future<void> submitRating({
    required String orderId,
    required int stars,
    required String comment,
    required bool isDriver,
    double? tip,
  }) async {
    if (useMock) return;
    try {
      await _client.from('ratings').insert({
        'order_id':  orderId,
        'stars':     stars,
        'comment':   comment.isEmpty ? null : comment,
        'tip':       tip,
        'is_driver': isDriver,
      });
    } catch (_) {}
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
