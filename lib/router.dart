// router.dart
// Define todas las rutas de navegación de la app usando go_router.
// Cada GoRoute mapea una URL (path) a una pantalla (builder).
// Para navegar entre pantallas se usa: context.go('/ruta') o context.push('/ruta').
// Las rutas que necesitan datos extras los reciben por state.extra (ej. producto, restaurante).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'screens/repartidor_plus_screen.dart';
import 'screens/registro_rider_plus_screen.dart';

// Notifica a GoRouter cada vez que el estado de autenticación de Supabase cambia.
// Con refreshListenable el router re-evalúa el redirect al restaurar la sesión del
// localStorage en web — sin esto hay una condición de carrera en la carga inicial.
class _SupabaseAuthNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;
  _SupabaseAuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}

// Rutas que solo el cliente puede ver
const _clientRoutes = {
  '/restaurants', '/menu', '/product-detail',
  '/cart', '/checkout', '/tracking', '/history', '/profile',
};

String _roleHome(String role) {
  switch (role) {
    case 'repartidor_plus': return '/rider';
    case 'repartidor':      return '/repartidor';
    case 'dueno':           return '/dueno';
    case 'admin':           return '/admin';
    case 'jefe_flota':      return '/flota';
    default:                return '/restaurants';
  }
}

// Router global de la app — se pasa a MaterialApp.router en main.dart
final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _SupabaseAuthNotifier(),
  redirect: (context, state) {
    final loc = state.matchedLocation;

    // Rutas públicas sin restricción
    const open = {
      '/', '/login', '/moto', '/repartidor-login', '/dueno-login',
      '/restaurante', '/registro-repartidor', '/registro-rider',
      '/registro-restaurante', '/flota-login',
    };
    if (open.contains(loc)) return null;

    final user = Supabase.instance.client.auth.currentUser;
    // Sin sesión en rutas protegidas → splash, que espera a Supabase y redirige según rol
    if (user == null) return '/';

    final role = (user.userMetadata?['role'] as String?) ?? 'cliente';

    // Bloquear rutas de cliente a usuarios con otro rol
    if (_clientRoutes.contains(loc) &&
        (role == 'repartidor_plus' || role == 'repartidor' ||
         role == 'dueno'           || role == 'admin'       || role == 'jefe_flota')) {
      return _roleHome(role);
    }

    // Bloquear rutas exclusivas de cada rol al resto
    if (loc == '/rider'      && role != 'repartidor_plus') return _roleHome(role);
    if (loc == '/repartidor' && role != 'repartidor')      return _roleHome(role);
    if (loc == '/dueno'      && role != 'dueno' && role != 'admin') return _roleHome(role);
    if (loc == '/admin'      && role != 'admin')           return _roleHome(role);
    if (loc == '/flota'      && role != 'jefe_flota')      return _roleHome(role);

    return null;
  },
  routes: [
    GoRoute(path: '/',          builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/login',     builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/restaurants', builder: (_, _) => const RestaurantsScreen()),
    GoRoute(
      path: '/menu',
      builder: (context, state) => MenuScreen(restaurant: state.extra as Restaurant),
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
    GoRoute(path: '/cart',      builder: (_, _) => const CartScreen()),
    GoRoute(path: '/checkout',  builder: (_, _) => const CheckoutScreen()),
    GoRoute(path: '/repartidor', builder: (_, _) => const RepartidorScreen()),
    GoRoute(path: '/dueno',     builder: (_, _) => const DuenoScreen()),
    GoRoute(path: '/history',   builder: (_, _) => const OrderHistoryScreen()),
    GoRoute(path: '/profile',   builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/registro-repartidor', builder: (_, _) => const RegistroRepartidorScreen()),
    GoRoute(path: '/restaurante',  builder: (_, _) => const DuenoLoginScreen()),
    GoRoute(path: '/dueno-login',  builder: (_, _) => const DuenoLoginScreen()),
    GoRoute(path: '/moto',         builder: (_, _) => const RepartidorLoginScreen()),
    GoRoute(path: '/repartidor-login', builder: (_, _) => const RepartidorLoginScreen()),
    GoRoute(path: '/rider',        builder: (_, _) => const RepartidorPlusScreen()),
    GoRoute(path: '/registro-rider', builder: (_, _) => const RegistroRiderPlusScreen()),
    GoRoute(path: '/flota-login',  builder: (_, _) => const FlotaLoginScreen()),
    GoRoute(path: '/flota',        builder: (_, _) => const FlotaScreen()),
    GoRoute(path: '/registro-restaurante', builder: (_, _) => const RegistroRestauranteScreen()),
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
