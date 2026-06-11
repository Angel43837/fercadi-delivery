// restaurant.dart
// Modelo de datos para un restaurante.
// Corresponde a la tabla "restaurants" en Supabase.
// lat/lng son opcionales — solo los tienen restaurantes con ubicación configurada.

class Restaurant {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;  // URL de la foto del restaurante (Supabase Storage)
  final String? address;
  final double? lat;       // Latitud GPS del restaurante
  final double? lng;       // Longitud GPS del restaurante
  final double rating;     // Calificación promedio (0.0 - 5.0)
  final bool isOpen;       // Si está abierto para recibir pedidos

  const Restaurant({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.address,
    this.lat,
    this.lng,
    this.rating = 0,
    this.isOpen = true,
  });

  // Crea un Restaurant desde un Map de JSON (respuesta de Supabase)
  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        address: json['address'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        rating: (json['rating'] as num? ?? 0).toDouble(),
        isOpen: json['is_open'] as bool? ?? true,
      );
}
