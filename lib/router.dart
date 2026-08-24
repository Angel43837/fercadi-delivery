// router.dart
// Define todas las rutas de navegación de la app usando go_router.
// Cada GoRoute mapea una URL (path) a una pantalla (builder).
// Para navegar entre pantallas se usa: context.go('/ruta') o context.push('/ruta').
// Las rutas que necesitan datos extras los reciben por state.extra (ej. producto, restaurante).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/product.dart';
import 'screens/splash_screen.dart';
import 'screens/cliente/login_screen.dart';
import 'screens/cliente/reset_password_screen.dart';
import 'screens/legal_document_screen.dart';
import 'core/legal_content.dart';
import 'screens/cliente/restaurants_screen.dart';
import 'screens/cliente/product_detail_screen.dart';
import 'screens/cliente/cart_screen.dart';
import 'screens/cliente/checkout_screen.dart';
import 'screens/cliente/tracking_screen.dart';
import 'screens/repartidor/repartidor_screen.dart';
import 'screens/dueno/dueno_screen.dart';
import 'screens/cliente/order_history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/dueno/dueno_login_screen.dart';
import 'screens/repartidor_login_screen.dart';
import 'screens/repartidor_plus/repartidor_plus_screen.dart';
import 'screens/repartidor_plus/tienda_rider_screen.dart';

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
// Nota: '/profile' no está aquí porque también la usa el repartidor (foto, nombre, CLABE)
const _clientRoutes = {
  '/restaurants', '/menu', '/product-detail',
  '/cart', '/checkout', '/tracking', '/history',
};

// Subconjunto de _clientRoutes que un invitado (sin cuenta) sí puede
// explorar libremente — checkout/tracking/history se quedan protegidas,
// requieren cuenta real.
const _guestBrowsable = {'/restaurants', '/product-detail', '/cart'};

// 'admin' y 'jefe_flota' tienen sus propias apps separadas (main_admin.dart /
// main_flota.dart) y no tienen pantallas dentro de este router.
String _roleHome(String role) {
  switch (role) {
    case 'repartidor_plus': return '/rider';
    case 'repartidor':      return '/repartidor';
    case 'dueno':           return '/dueno';
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
      '/restaurante', '/reset-password', '/privacy-policy', '/terms',
    };
    if (open.contains(loc)) return null;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // Modo invitado: puede explorar restaurantes/producto/carrito sin
      // cuenta — solo se le pide iniciar sesión al intentar pagar de verdad
      // (ver cart_screen.dart/checkout_screen.dart), no antes.
      if (_guestBrowsable.contains(loc)) return null;
      return '/';
    }

    final role = ((user.appMetadata['role'] ?? user.userMetadata?['role']) as String?) ?? 'cliente';

    // Bloquear rutas de cliente a usuarios con otro rol
    if (_clientRoutes.contains(loc) &&
        (role == 'repartidor_plus' || role == 'repartidor' || role == 'dueno')) {
      return _roleHome(role);
    }

    // Bloquear rutas exclusivas de cada rol al resto
    if (loc == '/rider'      && role != 'repartidor_plus') return _roleHome(role);
    if (loc == '/repartidor' && role != 'repartidor')      return _roleHome(role);
    if (loc == '/dueno'      && role != 'dueno' && role != 'admin') return _roleHome(role);

    return null;
  },
  routes: [
    GoRoute(path: '/',          builder: (_, _) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return LoginScreen(
          returnTo: extra?['returnTo'] as String?,
          startInSignUp: extra?['signUp'] as bool? ?? false,
        );
      },
    ),
    GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
    GoRoute(
      path: '/privacy-policy',
      builder: (_, _) => const LegalDocumentScreen(title: 'Aviso de Privacidad', content: kPrivacyPolicy),
    ),
    GoRoute(
      path: '/terms',
      builder: (_, _) => const LegalDocumentScreen(title: 'Términos y Condiciones', content: kTermsAndConditions),
    ),
    GoRoute(path: '/restaurants', builder: (_, _) => const RestaurantsScreen()),
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
    GoRoute(path: '/restaurante',  builder: (_, _) => const DuenoLoginScreen()),
    GoRoute(path: '/dueno-login',  builder: (_, _) => const DuenoLoginScreen()),
    GoRoute(path: '/moto',         builder: (_, _) => const RepartidorLoginScreen()),
    GoRoute(path: '/repartidor-login', builder: (_, _) => const RepartidorLoginScreen()),
    GoRoute(path: '/rider',        builder: (_, _) => const RepartidorPlusScreen()),
    GoRoute(
      path: '/tienda-rider',
      builder: (context, state) => TiendaRiderScreen(currentCoins: (state.extra as int?) ?? 0),
    ),
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
          restaurantImageUrl: extra['restaurantImageUrl'] as String?,
        );
      },
    ),
  ],
);
