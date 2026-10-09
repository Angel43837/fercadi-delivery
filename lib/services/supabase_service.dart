import 'dart:async';
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
import '../models/app_promo.dart';
import '../models/order_message.dart';
import '../models/promotion.dart';
import '../models/promotion_claim.dart';

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
      const Category(
        id: 'c1',
        restaurantId: '1',
        name: 'Hamburguesas',
        icon: '🍔',
      ),
      const Category(id: 'c2', restaurantId: '1', name: 'Papas', icon: '🍟'),
      const Category(id: 'c3', restaurantId: '1', name: 'Bebidas', icon: '🥤'),
      const Category(id: 'c10', restaurantId: '1', name: 'Postres', icon: '🍦'),
      const Category(
        id: 'c11',
        restaurantId: '1',
        name: 'Ensaladas',
        icon: '🥗',
      ),
      const Category(
        id: 'c12',
        restaurantId: '1',
        name: 'Desayunos',
        icon: '🥞',
      ),
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
      const Product(
        id: 'p1',
        categoryId: 'c1',
        name: 'Big Mac',
        description: 'La hamburguesa clásica con doble carne y salsa especial',
        price: 89,
      ),
      const Product(
        id: 'p2',
        categoryId: 'c1',
        name: 'Quarter Pounder',
        description: 'Jugosa y deliciosa con queso cheddar',
        price: 95,
      ),
      const Product(
        id: 'p3',
        categoryId: 'c1',
        name: 'McPollo Crispy',
        description: 'Pechuga crujiente con lechuga y mayo',
        price: 79,
      ),
    ],
    'c2': [
      const Product(
        id: 'p4',
        categoryId: 'c2',
        name: 'Papas Medianas',
        description: 'Crujientes y bien saladas',
        price: 35,
      ),
      const Product(
        id: 'p5',
        categoryId: 'c2',
        name: 'Papas Grandes',
        description: 'Para compartir o para ti solo',
        price: 45,
      ),
    ],
    'c3': [
      const Product(
        id: 'p6',
        categoryId: 'c3',
        name: 'Coca-Cola Grande',
        description: 'Refresco bien frío con hielo',
        price: 30,
      ),
      const Product(
        id: 'p7',
        categoryId: 'c3',
        name: 'Milkshake Chocolate',
        description: 'Cremoso y delicioso',
        price: 55,
      ),
    ],
    'c4': [
      const Product(
        id: 'p8',
        categoryId: 'c4',
        name: 'Café Americano',
        description: 'Clásico y aromático, doble shot',
        price: 65,
      ),
      const Product(
        id: 'p9',
        categoryId: 'c4',
        name: 'Café Latte',
        description: 'Suave y cremoso con leche vaporizada',
        price: 75,
      ),
    ],
    'c5': [
      const Product(
        id: 'p10',
        categoryId: 'c5',
        name: 'Frappé Oreo',
        description: 'Frío, cremoso y cargado de Oreos',
        price: 95,
      ),
      const Product(
        id: 'p11',
        categoryId: 'c5',
        name: 'Smoothie Tropical',
        description: 'Mango, piña y maracuyá',
        price: 85,
      ),
    ],
    'c6': [
      const Product(
        id: 'p12',
        categoryId: 'c6',
        name: 'Croissant de Jamón',
        description: 'Recién horneado con jamón y queso',
        price: 55,
      ),
    ],
    'c7': [
      const Product(
        id: 'p13',
        categoryId: 'c7',
        name: 'California Roll',
        description: '8 piezas de camarón, aguacate y pepino',
        price: 120,
      ),
      const Product(
        id: 'p14',
        categoryId: 'c7',
        name: 'Dragon Roll',
        description: '8 piezas premium con tuna y aguacate',
        price: 145,
      ),
    ],
    'c8': [
      const Product(
        id: 'p15',
        categoryId: 'c8',
        name: 'Edamame',
        description: 'Frijoles japoneses con sal de mar',
        price: 55,
      ),
      const Product(
        id: 'p16',
        categoryId: 'c8',
        name: 'Gyozas',
        description: '6 piezas de dumplings al vapor',
        price: 85,
      ),
    ],
    'c9': [
      const Product(
        id: 'p17',
        categoryId: 'c9',
        name: 'Mochi de Fresa',
        description: 'Postre japonés suave y dulce',
        price: 45,
      ),
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
      final data = await _client
          .from('restaurants')
          .select()
          .eq('is_open', true);
      list = (data as List).map((e) => Restaurant.fromJson(e)).toList();
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

  // Estado de aprobación del restaurante (fase 1 del sistema de registro/aprobación).
  // Devuelve null en mock o si el restaurante no existe.
  static Future<Map<String, dynamic>?> getRestaurantApprovalStatus(String restaurantId) async {
    if (useMock) return null;
    final data = await _client
        .from('restaurants')
        .select('approval_status, rejection_reason, correction_notes')
        .eq('id', restaurantId)
        .maybeSingle();
    return data;
  }

  // Admin aprueba/rechaza/pide correcciones a un restaurante dado de alta
  // por el registro web — admin_transition_restaurant_status() ya existe
  // en la base (RPC security definer, valida is_admin() del lado del
  // servidor), esto solo le faltaba un wrapper en Dart.
  static Future<void> adminTransitionRestaurantStatus({
    required String restaurantId,
    required String newStatus,
    String? note,
  }) async {
    if (useMock) return;
    await _client.rpc('admin_transition_restaurant_status', params: {
      'p_restaurant_id': restaurantId,
      'p_new_status': newStatus,
      'p_note': note,
    });
  }

  // Mismo patrón que arriba, para un repartidor registrado por la web
  // (tabla drivers) — antes no existía ninguna forma de aprobar/rechazar
  // a un rider desde ninguna app.
  static Future<void> adminTransitionDriverStatus({
    required String driverId,
    required String newStatus,
    String? note,
  }) async {
    if (useMock) return;
    await _client.rpc('admin_transition_driver_status', params: {
      'p_driver_id': driverId,
      'p_new_status': newStatus,
      'p_note': note,
    });
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
  static const _imgFood2 =
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&h=300&fit=crop&q=80';
  static const _imgFood3 =
      'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400&h=300&fit=crop&q=80';
  static const _imgPollo1 =
      'https://images.unsplash.com/photo-1532550907401-a500c9a57435?w=400&h=300&fit=crop&q=80';
  static const _imgPollo2 =
      'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=400&h=300&fit=crop&q=80';
  static const _imgNieve =
      'https://images.unsplash.com/photo-1501443762994-82bd5dace89a?w=400&h=300&fit=crop&q=80';
  static const _imgNieveLimon =
      'https://images.unsplash.com/photo-1559181567-c3190ca9959b?w=400&h=300&fit=crop&q=80';
  static const _imgPaleta =
      'https://images.unsplash.com/photo-1488900128323-21503983a07e?w=400&h=300&fit=crop&q=80';
  static const _imgHotDog1 =
      'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgHotDog2 =
      'https://images.pexels.com/photos/4518641/pexels-photo-4518641.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgArrozFrito =
      'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=400&h=300&fit=crop&q=80';
  static const _imgChowMein =
      'https://images.unsplash.com/photo-1555126634-323283e090fa?w=400&h=300&fit=crop&q=80';
  static const _imgAgridulce =
      'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=400&h=300&fit=crop&q=80';
  static const _imgAlitas1 =
      'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400&h=300&fit=crop&q=80';
  static const _imgAlitas2 =
      'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?w=400&h=300&fit=crop&q=80';
  static const _imgPastelChoc =
      'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=400&h=300&fit=crop&q=80';
  static const _imgTresLeches =
      'https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=400&h=300&fit=crop&q=80';
  static const _imgCapuchino =
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400&h=300&fit=crop&q=80';
  static const _imgFrappe =
      'https://images.unsplash.com/photo-1572490122747-3e9197aa5d6a?w=400&h=300&fit=crop&q=80';
  static const _imgCalRoll =
      'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400&h=300&fit=crop&q=80';
  static const _imgCarnitas1 =
      'https://images.unsplash.com/photo-1504544750208-dc0358e63f7f?w=400&h=300&fit=crop&q=80';
  static const _imgCarnitas2 =
      'https://images.unsplash.com/photo-1529543544282-ea669407fca3?w=400&h=300&fit=crop&q=80';
  static const _imgPizzaHaw =
      'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&h=300&fit=crop&q=80';
  static const _imgBirriaTaco =
      'https://images.pexels.com/photos/7613568/pexels-photo-7613568.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgBirriaStew =
      'https://images.pexels.com/photos/6896379/pexels-photo-6896379.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgConsome =
      'https://images.unsplash.com/photo-1547592180-85f173990554?w=400&h=300&fit=crop&q=80';
  static const _imgTortaPierna =
      'https://images.unsplash.com/photo-1639667911189-700bd2029f5b?w=400&h=300&fit=crop&q=80';
  static const _imgTortaMilan =
      'https://images.unsplash.com/photo-1702119614788-bae35a7be313?w=400&h=300&fit=crop&q=80';
  static const _imgTortaCubana =
      'https://images.unsplash.com/photo-1642694325494-9b3c23b80cc3?w=400&h=300&fit=crop&q=80';
  static const _imgCamarones =
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400&h=300&fit=crop&q=80';
  static const _imgFilete =
      'https://images.unsplash.com/photo-1510130387422-82bed34b37e9?w=400&h=300&fit=crop&q=80';
  static const _imgTacoPastor =
      'https://images.unsplash.com/photo-1624726175512-19b9baf9fbd1?w=400&h=300&fit=crop&q=80';
  static const _imgTacoBistec =
      'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?w=400&h=300&fit=crop&q=80';
  static const _imgTacoChorizo =
      'https://images.pexels.com/photos/2092507/pexels-photo-2092507.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop';
  static const _imgQuesadilla =
      'https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=400&h=300&fit=crop&q=80';

  static const Map<String, String> _productImageFix = {
    // Carnita
    'ep1781496944163':
        'https://images.pexels.com/photos/1639557/pexels-photo-1639557.jpeg?auto=compress&cs=tinysrgb&w=400&h=300&fit=crop',
    // Hot Dogs
    'p_hd_1': _imgHotDog1, 'p_hd_2': _imgHotDog2,
    // Nieves
    'p_nieves_1': _imgNieveLimon,
    'p_nieves_2': _imgNieve,
    'p_nieves_3': _imgPaleta,
    // Sushi
    'p13': _imgCalRoll,
    // Tacos Chuy
    'p_chuy_1': _imgTacoPastor,
    'p_chuy_2': _imgTacoBistec,
    'p_chuy_3': _imgTacoChorizo,
    'p_chuy_4': _imgQuesadilla, 'p_chuy_5': _imgQuesadilla,
    // Carnitas
    'p_carnitas_1': _imgCarnitas1, 'p_carnitas_2': _imgCarnitas2,
    'p_carnitas_3': _imgFood3, 'p_carnitas_4': _imgFood2,
    // Birria
    'p_birria_1': _imgBirriaTaco,
    'p_birria_2': _imgBirriaStew,
    'p_birria_3': _imgConsome,
    // Pizza
    'p_pizza_2': _imgPizzaHaw,
    // Mariscos
    'p_mar_1': _imgCamarones, 'p_mar_2': _imgFood3, 'p_mar_3': _imgFilete,
    // Tortas
    'p_tortas_1': _imgTortaPierna,
    'p_tortas_2': _imgTortaMilan,
    'p_tortas_3': _imgTortaCubana,
    // Wok
    'p_wok_1': _imgArrozFrito,
    'p_wok_2': _imgChowMein,
    'p_wok_3': _imgAgridulce,
    // Alitas
    'p_alitas_1': _imgAlitas1, 'p_alitas_2': _imgAlitas2,
    'p_alitas_3':
        'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&h=300&fit=crop&q=80',
    // Pastelería
    'p_past_1': _imgPastelChoc,
    'p_past_2': _imgTresLeches,
    'p_past_4': _imgCapuchino,
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
    if (n.contains('pastor')) return _imgTacoPastor;
    if (n.contains('bistec') || n.contains('bistek')) return _imgTacoBistec;
    if (n.contains('chorizo') && n.contains('taco')) return _imgTacoChorizo;
    if (n.contains('quesadilla')) return _imgQuesadilla;
    if (n.contains('taco') || n.contains('taquiza')) return _imgTacoPastor;
    if (n.contains('consomé') || n.contains('consome')) return _imgConsome;
    if (n.contains('birria')) return _imgBirriaStew;
    if (n.contains('carnitas')) return _imgCarnitas1;
    if (n.contains('hot dog') || n.contains('hotdog')) return _imgHotDog1;
    if (n.contains('nieve') && (n.contains('limón') || n.contains('limon')))
      return _imgNieveLimon;
    if (n.contains('nieve') || n.contains('helado') || n.contains('nieves'))
      return _imgNieve;
    if (n.contains('paleta')) return _imgPaleta;
    if (n.contains('pizza')) return _imgPizzaHaw;
    if (n.contains('arroz') && n.contains('frito')) return _imgArrozFrito;
    if (n.contains('chow mein') || n.contains('chowmein')) return _imgChowMein;
    if (n.contains('agridulce')) return _imgAgridulce;
    if (n.contains('alita') || n.contains('wing')) return _imgAlitas1;
    if (n.contains('camarón') || n.contains('camaron') || n.contains('ceviche'))
      return _imgCamarones;
    if (n.contains('filete') || n.contains('pescado')) return _imgFilete;
    if (n.contains('milanesa')) return _imgTortaMilan;
    if (n.contains('cubana')) return _imgTortaCubana;
    if (n.contains('torta') || n.contains('cemita')) return _imgTortaPierna;
    if (n.contains('california') || n.contains('roll')) return _imgCalRoll;
    if (n.contains('sushi')) return _imgCalRoll;
    if (n.contains('frappé') || n.contains('frappe') || n.contains('frapé'))
      return _imgFrappe;
    if (n.contains('capuchino') ||
        n.contains('cappuccino') ||
        n.contains('café') ||
        n.contains('cafe') ||
        n.contains('latte'))
      return _imgCapuchino;
    if (n.contains('tres leches')) return _imgTresLeches;
    if (n.contains('pastel') || n.contains('torta de') || n.contains('cake'))
      return _imgPastelChoc;
    if (n.contains('pollo') && (n.contains('frito') || n.contains('crispy')))
      return _imgPollo1;
    if (n.contains('pollo') || n.contains('chicken')) return _imgPollo2;
    return null;
  }

  static Product _fixProductImage(Product p) {
    // 1. Override específico por ID de producto
    String? imageUrl = _productImageFix[p.id];

    // 2. Reparar URL de Unsplash si el formato está incompleto
    if (imageUrl == null &&
        p.imageUrl != null &&
        p.imageUrl!.contains('unsplash.com')) {
      imageUrl = _repairUrl(p.imageUrl!);
    }

    // 3. Fallback por nombre si no hay imagen válida
    if ((imageUrl == null || imageUrl.isEmpty) &&
        (p.imageUrl == null || p.imageUrl!.isEmpty)) {
      imageUrl = _imageByName(p.name);
    }

    if (imageUrl == null) return p;
    return Product(
      id: p.id,
      categoryId: p.categoryId,
      name: p.name,
      description: p.description,
      price: p.price,
      imageUrl: imageUrl,
      isAvailable: p.isAvailable,
      images: p.images,
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
    return (data as List)
        .map((e) => _fixProductImage(Product.fromJson(e)))
        .toList();
  }

  static Future<List<({String name, String icon, List<Product> products})>>
  getMenuSections(String restaurantId) async {
    if (useMock) {
      final cats = _mockCategories[restaurantId] ?? [];
      return [
        for (final cat in cats)
          (
            name: cat.name,
            icon: cat.icon ?? '🍽️',
            products: _mockProducts[cat.id] ?? [],
          ),
      ];
    }
    final catsData = await _client
        .from('categories')
        .select()
        .eq('restaurant_id', restaurantId);
    final sections = <({String name, String icon, List<Product> products})>[];
    for (final cat in catsData as List) {
      final prodsData = await _client
          .from('products')
          .select()
          .eq('category_id', cat['id'])
          .eq('is_available', true);
      sections.add((
        name: cat['name'] as String,
        icon: cat['emoji_icon'] as String? ?? '🍽️',
        products: (prodsData as List).map((e) => Product.fromJson(e)).toList(),
      ));
    }
    return sections;
  }

  static Future<List<Product>> getProductsForRestaurant(
    String restaurantId,
  ) async {
    if (useMock) return [];
    final data = await _client
        .from('products')
        .select()
        .eq('restaurant_id', restaurantId);
    return (data as List).map((e) => Product.fromJson(e)).toList();
  }

  // Promos propias de la app GOGO Food (no de un restaurante) — cupones que
  // se muestran en la pestaña "Promos" de restaurants_screen.dart.
  static Future<List<AppPromo>> getActivePromos() async {
    if (useMock) return [];
    final data = await _client
        .from('app_promos')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    final now = DateTime.now();
    return (data as List)
        .map((e) => AppPromo.fromJson(e))
        .where((p) => p.expiresAt == null || p.expiresAt!.isAfter(now))
        .toList();
  }

  // ── Promociones/cupones reales ───────────────────────────────────────────
  // No confundir con getActivePromos() de arriba (AppPromo — banners
  // puramente visuales). Esto es el sistema real: reclamar, "Mis
  // promociones", validar y aplicar en el checkout. El descuento SIEMPRE
  // lo calcula el servidor (validate_promotion_for_order) — estas
  // funciones nunca calculan un monto en Dart, solo piden/mandan lo que la
  // base de datos ya decidió. Ver supabase/migrations/20260901010000_promotions.sql.

  // Detalle de una sola promoción (para promotion_detail_screen.dart, a
  // donde llega un banner con linked_promotion_id). RLS ya filtra que un
  // cliente normal solo pueda ver esta fila si is_active = true.
  static Future<Promotion?> getPromotionById(String id) async {
    if (useMock) return null;
    try {
      final data = await _client.from('promotions').select().eq('id', id).maybeSingle();
      if (data == null) return null;
      return Promotion.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  // Único lugar donde se crea un reclamo — pasa por la función
  // claim_promotion (security definer), nunca un insert directo.
  static Future<PromotionClaim> claimPromotion(String promotionId) async {
    final data = await _client.rpc('claim_promotion', params: {
      'p_promotion_id': promotionId,
    });
    return PromotionClaim.fromMap((data as Map).cast<String, dynamic>());
  }

  // "Mis promociones" — ya agrupadas en los 4 buckets que muestra la
  // pantalla (Disponible/Próximamente/Expirada/Utilizada), calculados al
  // leer, nunca guardados.
  static Future<Map<ClaimBucket, List<PromotionClaim>>> getMyPromotions() async {
    if (useMock) return {};
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    try {
      final data = await _client
          .from('promotion_claims')
          .select('*, promotion:promotions(*)')
          .eq('user_id', uid)
          .order('claimed_at', ascending: false);
      final claims = (data as List)
          .map((e) => PromotionClaim.fromMap(e as Map<String, dynamic>))
          .toList();
      final grouped = <ClaimBucket, List<PromotionClaim>>{
        for (final b in ClaimBucket.values) b: [],
      };
      for (final c in claims) {
        grouped[c.bucket]!.add(c);
      }
      return grouped;
    } catch (_) {
      return {};
    }
  }

  // Le pide al servidor el descuento real para un reclamo + carrito dados —
  // esto es lo que se muestra en el checkout, nunca un cálculo hecho en Dart.
  // cartItems: [{'product_id':..., 'category_id':..., 'quantity':n, 'unit_price':x}, ...]
  static Future<Map<String, dynamic>> validatePromotionForOrder({
    required String claimId,
    required String restaurantId,
    required List<Map<String, dynamic>> cartItems,
    required double subtotal,
    required double deliveryFee,
  }) async {
    final data = await _client.rpc('validate_promotion_for_order', params: {
      'p_claim_id': claimId,
      'p_restaurant_id': restaurantId,
      'p_cart_items': cartItems,
      'p_subtotal': subtotal,
      'p_delivery_fee': deliveryFee,
    });
    return (data as Map).cast<String, dynamic>();
  }

  // Se llama justo después de que el pedido ya se creó de verdad. Si esto
  // falla, el pedido en sí ya se completó igual — no fatal (mismo criterio
  // que el resto de los "side effects" de esta app).
  static Future<void> applyPromotionToOrder({
    required String claimId,
    required String orderId,
    required double discountAmount,
  }) async {
    try {
      await _client.rpc('apply_promotion_to_order', params: {
        'p_claim_id': claimId,
        'p_order_id': orderId,
        'p_discount_amount': discountAmount,
      });
    } catch (e) {
      debugPrint('applyPromotionToOrder falló (el pedido ya se creó igual): $e');
    }
  }

  // ── Promociones — administración ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> adminGetPromotions() async {
    if (useMock) return [];
    final data = await _client
        .from('promotions')
        .select()
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> adminCreatePromotion(Map<String, dynamic> payload) async {
    await _client.from('promotions').insert(payload);
  }

  static Future<void> adminUpdatePromotion(String id, Map<String, dynamic> payload) async {
    await _client.from('promotions').update(payload).eq('id', id);
  }

  static Future<void> adminSetPromotionActive(String id, bool active) async {
    await _client.from('promotions').update({'is_active': active}).eq('id', id);
  }

  // Contadores para la vista de estadísticas del admin — lectura directa
  // sobre promotion_claims, sin RPC ni tabla aparte (RLS ya lo protege).
  static Future<Map<String, dynamic>> getPromotionStats(String promotionId) async {
    final claims = await _client
        .from('promotion_claims')
        .select('status, discount_amount')
        .eq('promotion_id', promotionId);
    final list = (claims as List).cast<Map<String, dynamic>>();
    final used = list.where((c) => c['status'] == 'used').toList();
    final totalDiscount = used.fold<double>(
        0, (s, c) => s + ((c['discount_amount'] as num?)?.toDouble() ?? 0));
    return {
      'claims': list.length,
      'used': used.length,
      'totalDiscountGiven': totalDiscount,
    };
  }

  // Precio más barato disponible de cada restaurante — usado por el filtro
  // "Menos de $100"/"Menos de $200" en restaurants_screen.dart. Una sola
  // consulta para todos los restaurantes de la zona, no una por restaurante.
  static Future<Map<String, double>> getMinPricesForRestaurants(
    List<String> restaurantIds,
  ) async {
    if (useMock || restaurantIds.isEmpty) return {};
    final data = await _client
        .from('products')
        .select('restaurant_id, price')
        .inFilter('restaurant_id', restaurantIds)
        .eq('is_available', true);
    final result = <String, double>{};
    for (final row in (data as List)) {
      final rid = row['restaurant_id'] as String?;
      final price = (row['price'] as num?)?.toDouble();
      if (rid == null || price == null) continue;
      final current = result[rid];
      if (current == null || price < current) result[rid] = price;
    }
    return result;
  }

  // ── Flota de repartidores ──────────────────────────────────────────────────

  // Crea repartidor (sin gamificación) y lo vincula al jefe de flota.
  // Requiere que AppConstants.supabaseServiceRoleKey esté configurado en constants.dart.
  // ⚠️ Nunca poner la clave real en constantes.dart si está en git — usar variables de entorno o Edge Function.
  // Retorna null si todo OK, o el mensaje de error si falla.
  static Future<String?> createRepartidorFlota({
    required String name,
    required String email,
    required String password,
    required String jefeId,
  }) async {
    const key = AppConstants.supabaseServiceRoleKey;
    if (key.isEmpty) {
      return 'Función no disponible: configura supabaseServiceRoleKey en AppConstants o usa una Edge Function.';
    }
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.supabaseUrl}/auth/v1/admin/users'),
        headers: {
          'Authorization': 'Bearer $key',
          'apikey': key,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
          'user_metadata': {'name': name},
          'app_metadata': {'role': 'repartidor'},
          'email_confirm': true,
        }),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['msg'] as String? ??
            body['message'] as String? ??
            'Error al crear usuario';
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final userId = data['id'] as String;
      await _client.from('flota_members').insert({
        'jefe_id': jefeId,
        'rider_id': userId,
        'rider_name': name,
        'rider_email': email,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // Devuelve los riders vinculados a un jefe
  static Future<List<Map<String, dynamic>>> getFlotaRiders(
    String jefeId,
  ) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('flota_members')
          .select()
          .eq('jefe_id', jefeId);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // Un solo rider de flota_members (placa, nombre/correo denormalizados)
  static Future<Map<String, dynamic>?> getFlotaMember(String riderId) async {
    if (useMock) return null;
    try {
      return await _client
          .from('flota_members')
          .select()
          .eq('rider_id', riderId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
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

  // Obtiene las ubicaciones actuales de una lista de riders
  static Future<Map<String, Map<String, dynamic>>> getRiderLocations(
    List<String> riderIds,
  ) async {
    if (useMock || riderIds.isEmpty) return {};
    try {
      final data = await _client
          .from('rider_locations')
          .select()
          .inFilter('rider_id', riderIds);
      return {
        for (final r in (data as List))
          r['rider_id'] as String: r as Map<String, dynamic>,
      };
    } catch (_) {
      return {};
    }
  }

  // Pedidos de hoy de un rider específico
  static Future<List<Map<String, dynamic>>> getRiderOrdersToday(
    String riderId,
  ) async {
    if (useMock) return [];
    try {
      final today = DateTime.now();
      final start = DateTime(
        today.year,
        today.month,
        today.day,
      ).toUtc().toIso8601String();
      final data = await _client
          .from('orders')
          .select('id, total, delivery_fee, status, created_at')
          .eq('repartidor_id', riderId)
          .gte('created_at', start)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // Pedido activo actual de un rider
  static Future<Map<String, dynamic>?> getRiderActiveOrder(
    String riderId,
  ) async {
    if (useMock) return null;
    try {
      final data = await _client
          .from('orders')
          .select('id, status, address, restaurant_id')
          .eq('repartidor_id', riderId)
          .inFilter('status', ['accepted', 'delivering'])
          .maybeSingle();
      return data;
    } catch (_) {
      return null;
    }
  }

  // Historial completo de pedidos de un rider (sin filtro de fecha), para la
  // vista de detalle del jefe de flota. Las estadísticas (hoy/semana/totales)
  // se calculan del lado del cliente a partir de esta lista.
  static Future<List<Map<String, dynamic>>> getRiderOrderHistory(
    String riderId,
  ) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('orders')
          .select('id, total, delivery_fee, status, created_at')
          .eq('repartidor_id', riderId)
          .order('created_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // Datos de auth.users (user_metadata: name, phone, avatar_url, etc.) de un
  // rider — el jefe de flota no es ese usuario, así que no puede leerlos con
  // su propia sesión y se necesita la Admin API (service role key).
  static Future<Map<String, dynamic>?> getRiderAuthProfile(
    String riderId,
  ) async {
    const key = AppConstants.supabaseServiceRoleKey;
    if (key.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.supabaseUrl}/auth/v1/admin/users/$riderId'),
        headers: {'Authorization': 'Bearer $key', 'apikey': key},
      );
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Edita el perfil de un rider desde el panel de flota. Nombre/teléfono/foto
  // se guardan en user_metadata (misma fuente que repartidor_plus_screen.dart
  // usa para el propio perfil del rider, para no crear una segunda copia que
  // se desincronice); correo y placa también se reflejan en flota_members
  // porque getFlotaRiders lee de ahí para la lista. Retorna null si OK, o el
  // mensaje de error si falla.
  static Future<String?> updateFlotaMember({
    required String riderId,
    required String name,
    required String email,
    String? phone,
    String? plate,
    String? photoUrl,
  }) async {
    const key = AppConstants.supabaseServiceRoleKey;
    if (key.isEmpty) {
      return 'Función no disponible: configura supabaseServiceRoleKey en AppConstants o usa una Edge Function.';
    }
    try {
      final current = await getRiderAuthProfile(riderId);
      final metadata = Map<String, dynamic>.from(
        current?['user_metadata'] as Map<String, dynamic>? ?? {},
      );
      metadata['name'] = name;
      if (phone != null) metadata['phone'] = phone;
      if (photoUrl != null) metadata['avatar_url'] = photoUrl;

      final res = await http.put(
        Uri.parse('${AppConstants.supabaseUrl}/auth/v1/admin/users/$riderId'),
        headers: {
          'Authorization': 'Bearer $key',
          'apikey': key,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'email_confirm': true,
          'user_metadata': metadata,
        }),
      );
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['msg'] as String? ??
            body['message'] as String? ??
            'Error al actualizar';
      }
      await _client
          .from('flota_members')
          .update({
            'rider_name': name,
            'rider_email': email,
            if (plate != null) 'rider_plate': plate,
          })
          .eq('rider_id', riderId);
      return null;
    } catch (e) {
      return e.toString();
    }
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
  static Future<
    ({List<Restaurant> restaurants, Set<String> productRestaurantIds})
  >
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
        .where(
          (r) =>
              productRestaurantIds.contains(r.id) &&
              !matchRestaurants.any((m) => m.id == r.id),
        )
        .toList();
    return (
      restaurants: [...matchRestaurants, ...extra],
      productRestaurantIds: productRestaurantIds,
    );
  }

  // Detecta el formato real de una imagen por sus bytes mágicos — en web no
  // se recomprime (_compressToWebP la deja intacta), así que hay que revisar
  // el contenido real en vez de asumir un formato fijo.
  static String _detectImageExt(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'gif';
    }
    return 'jpg';
  }

  static String _mimeForExt(String ext) => switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

  // Detalle del último fallo de subida de foto (compresión o Storage) — para
  // poder mostrar en pantalla EXACTAMENTE cuál paso fue, en vez de un
  // "no se pudo subir" genérico que no dice nada. Las funciones de subida ya
  // regresan `null` en caso de error (así estaba, no se cambió ese contrato
  // para no tener que tocar cada lugar que las llama) — esto solo guarda el
  // motivo real al lado, que la pantalla de perfil lee cuando ve `null`.
  static String? lastUploadError;

  // Comprime a WebP con calidad 82. En web no hay soporte nativo, regresa los bytes sin cambio.
  // A propósito NO atrapa errores aquí (antes sí, y con eso "fallaba" en
  // silencio: si el plugin nativo tronaba, la función regresaba los bytes
  // originales sin convertir, pero el que llama igual subía el archivo
  // etiquetado como .webp/image-webp — resultado: un archivo mal etiquetado
  // que parecía subido bien). Ahora un fallo aquí se propaga y el método de
  // subida lo trata como lo que es: la subida falló.
  static Future<Uint8List> _compressToWebP(Uint8List bytes) async {
    if (kIsWeb) return bytes;
    // Sin límite de tiempo, si el plugin nativo se quedaba trabado esto
    // colgaba para siempre — y como el .timeout() de uploadBinary() está
    // más adelante en la cadena, nunca se llegaba ni siquiera a esa
    // protección.
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 82,
      format: CompressFormat.webp,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('conversión a WebP'),
    );
    if (compressed.isEmpty) {
      throw Exception('La conversión a WebP no produjo ningún archivo');
    }
    return compressed;
  }

  // ownerId (normalmente el restaurant_id del dueño que sube la foto) se
  // antepone al nombre del archivo — antes el nombre era solo un timestamp,
  // sin ninguna relación con el dueño/restaurante. El bucket es público y
  // sin políticas de dueño reales (igual que profile-photos/rider-avatars),
  // así que el nombre del archivo es la única protección real contra que
  // alguien pise la foto de OTRO restaurante subiendo con el mismo nombre
  // — y ese nombre es visible para cualquiera en la URL pública de la
  // foto, así que sin el restaurant_id ahí, cualquiera podía reemplazar la
  // foto de cualquier platillo de cualquier restaurante.
  static Future<String?> uploadProductImageBytes(Uint8List bytes, {String? ownerId}) async {
    if (useMock) return null;
    try {
      final compressed = await _compressToWebP(bytes);
      final ext = kIsWeb ? _detectImageExt(bytes) : 'webp';
      final mimeType = kIsWeb ? _mimeForExt(ext) : 'image/webp';
      final prefix = ownerId == null
          ? ''
          : '${ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_';
      final fileName = '$prefix${DateTime.now().millisecondsSinceEpoch}.$ext';
      // Antes sin timeout ni lastUploadError — a diferencia de las otras
      // subidas (perfil, rider), una conexión colgada aquí se quedaba
      // esperando para siempre y el error real nunca quedaba disponible
      // para mostrarse en pantalla (el dueño solo veía "no se pudo subir").
      await _client.storage
          .from('product-images')
          .uploadBinary(
            fileName,
            compressed,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          )
          .timeout(const Duration(seconds: 20));
      lastUploadError = null;
      return _client.storage.from('product-images').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('[Upload] uploadProductImageBytes error: $e');
      lastUploadError = e.toString();
      return null;
    }
  }

  // Borra un archivo de Storage a partir de su URL pública — se usa al
  // reemplazar una foto (producto/banner) para no dejar el archivo anterior
  // como basura huérfana en el bucket. A diferencia de la foto de
  // perfil/logo/avatar (que siempre reusa el mismo nombre de archivo por
  // usuario/restaurante, así que un upsert ya sobreescribe sin dejar
  // basura), las fotos de producto y de banner usan un nombre con
  // timestamp — cada foto nueva es un archivo nuevo, así que sin este
  // borrado explícito el anterior se queda huérfano para siempre.
  // Solo usa el bucket + la ruta que trae la URL, contra el proyecto de
  // Supabase con el que esta app está conectada ahora mismo — si la URL
  // guardada quedó apuntando a otro proyecto (ej. de antes de una
  // migración) y aquí no hay ningún archivo con esa ruta, Storage
  // simplemente no borra nada. Best-effort: nunca lanza error si falla.
  static Future<void> deleteImageByUrl(String? url) async {
    if (url == null || !url.startsWith('http')) return;
    final match = RegExp(r'/object/public/([^/]+)/(.+)$').firstMatch(url);
    if (match == null) return;
    final bucket = match.group(1)!;
    final path = Uri.decodeComponent(match.group(2)!);
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {}
  }

  static Future<String?> uploadProfilePhotoBytes(
    Uint8List bytes,
    String userId,
  ) async {
    if (useMock) return null;
    try {
      final compressed = await _compressToWebP(bytes);
      final ext = kIsWeb ? _detectImageExt(bytes) : 'webp';
      final mimeType = kIsWeb ? _mimeForExt(ext) : 'image/webp';
      final fileName = 'profile_$userId.$ext';
      await _client.storage
          .from('profile-photos')
          .uploadBinary(
            fileName,
            compressed,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          )
          .timeout(const Duration(seconds: 20));
      // Limpieza best-effort del .jpg viejo que dejaba la versión anterior
      // de este flujo (antes de la conversión a WebP, siempre subía como
      // .jpg) — mismo fix ya aplicado en uploadRiderAvatarBytes. Si no
      // existe, Storage simplemente no encuentra nada que borrar.
      if (ext != 'jpg') {
        unawaited(_client.storage.from('profile-photos').remove(['profile_$userId.jpg']).catchError((_) => <FileObject>[]));
      }
      lastUploadError = null;
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('[Upload] uploadProfilePhotoBytes error: $e');
      lastUploadError = e.toString();
      return null;
    }
  }

  static Future<String?> uploadProfilePhoto(
    String localPath,
    String userId,
  ) async {
    if (useMock) return null;
    try {
      final bytes = await File(localPath).readAsBytes();
      final compressed = await _compressToWebP(bytes);
      final ext = kIsWeb ? localPath.split('.').last.toLowerCase() : 'webp';
      final mimeType = kIsWeb
          ? 'image/${localPath.split('.').last.toLowerCase()}'
          : 'image/webp';
      final fileName = 'profile_$userId.$ext';
      // Sin límite de tiempo, una conexión lenta/caída a medias dejaba el
      // await esperando para siempre — el spinner de _pickPhoto() nunca se
      // apagaba porque su finally jamás llegaba a correr.
      await _client.storage
          .from('profile-photos')
          .uploadBinary(
            fileName,
            compressed,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          )
          .timeout(const Duration(seconds: 20));
      // Mismo fix que uploadProfilePhotoBytes/uploadRiderAvatarBytes: borra
      // el .jpg viejo que dejó la versión anterior de este flujo (antes de
      // convertir a WebP) para no dejarlo huérfano en el bucket.
      if (ext != 'jpg') {
        unawaited(_client.storage.from('profile-photos').remove(['profile_$userId.jpg']).catchError((_) => <FileObject>[]));
      }
      lastUploadError = null;
      return _client.storage.from('profile-photos').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('[Upload] uploadProfilePhoto error: $e');
      lastUploadError = e.toString();
      return null;
    }
  }

  // Foto de perfil de repartidor_plus (bucket rider-avatars) — antes vivía
  // como código suelto en repartidor_plus_screen.dart, sin WebP y sin
  // límite de tiempo (mismo bug que ya se arregló aquí para el cliente).
  static Future<String?> uploadRiderAvatarBytes(
    Uint8List bytes,
    String userId,
  ) async {
    if (useMock) return null;
    try {
      final compressed = await _compressToWebP(bytes);
      final ext = kIsWeb ? _detectImageExt(bytes) : 'webp';
      final mimeType = kIsWeb ? _mimeForExt(ext) : 'image/webp';
      final fileName = 'avatars/$userId.$ext';
      await _client.storage
          .from('rider-avatars')
          .uploadBinary(
            fileName,
            compressed,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          )
          .timeout(const Duration(seconds: 20));
      final url = _client.storage.from('rider-avatars').getPublicUrl(fileName);
      // Limpieza best-effort del .jpg viejo que dejaba la versión anterior
      // de este flujo (antes de este fix, siempre subía como .jpg) — si no
      // existe, Storage simplemente no encuentra nada que borrar.
      if (ext != 'jpg') {
        unawaited(_client.storage.from('rider-avatars').remove(['avatars/$userId.jpg']).catchError((_) => <FileObject>[]));
      }
      lastUploadError = null;
      return url;
    } catch (e) {
      debugPrint('[Upload] uploadRiderAvatarBytes error: $e');
      lastUploadError = e.toString();
      return null;
    }
  }

  static Future<void> updateRestaurantLogo(
    String restaurantId,
    String imageUrl,
  ) async {
    if (useMock) return;
    await _client
        .from('restaurants')
        .update({'image_url': imageUrl})
        .eq('id', restaurantId);
  }

  // Perfil real del restaurante (nombre, descripción, dirección, emoji,
  // logo) tal cual vive en Supabase — fuente de verdad para el panel de
  // ajustes del dueño. Antes ese panel solo leía un caché local
  // (SharedPreferences) que se pierde al reinstalar la app o entrar desde
  // otro dispositivo, mostrando todo en blanco aunque el restaurante sí
  // tuviera sus datos guardados de verdad del otro lado.
  static Future<Map<String, String>?> getRestaurantProfile(
    String restaurantId,
  ) async {
    if (useMock) return null;
    try {
      final row = await _client
          .from('restaurants')
          .select('name, description, address, image_url, emoji_icon, phone')
          .eq('id', restaurantId)
          .maybeSingle();
      if (row == null) return null;
      return {
        'name':    row['name'] as String? ?? '',
        'desc':    row['description'] as String? ?? '',
        'address': row['address'] as String? ?? '',
        'photo':   row['image_url'] as String? ?? '',
        'emoji':   row['emoji_icon'] as String? ?? '',
        'phone':   row['phone'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateRestaurantProfile({
    required String restaurantId,
    required String name,
    required String description,
    required String address,
    required String emoji,
    required String phone,
  }) async {
    if (useMock) return;
    await _client.from('restaurants').update({
      'name': name,
      'description': description,
      'address': address,
      'emoji_icon': emoji,
      'phone': phone,
    }).eq('id', restaurantId);
  }

  static Future<String> getRestaurantZona(String restaurantId) async {
    if (useMock) return 'maravatio';
    try {
      final row = await _client
          .from('restaurants')
          .select('zona')
          .eq('id', restaurantId)
          .maybeSingle();
      return row?['zona'] as String? ?? 'maravatio';
    } catch (_) {
      return 'maravatio';
    }
  }

  static Future<bool> getRestaurantIsPremium(String restaurantId) async {
    if (useMock) return false;
    try {
      final row = await _client
          .from('restaurants')
          .select('is_premium')
          .eq('id', restaurantId)
          .maybeSingle();
      return row?['is_premium'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> getRestaurantCategorias(String restaurantId) async {
    if (useMock) return [];
    try {
      final row = await _client
          .from('restaurants')
          .select('categorias')
          .eq('id', restaurantId)
          .maybeSingle();
      return (row?['categorias'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateRestaurantZona(
    String restaurantId,
    String zona,
  ) async {
    if (useMock) return;
    await _client
        .from('restaurants')
        .update({'zona': zona})
        .eq('id', restaurantId);
  }

  static Future<void> updateRestaurantCategorias(
    String restaurantId,
    List<String> categorias,
  ) async {
    if (useMock) return;
    await _client
        .from('restaurants')
        .update({'categorias': categorias})
        .eq('id', restaurantId);
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
    } catch (_) {
      return {};
    }
  }

  // user_email sigue existiendo por compatibilidad (era parte de la llave
  // primaria original y sigue NOT NULL) pero ya no es la identidad real —
  // eso es user_id ahora (ver migración 20260901000000_likes_user_id_and_rls_fix.sql,
  // que también quitó la política "Allow all" que dejaba a cualquiera con la
  // anon key insertar/borrar likes de otra persona). Una cuenta de solo-
  // teléfono no tiene email, así que se rellena con un valor sintético único
  // que ya no se lee para nada.
  static String _likeIdentityEmail() {
    final user = _client.auth.currentUser;
    final email = user?.email;
    if (email != null && email.isNotEmpty) return email;
    final phone = user?.phone;
    if (phone != null && phone.isNotEmpty) {
      return 'phone:${phone.startsWith('+') ? phone : '+$phone'}';
    }
    return 'uid:${user?.id ?? 'desconocido'}';
  }

  static Future<Set<String>> getUserLikedProducts(String userId) async {
    if (useMock || userId.isEmpty) return {};
    try {
      final data = await _client
          .from('product_likes')
          .select('product_id')
          .eq('user_id', userId);
      return {for (final r in data as List) r['product_id'] as String};
    } catch (_) {
      return {};
    }
  }

  static Future<void> toggleProductLike(String productId, String userId) async {
    if (useMock || userId.isEmpty) return;
    try {
      final existing = await _client
          .from('product_likes')
          .select()
          .eq('product_id', productId)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing == null) {
        await _client.from('product_likes').insert({
          'product_id': productId,
          'user_id': userId,
          'user_email': _likeIdentityEmail(),
        });
      } else {
        await _client
            .from('product_likes')
            .delete()
            .eq('product_id', productId)
            .eq('user_id', userId);
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
      final data = await _client
          .from('restaurant_likes')
          .select('restaurant_id');
      final counts = <String, int>{};
      for (final row in data as List) {
        final id = row['restaurant_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }

  // Restaurantes de los que el cliente ya ha pedido antes — se usa para
  // personalizar el orden de /restaurants (categorías favoritas primero).
  static Future<List<String>> getCustomerOrderedRestaurantIds(String customerId) async {
    if (useMock || customerId.isEmpty) return [];
    try {
      final data = await _client
          .from('orders')
          .select('restaurant_id')
          .eq('customer_id', customerId)
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final row in data as List) row['restaurant_id'] as String];
    } catch (_) {
      return [];
    }
  }

  static Future<Set<String>> getUserLikedRestaurants(String userId) async {
    if (useMock || userId.isEmpty) return {};
    try {
      final data = await _client
          .from('restaurant_likes')
          .select('restaurant_id')
          .eq('user_id', userId);
      return {for (final r in data as List) r['restaurant_id'] as String};
    } catch (_) {
      return {};
    }
  }

  static Future<void> toggleRestaurantLike(
    String restaurantId,
    String userId,
  ) async {
    if (useMock || userId.isEmpty) return;
    try {
      final existing = await _client
          .from('restaurant_likes')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing == null) {
        await _client.from('restaurant_likes').insert({
          'restaurant_id': restaurantId,
          'user_id': userId,
          'user_email': _likeIdentityEmail(),
        });
      } else {
        await _client
            .from('restaurant_likes')
            .delete()
            .eq('restaurant_id', restaurantId)
            .eq('user_id', userId);
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

  static Future<void> setProductAvailability(
    String productId,
    bool isAvailable,
  ) async {
    if (useMock) return;
    await _client
        .from('products')
        .update({'is_available': isAvailable})
        .eq('id', productId);
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
      await _client
          .from('orders')
          .update({'current_lat': lat, 'current_lng': lng})
          .eq('id', _activeOrderId!);
    } catch (_) {}
  }

  static void stopLocationBroadcast() {
    _activeOrderId = null;
  }

  // El cliente llama esto para obtener la ubicación del repartidor
  static Future<({double lat, double lng})?> getRepartidorLocation(
    String orderId,
  ) async {
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
    String? paymentStatus,
    String? stripePaymentIntentId,
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
      'delivery_fee': deliveryFee,
      'status': 'pending',
      'customer_name': deliveryJson,
      'customer_id': _client.auth.currentUser?.id,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (stripePaymentIntentId != null)
        'stripe_payment_intent_id': stripePaymentIntentId,
      if (clientFcmToken != null) 'client_fcm_token': clientFcmToken,
    });
    if (items.isNotEmpty) {
      await _client
          .from('order_items')
          .insert(items.map((i) => {'order_id': orderId, ...i}).toList());
    }
    return orderId;
  }

  static Future<List<Map<String, dynamic>>> getRestaurantsAdmin() async {
    if (useMock) {
      return _mockRestaurants
          .map(
            (r) => {
              'id': r.id,
              'name': r.name,
              'description': r.description,
              'address': r.address,
              'emoji_icon': '🍽️',
              'is_open': true,
              'rating': r.rating,
            },
          )
          .toList();
    }
    final data = await _client.from('restaurants').select().order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getActiveOrders({
    String? restaurantId,
  }) async {
    if (useMock) return [];
    final now = DateTime.now();
    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    var query = _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .inFilter('status', [
          'pending',
          'restaurant_accepted',
          'accepted',
          'delivering',
          'delivered',
          'cancelled',
        ])
        .gte('created_at', startOfDay);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      query = query.eq('restaurant_id', restaurantId);
    }
    final data = await query.order('created_at', ascending: false).limit(200);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> adminUpdateOrderStatus(
    String orderId,
    String status,
  ) async {
    if (useMock) return;
    await _client.from('orders').update({'status': status}).eq('id', orderId);
    await _sendFcmForStatus(orderId, status);
  }

  // ── Mensajes directos de Admin a un usuario ───────────────────────────────

  // Admin le manda un aviso puntual a un cliente o repartidor específico
  // (ej. "tu identificación salió borrosa, vuelve a subirla") — antes no
  // existía ninguna forma de hacer esto desde la app.
  static Future<void> sendAdminMessage({
    required String recipientId,
    required String title,
    required String body,
  }) async {
    if (useMock) return;
    await _client.from('admin_messages').insert({
      'recipient_id': recipientId,
      'sent_by': _client.auth.currentUser?.id,
      'title': title,
      'body': body,
    });
  }

  static Future<List<Map<String, dynamic>>> getMyAdminMessages() async {
    if (useMock) return [];
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await _client
        .from('admin_messages')
        .select()
        .eq('recipient_id', uid)
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<int> getUnreadAdminMessageCount() async {
    if (useMock) return 0;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    final data = await _client
        .from('admin_messages')
        .select('id')
        .eq('recipient_id', uid)
        .filter('read_at', 'is', null);
    return (data as List).length;
  }

  static Future<void> markAdminMessageRead(String messageId) async {
    if (useMock) return;
    await _client
        .from('admin_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId);
  }

  // ── Alertas de la plataforma ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAlerts() async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('alerts')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // priority: 'critica' | 'alta' | 'media' | 'baja'
  // category: 'pagos' | 'servidor' | 'restaurante' | 'base_datos' | 'conexion' | 'otro'
  static Future<void> createAlert({
    required String title,
    String? description,
    String priority = 'media',
    String category = 'otro',
  }) async {
    if (useMock) return;
    try {
      await _client.from('alerts').insert({
        'title': title,
        'description': description,
        'priority': priority,
        'category': category,
        'status': 'pendiente',
      });
    } catch (_) {}
  }

  // status: 'pendiente' | 'en_proceso' | 'resuelta'
  static Future<void> updateAlertStatus(String alertId, String status) async {
    if (useMock) return;
    try {
      await _client
          .from('alerts')
          .update({
            'status': status,
            'resolved_at': status == 'resuelta'
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', alertId);
    } catch (_) {}
  }

  // ── Tienda de coins del repartidor ───────────────────────────────────────
  // Productos administrables desde el panel de Admin. La pantalla de canje
  // ya no vive en esta app — se movió a Pagina_web_GoGo (login propio ahí);
  // estas funciones se quedan porque el admin las sigue usando para
  // mantener el catálogo (mismas tablas, mismos permisos de siempre).

  static Future<List<Map<String, dynamic>>> getRiderStoreItems({
    bool onlyActive = true,
  }) async {
    if (useMock) return [];
    try {
      final data = onlyActive
          ? await _client
                .from('rider_store_items')
                .select()
                .eq('is_active', true)
                .order('sort_order')
          : await _client
                .from('rider_store_items')
                .select()
                .order('sort_order');
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  static Future<void> createRiderStoreItem(Map<String, dynamic> item) async {
    if (useMock) return;
    try {
      await _client.from('rider_store_items').insert(item);
    } catch (_) {}
  }

  static Future<void> updateRiderStoreItem(
    String id,
    Map<String, dynamic> item,
  ) async {
    if (useMock) return;
    try {
      await _client.from('rider_store_items').update(item).eq('id', id);
    } catch (_) {}
  }

  static Future<void> deleteRiderStoreItem(String id) async {
    if (useMock) return;
    try {
      await _client.from('rider_store_items').delete().eq('id', id);
    } catch (_) {}
  }

  // ── Estadísticas de la plataforma (rankings) ─────────────────────────────

  static Future<List<Map<String, dynamic>>> getTopLikedRestaurants({
    int limit = 10,
  }) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('restaurant_likes')
          .select('restaurant_id, restaurants(name)');
      final Map<String, Map<String, dynamic>> agg = {};
      for (final r in (data as List).cast<Map<String, dynamic>>()) {
        final rid = r['restaurant_id'] as String? ?? '';
        if (rid.isEmpty) continue;
        final restaurant = r['restaurants'] as Map<String, dynamic>?;
        agg.putIfAbsent(
          rid,
          () => {
            'id': rid,
            'name': restaurant?['name'] ?? 'Restaurante',
            'value': 0,
          },
        );
        agg[rid]!['value'] = (agg[rid]!['value'] as int) + 1;
      }
      final result = agg.values.toList()
        ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
      return result.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTopLikedProducts({
    int limit = 10,
  }) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('product_likes')
          .select('product_id, products(name, restaurants(name))');
      final Map<String, Map<String, dynamic>> agg = {};
      for (final r in (data as List).cast<Map<String, dynamic>>()) {
        final pid = r['product_id'] as String? ?? '';
        if (pid.isEmpty) continue;
        final product = r['products'] as Map<String, dynamic>?;
        final restaurant = product?['restaurants'] as Map<String, dynamic>?;
        agg.putIfAbsent(
          pid,
          () => {
            'id': pid,
            'name': product?['name'] ?? 'Producto',
            'restaurant_name': restaurant?['name'] ?? '',
            'value': 0,
          },
        );
        agg[pid]!['value'] = (agg[pid]!['value'] as int) + 1;
      }
      final result = agg.values.toList()
        ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
      return result.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTopOrderedProducts({
    int limit = 10,
  }) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('order_items')
          .select('product_id, quantity, products(name, restaurants(name))')
          .not('product_id', 'is', null);
      final Map<String, Map<String, dynamic>> agg = {};
      for (final it in (data as List).cast<Map<String, dynamic>>()) {
        final pid = it['product_id'] as String? ?? '';
        if (pid.isEmpty) continue;
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        final product = it['products'] as Map<String, dynamic>?;
        final restaurant = product?['restaurants'] as Map<String, dynamic>?;
        agg.putIfAbsent(
          pid,
          () => {
            'id': pid,
            'name': product?['name'] ?? 'Producto',
            'restaurant_name': restaurant?['name'] ?? '',
            'value': 0,
          },
        );
        agg[pid]!['value'] = (agg[pid]!['value'] as int) + qty;
      }
      final result = agg.values.toList()
        ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
      return result.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getTopOrderedRestaurants({
    int limit = 10,
  }) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('orders')
          .select('restaurant_id, restaurants(name)')
          .not('restaurant_id', 'is', null);
      final Map<String, Map<String, dynamic>> agg = {};
      for (final o in (data as List).cast<Map<String, dynamic>>()) {
        final rid = o['restaurant_id'] as String? ?? '';
        if (rid.isEmpty) continue;
        final restaurant = o['restaurants'] as Map<String, dynamic>?;
        agg.putIfAbsent(
          rid,
          () => {
            'id': rid,
            'name': restaurant?['name'] ?? 'Restaurante',
            'value': 0,
          },
        );
        agg[rid]!['value'] = (agg[rid]!['value'] as int) + 1;
      }
      final result = agg.values.toList()
        ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
      return result.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setRestaurantOpen(
    String restaurantId,
    bool isOpen,
  ) async {
    if (useMock) return;
    await _client
        .from('restaurants')
        .update({'is_open': isOpen})
        .eq('id', restaurantId);
  }

  static Future<void> deleteRestaurant(String restaurantId) async {
    if (useMock) return;
    // Obtiene IDs de categorías y productos para borrar en cascada
    final catRows = await _client
        .from('categories')
        .select('id')
        .eq('restaurant_id', restaurantId);
    final catIds = (catRows as List).map((r) => r['id'] as String).toList();

    if (catIds.isNotEmpty) {
      final prodRows = await _client
          .from('products')
          .select('id')
          .inFilter('category_id', catIds);
      final prodIds = (prodRows as List).map((r) => r['id'] as String).toList();
      if (prodIds.isNotEmpty) {
        await _client
            .from('product_images')
            .delete()
            .inFilter('product_id', prodIds);
        await _client
            .from('product_likes')
            .delete()
            .inFilter('product_id', prodIds);
        await _client
            .from('order_items')
            .delete()
            .inFilter('product_id', prodIds);
        await _client.from('products').delete().inFilter('category_id', catIds);
      }
      await _client
          .from('categories')
          .delete()
          .eq('restaurant_id', restaurantId);
    }

    await _client.from('orders').delete().eq('restaurant_id', restaurantId);
    await _client.from('restaurants').delete().eq('id', restaurantId);
  }

  static Future<List<Map<String, dynamic>>> getOrdersForRepartidor() async {
    final userId = _client.auth.currentUser?.id;
    // Solo pedidos ya confirmados por el restaurante y sin repartidor
    // asignado (restaurant_accepted) + los ya asignados a este repartidor —
    // antes mostraba 'pending' directo, sin esperar a que el restaurante
    // confirmara nada.
    final data = await _client
        .from('orders')
        .select(
          '*, restaurants(name, address, image_url, lat, lng), order_items(quantity, price, notes, products(id, name))',
        )
        .or(
          'status.eq.restaurant_accepted,and(status.eq.accepted,repartidor_id.eq.$userId)',
        )
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

  // El repartidor cancela SU entrega ya aceptada — el pedido vuelve a
  // 'pending' y sin repartidor asignado para que otro lo pueda tomar. No es
  // lo mismo que cancelar el pedido del cliente (ese sigue siendo 'cancelled').
  static Future<void> releaseOrderFromRider(String orderId) async {
    await _client
        .from('orders')
        .update({'status': 'pending', 'repartidor_id': null})
        .eq('id', orderId);
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
        'accepted' => (
          '🍳 ¡Pedido aceptado!',
          'Tu pedido está siendo preparado.',
        ),
        'delivering' => (
          '🛵 ¡Repartidor en camino!',
          'Tu pedido ya viene para acá.',
        ),
        'delivered' => ('✅ ¡Pedido entregado!', '¡Buen provecho!'),
        _ => ('', ''),
      };
      if (title.isEmpty) return;
      await _client.functions.invoke(
        'send-order-notification',
        body: {'token': token, 'title': title, 'body': body},
      );
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

  // Repartidor asignado al pedido (null hasta que alguien lo acepta) —
  // usado para mostrarle su nombre/foto al cliente en el seguimiento.
  static Future<String?> getOrderRepartidorId(String orderId) async {
    try {
      final data = await _client
          .from('orders')
          .select('repartidor_id')
          .eq('id', orderId)
          .single();
      return data['repartidor_id'] as String?;
    } catch (_) {
      return null;
    }
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
        'order_id': orderId,
        'stars': stars,
        'comment': comment.isEmpty ? null : comment,
        'tip': tip,
        'is_driver': isDriver,
      });
    } catch (_) {}
  }

  // Historial completo de pedidos de un cliente (todas las fechas, no solo hoy).
  static Future<List<Map<String, dynamic>>> getOrdersByPhone(
    String phone,
  ) async {
    if (useMock) return [];
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .ilike('customer_name', '%"phone":"$phone"%')
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // Historial de pedidos de un cliente por su id real (orders.customer_id) —
  // más confiable que getOrdersByPhone, que depende de un texto libre
  // guardado en customer_name y puede no coincidir si el formato del
  // teléfono varía entre pedidos.
  static Future<List<Map<String, dynamic>>> getOrdersByCustomerId(
    String customerId,
  ) async {
    if (useMock) return [];
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // Historial completo de entregas de un repartidor (todas las fechas, no solo hoy).
  static Future<List<Map<String, dynamic>>> getOrdersByRepartidor(
    String repartidorId,
  ) async {
    if (useMock) return [];
    final data = await _client
        .from('orders')
        .select('*, order_items(quantity, price, notes, products(id, name))')
        .eq('repartidor_id', repartidorId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // Calificaciones asociadas a una lista de pedidos (para calcular promedio).
  // Excluye is_hidden = true: si Admin oculta una reseña, también desaparece
  // de las vistas normales del cliente/rider, no solo del panel.
  static Future<List<Map<String, dynamic>>> getRatingsForOrders(
    List<String> orderIds,
  ) async {
    if (useMock || orderIds.isEmpty) return [];
    final data = await _client
        .from('ratings')
        .select()
        .inFilter('order_id', orderIds)
        .eq('is_hidden', false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── Reseñas (moderación desde Admin) ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAllRatingsForAdmin() async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('ratings')
          .select('*, orders(repartidor_id, customer_name)')
          .order('created_at', ascending: false)
          .limit(500);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setRatingModeration(
    String ratingId, {
    bool? isHidden,
    bool? isFlagged,
    String? reportReason,
  }) async {
    if (useMock) return;
    final payload = <String, dynamic>{};
    if (isHidden != null) payload['is_hidden'] = isHidden;
    if (isFlagged != null) payload['is_flagged'] = isFlagged;
    if (reportReason != null) payload['report_reason'] = reportReason;
    if (payload.isEmpty) return;
    try {
      await _client.from('ratings').update(payload).eq('id', ratingId);
    } catch (_) {}
  }

  static Future<void> logModerationAction(
    String ratingId,
    String adminEmail,
    String action, {
    String? note,
  }) async {
    if (useMock) return;
    try {
      await _client.from('rating_moderation_log').insert({
        'rating_id': ratingId,
        'admin_email': adminEmail,
        'action': action,
        'note': note,
      });
    } catch (_) {}
  }

  static Future<void> deleteRating(String ratingId) async {
    if (useMock) return;
    try {
      await _client.from('ratings').delete().eq('id', ratingId);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getModerationLogForRating(
    String ratingId,
  ) async {
    if (useMock) return [];
    try {
      final data = await _client
          .from('rating_moderation_log')
          .select()
          .eq('rating_id', ratingId)
          .order('created_at', ascending: false);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // Consulta/suspende cuentas via Edge Function — la service_role key nunca
  // vive en la app, solo en el servidor de esa función.
  static Future<Map<String, dynamic>?> lookupAuthUser(String userId) async {
    if (useMock) return null;
    try {
      final res = await _client.functions
          .invoke(
            'admin-user-lookup',
            body: {'action': 'lookup', 'userId': userId},
          )
          .timeout(const Duration(seconds: 15));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  // Todas las cuentas de un rol (o varios), tengan o no pedidos — a
  // diferencia de las listas de "Clientes"/"Repartidores" de Admin, que
  // antes se armaban solo a partir de orders.repartidor_id/customer_name y
  // por eso una cuenta recién creada sin pedidos no aparecía en ningún lado.
  static Future<List<Map<String, dynamic>>> listUsersByRole(
    List<String> roles,
  ) async {
    if (useMock) return [];
    try {
      final res = await _client.functions
          .invoke(
            'admin-user-lookup',
            body: {'action': 'listByRole', 'role': roles},
          )
          .timeout(const Duration(seconds: 20));
      final data = res.data;
      if (data is Map && data['users'] is List) {
        return (data['users'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // Datos del registro web de un repartidor (vehículo, tipo de
  // identificación) + enlaces temporales a sus documentos — null si nunca
  // se registró por la web (ej. cuentas de flota, que no pasan por ahí).
  static Future<Map<String, dynamic>?> getDriverDocs(String riderId) async {
    if (useMock) return null;
    try {
      final res = await _client.functions
          .invoke(
            'admin-user-lookup',
            body: {'action': 'driverDocs', 'userId': riderId},
          )
          .timeout(const Duration(seconds: 15));
      final data = res.data;
      if (data is Map && data['driver'] is Map) {
        return Map<String, dynamic>.from(data['driver'] as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Repartidores registrados por la web que todavía necesitan revisión —
  // alimenta el apartado de "Aceptaciones" en Admin, junto con los
  // restaurantes pendientes.
  static Future<List<Map<String, dynamic>>> getPendingDrivers() async {
    if (useMock) return [];
    try {
      final res = await _client.functions
          .invoke('admin-user-lookup', body: {'action': 'listPendingDrivers'})
          .timeout(const Duration(seconds: 15));
      final data = res.data;
      if (data is Map && data['drivers'] is List) {
        return (data['drivers'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // Nombre/foto de la contraparte de un pedido (cliente↔repartidor) —
  // vía Edge Function, que verifica que quien llama de verdad participe
  // en ese pedido antes de devolver el perfil del otro lado.
  static Future<Map<String, dynamic>?> getOrderCounterpartProfile(
    String orderId,
    String targetUserId,
  ) async {
    if (useMock) return null;
    try {
      final res = await _client.functions
          .invoke(
            'order-user-lookup',
            body: {'orderId': orderId, 'targetUserId': targetUserId},
          )
          .timeout(const Duration(seconds: 15));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setUserBanned(String userId, bool banned) async {
    if (useMock) return false;
    try {
      final res = await _client.functions
          .invoke(
            'admin-user-lookup',
            body: {'action': banned ? 'ban' : 'unban', 'userId': userId},
          )
          .timeout(const Duration(seconds: 15));
      return res.data is Map && (res.data as Map)['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Rider Stats ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getRiderStats(String riderId) async {
    if (useMock) return {};
    try {
      final data = await _client
          .from('rider_stats')
          .select()
          .eq('rider_id', riderId)
          .maybeSingle();
      return data ?? {};
    } catch (_) {
      return {};
    }
  }

  // Incrementa stats del rider vía RPC atómica en el servidor.
  // SQL requerido (ejecutar una vez en Supabase > SQL Editor):
  //
  // CREATE OR REPLACE FUNCTION increment_rider_stats(
  //   p_rider_id uuid, p_coins_add int DEFAULT 0,
  //   p_repartos_add int DEFAULT 0, p_dinero_add numeric DEFAULT 0
  // ) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
  // BEGIN
  //   INSERT INTO rider_stats (rider_id, coins, repartos, dinero, updated_at)
  //   VALUES (p_rider_id, p_coins_add, p_repartos_add, p_dinero_add, now())
  //   ON CONFLICT (rider_id) DO UPDATE SET
  //     coins     = rider_stats.coins     + EXCLUDED.coins,
  //     repartos  = rider_stats.repartos  + EXCLUDED.repartos,
  //     dinero    = rider_stats.dinero    + EXCLUDED.dinero,
  //     updated_at = now();
  // END; $$;
  // GRANT EXECUTE ON FUNCTION increment_rider_stats TO authenticated;
  static Future<void> incrementRiderStats(
    String riderId, {
    int coinsAdd = 0,
    int repartosAdd = 0,
    double dineroAdd = 0,
  }) async {
    if (useMock) return;
    try {
      await _client.rpc(
        'increment_rider_stats',
        params: {
          'p_rider_id': riderId,
          'p_coins_add': coinsAdd,
          'p_repartos_add': repartosAdd,
          'p_dinero_add': dineroAdd,
        },
      );
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

  // ── Llamadas a repartidor desde la app de escritorio (gogo-pedidos-escritorio) ──
  // Ver supabase/migrations/20261008000000_rider_calls.sql — un dueño llama
  // a TODOS los repartidores de flota en línea; el primero en aceptar se
  // queda el pedido (respond_rider_call valida eso del lado del servidor).

  static Future<List<Map<String, dynamic>>> getPendingRiderCalls() async {
    if (useMock) return [];
    final data = await _client
        .from('rider_calls')
        .select()
        .eq('status', 'pendiente')
        .order('created_at');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // true si de verdad la ganó (nadie más la aceptó primero).
  static Future<bool> respondRiderCall(String callId, bool accept) async {
    final res = await _client.rpc('respond_rider_call', params: {
      'p_call_id': callId,
      'p_accept': accept,
    });
    return res == true;
  }

  static RealtimeChannel subscribeToRiderCalls(void Function() onUpdate) {
    final channel = _client.channel('db_rider_calls');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rider_calls',
          callback: (_) => onUpdate(),
        )
        .subscribe();
    return channel;
  }

  // ── Chat interno del pedido (cliente ↔ repartidor) ──────────────────────

  static Future<List<OrderMessage>> getOrderMessages(String orderId) async {
    if (useMock) return [];
    final data = await _client
        .from('order_messages')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    return (data as List).map((e) => OrderMessage.fromJson(e)).toList();
  }

  static Future<void> sendOrderMessage(String orderId, String content) async {
    if (useMock) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No hay sesión activa');
    await _client.from('order_messages').insert({
      'order_id': orderId,
      'sender_id': userId,
      'content': content,
    });
  }

  static RealtimeChannel subscribeToOrderMessages(
    String orderId,
    void Function(OrderMessage) onNewMessage,
  ) {
    final channel = _client.channel('order_messages_$orderId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: orderId,
          ),
          callback: (payload) => onNewMessage(OrderMessage.fromJson(payload.newRecord)),
        )
        .subscribe();
    return channel;
  }

  // ── Configuración de la plataforma ────────────────────────────────────────

  static Future<void> setPlatformConfig(String key, String value) async {
    if (useMock) return;
    await _client.from('platform_config').upsert({'key': key, 'value': value});
  }
}
