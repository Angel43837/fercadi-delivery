class Category {
  final String id;
  final String restaurantId;
  final String name;
  final String? icon;

  const Category({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.icon,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        name: json['name'] as String,
        icon: (json['emoji_icon'] ?? json['icon']) as String?,
      );
}
