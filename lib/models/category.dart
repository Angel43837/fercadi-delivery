// category.dart
// Modelo de datos para una categoría del menú (ej. Hamburguesas, Bebidas, Postres).
// Corresponde a la tabla "categories" en Supabase.
// El icon es un emoji que se muestra en la pestaña de la categoría.

class Category {
  final String id;
  final String restaurantId;  // A qué restaurante pertenece esta categoría
  final String name;
  final String? icon;         // Emoji representativo (ej. "🍔", "🥤")

  const Category({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.icon,
  });

  // Crea una Category desde un Map de JSON (respuesta de Supabase)
  // Supabase usa "emoji_icon" pero el mock usa "icon", acepta ambos
  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        name: json['name'] as String,
        icon: (json['emoji_icon'] ?? json['icon']) as String?,
      );
}
