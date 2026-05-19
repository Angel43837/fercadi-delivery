import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/restaurant.dart';
import '../models/category.dart';
import '../models/product.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // Cambia a false cuando configures Supabase con tus credenciales reales
  static const bool useMock = false;

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
        .select('*, product_images(*)')
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

  static Future<void> createOrder({
    required String userId,
    required String restaurantId,
    required double total,
    required List<Map<String, dynamic>> items,
  }) async {
    if (useMock) return;
    final order = await _client.from('orders').insert({
      'user_id': userId,
      'restaurant_id': restaurantId,
      'total': total,
      'status': 'pending',
    }).select().single();

    for (final item in items) {
      await _client.from('order_items').insert({
        'order_id': order['id'],
        'product_id': item['product_id'],
        'quantity': item['quantity'],
        'price': item['price'],
      });
    }
  }
}
