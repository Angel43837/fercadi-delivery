// router.dart
// Define todas las rutas de navegación de la app usando go_router.
// Cada GoRoute mapea una URL (path) a una pantalla (builder).
// Para navegar entre pantallas se usa: context.go('/ruta') o context.push('/ruta').
// Las rutas que necesitan datos extras los reciben por state.extra (ej. producto, restaurante).

import 'package:go_router/go_router.dart';
import 'models/restaurant.dart';
import 'models/product.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/restaurants_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/repartidor_screen.dart';
import 'screens/dueno_screen.dart';
import 'screens/order_history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/registro_repartidor_screen.dart';
import 'screens/registro_restaurante_screen.dart';
import 'screens/dueno_login_screen.dart';
import 'screens/repartidor_login_screen.dart';
import 'screens/flota_screen.dart';
import 'screens/flota_login_screen.dart';

// Router global de la app — se pasa a MaterialApp.router en main.dart
final appRouter = GoRouter(
  initialLocation: '/', // Siempre arranca en el splash
  routes: [
    // Pantalla de carga con el logo (3 segundos, luego redirige según sesión)
    GoRoute(
      path: '/',
      builder: (_, _) => const SplashScreen(),
    ),
    // Login / registro con email, Google o Facebook
    GoRoute(
      path: '/login',
      builder: (_, _) => const LoginScreen(),
    ),
    // Pantalla principal del cliente — lista de restaurantes
    GoRoute(
      path: '/restaurants',
      builder: (_, _) => const RestaurantsScreen(),
    ),
    // Menú de un restaurante específico (recibe objeto Restaurant por extra)
    GoRoute(
      path: '/menu',
      builder: (context, state) =>
          MenuScreen(restaurant: state.extra as Restaurant),
    ),
    // Detalle de un producto con carrusel de imágenes y selector de cantidad
    // Recibe: { product: Product, restaurantId: String }
    GoRoute(
      path: '/product-detail',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ProductDetailScreen(
          product: extra['product'] as Product,
          restaurantId: extra['restaurantId'] as String,
        );
      },
    ),
    // Carrito de compras del cliente
    GoRoute(
      path: '/cart',
      builder: (_, _) => const CartScreen(),
    ),
    // Pantalla de confirmación y pago del pedido
    GoRoute(
      path: '/checkout',
      builder: (_, _) => const CheckoutScreen(),
    ),
    // Panel del repartidor — muestra pedidos pendientes y mapa GPS en tiempo real
    GoRoute(
      path: '/repartidor',
      builder: (_, _) => const RepartidorScreen(),
    ),
    // Panel del dueño del restaurante — gestiona pedidos y configura el restaurante
    GoRoute(
      path: '/dueno',
      builder: (_, _) => const DuenoScreen(),
    ),
    // Historial de pedidos anteriores del cliente
    GoRoute(
      path: '/history',
      builder: (_, _) => const OrderHistoryScreen(),
    ),
    // Perfil del usuario — nombre, foto, dirección, método de pago, tarjeta
    GoRoute(
      path: '/profile',
      builder: (_, _) => const ProfileScreen(),
    ),
    // Formulario de registro para nuevos repartidores
    GoRoute(
      path: '/registro-repartidor',
      builder: (_, _) => const RegistroRepartidorScreen(),
    ),
    // Login exclusivo para dueños de restaurante (tema naranja)
    GoRoute(
      path: '/restaurante',
      builder: (_, _) => const DuenoLoginScreen(),
    ),
    // Login exclusivo para repartidores — deben registrarse primero
    GoRoute(
      path: '/moto',
      builder: (_, _) => const RepartidorLoginScreen(),
    ),
    // Login exclusivo para jefes de flota (tema oscuro azul)
    GoRoute(
      path: '/flota-login',
      builder: (_, _) => const FlotaLoginScreen(),
    ),
    // Panel del jefe de flota — ve riders, ubicaciones y ganancias
    GoRoute(
      path: '/flota',
      builder: (_, _) => const FlotaScreen(),
    ),
    // Formulario de registro para nuevos restaurantes / dueños
    GoRoute(
      path: '/registro-restaurante',
      builder: (_, _) => const RegistroRestauranteScreen(),
    ),
    // Pantalla de seguimiento en tiempo real del pedido en camino
    // Recibe: { restaurantName, address, total, orderId, lat?, lng? }
    GoRoute(
      path: '/tracking',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        if (extra == null) return const SplashScreen();
        return TrackingScreen(
          restaurantName: extra['restaurantName'] as String,
          address: extra['address'] as String,
          total: extra['total'] as double,
          orderId: extra['orderId'] as String? ?? 'o1',
          lat: extra['lat'] as double?,
          lng: extra['lng'] as double?,
        );
      },
    ),
  ],
);
