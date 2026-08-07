// product_categories.dart
// Lista fija y genérica sugerida para las categorías de MENÚ (tabla `categories`,
// las pestañas de platillos dentro de un restaurante — NO confundir con
// `kRestaurantCategories` en restaurant_categories.dart, que es el tipo de
// restaurante usado en el filtro del cliente).
//
// Uso: al dar de alta un restaurante nuevo, elegir sus categorías de menú
// de esta lista en vez de inventar nombres específicos (ej. "Hamburguesas")
// que no generalizan bien si el restaurante también vende otras cosas
// (hot dogs, tortas, etc.). Los restaurantes ya existentes conservan sus
// categorías específicas tal como están — esta lista aplica solo hacia
// adelante, no es una migración retroactiva.
const List<String> kProductCategories = [
  'Platillos',
  'Entradas',
  'Ensaladas',
  'Desayunos',
  'Acompañamientos',
  'Postres',
  'Bebidas',
];
