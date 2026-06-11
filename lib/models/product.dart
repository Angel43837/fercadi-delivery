// product.dart
// Modelo de datos para un platillo/producto del menú.
// Corresponde a la tabla "products" en Supabase.
// images es una lista de URLs adicionales para el carrusel de fotos en el detalle.

class Product {
  final String id;
  final String categoryId;  // A qué categoría del menú pertenece
  final String name;
  final String? description;
  final double price;          // Precio en MXN
  final String? imageUrl;      // Foto principal del platillo
  final bool isAvailable;      // Si se puede ordenar en este momento
  final List<String> images;   // Fotos adicionales para el carrusel

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.isAvailable = true,
    this.images = const [],
  });

  // Crea un Product desde un Map de JSON (respuesta de Supabase)
  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['image_url'] as String?,
        isAvailable: json['is_available'] as bool? ?? true,
        images: const [],
      );
}
