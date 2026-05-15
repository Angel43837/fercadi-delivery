class Restaurant {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? address;
  final double? lat;
  final double? lng;
  final double rating;
  final bool isOpen;

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
