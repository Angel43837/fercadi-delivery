import 'package:flutter/material.dart';

// Lista fija de categorías de restaurante — a propósito NO es texto libre.
// Se elige de aquí al registrar un restaurante (y se puede editar después
// desde el panel del dueño) para que el filtro de categorías que ve el
// cliente sea consistente entre restaurantes, en vez de que cada dueño le
// ponga el nombre que se le ocurra a sus categorías de menú.
//
// Lista inicial acordada con el negocio — agregar aquí para sumar una nueva
// categoría, no hace falta tocar la base de datos.
const List<String> kRestaurantCategories = [
  'Comida rápida',
  'Bebidas',
  'Postres',
  'Antojitos mexicanos',
  'Mariscos',
  'Pizza',
  'Comida asiática',
];

// Filtros por precio — no son una categoría real del restaurante (no viven en
// restaurants.categorias), son pseudo-categorías calculadas en el cliente a
// partir del platillo más barato disponible de cada restaurante. Se agregan
// aparte en la barra de filtros de restaurants_screen.dart.
const String kPriceFilterUnder100 = 'Menos de \$100';
const String kPriceFilterUnder200 = 'Menos de \$200';
const List<String> kPriceFilters = [kPriceFilterUnder100, kPriceFilterUnder200];

// Ícono para cada chip de la barra de filtros (categorías reales + precio).
// Lo que no está en el mapa cae en el ícono genérico de abajo.
const Map<String, IconData> kRestaurantCategoryIcons = {
  'Comida rápida': Icons.fastfood_rounded,
  'Bebidas': Icons.local_drink_rounded,
  'Postres': Icons.icecream_rounded,
  'Antojitos mexicanos': Icons.lunch_dining_rounded,
  'Mariscos': Icons.set_meal_rounded,
  'Pizza': Icons.local_pizza_rounded,
  'Comida asiática': Icons.ramen_dining_rounded,
  kPriceFilterUnder100: Icons.savings_rounded,
  kPriceFilterUnder200: Icons.payments_rounded,
};

const IconData kRestaurantCategoryIconDefault = Icons.restaurant_menu_rounded;
