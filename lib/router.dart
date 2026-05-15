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
import 'screens/admin_screen.dart';
import 'screens/dueno_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, _) => const LoginScreen(),
    ),
    GoRoute(
      path: '/restaurants',
      builder: (_, _) => const RestaurantsScreen(),
    ),
    GoRoute(
      path: '/menu',
      builder: (context, state) =>
          MenuScreen(restaurant: state.extra as Restaurant),
    ),
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
    GoRoute(
      path: '/cart',
      builder: (_, _) => const CartScreen(),
    ),
    GoRoute(
      path: '/checkout',
      builder: (_, _) => const CheckoutScreen(),
    ),
    GoRoute(
      path: '/repartidor',
      builder: (_, _) => const RepartidorScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, _) => const AdminScreen(),
    ),
    GoRoute(
      path: '/dueno',
      builder: (_, _) => const DuenoScreen(),
    ),
    GoRoute(
      path: '/tracking',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return TrackingScreen(
          restaurantName: extra['restaurantName'] as String,
          address: extra['address'] as String,
          total: extra['total'] as double,
        );
      },
    ),
  ],
);
