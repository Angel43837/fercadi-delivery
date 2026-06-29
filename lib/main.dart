// main.dart
// Punto de entrada de la app Grupo Fercadi.
// Inicializa notificaciones, conecta Supabase y lanza la app con los providers globales.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'providers/cart_provider.dart';
import 'providers/app_data_provider.dart';
import 'providers/theme_provider.dart';
import 'router.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConstants.sentryDsn;
      options.environment = AppConstants.sentryDsn.isEmpty ? 'development' : 'production';
      options.tracesSampleRate = 0.3;
      if (!kIsWeb) options.attachScreenshot = true; // No soportado en web
    },
    appRunner: () async {

      // Inicializa Stripe
      try {
        Stripe.publishableKey = AppConstants.stripePublishableKey;
        await Stripe.instance.applySettings();
      } catch (_) {}

      // flutter_local_notifications no soporta web
      if (!kIsWeb) await NotificationService.init();

      // Solo conecta Supabase si no estamos en modo demo (useMock = false)
      if (!SupabaseService.useMock) {
        await Supabase.initialize(
          url: AppConstants.supabaseUrl,
          anonKey: AppConstants.supabaseAnonKey,
        );
        // Crea los buckets de Storage si no existen (fotos de perfil, productos)
        SupabaseService.ensureStorageBuckets();
      }

      runApp(const FercadiApp());
    },
  );
}

// Widget raíz de la app — configura providers globales y el tema visual
class FercadiApp extends StatelessWidget {
  const FercadiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => AppDataProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (ctx, themeProvider, child) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'GOGO FOOD',
          themeMode: themeProvider.isDark ? ThemeMode.dark : ThemeMode.light,
          // ── Tema oscuro ──────────────────────────────────────────────────
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppConstants.bgColor,
            colorScheme: const ColorScheme.dark(
              primary: Color.fromARGB(255, 255, 0, 0),
              surface: AppConstants.surfaceColor,
              onSurface: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppConstants.surfaceColor,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppConstants.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            cardColor: AppConstants.surfaceColor,
          ),
          // ── Tema claro (naranja) ─────────────────────────────────────────
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: AppConstants.primaryColor,
            colorScheme: const ColorScheme.light(
              primary: AppConstants.primaryColor,
              surface: AppConstants.primaryColor,
              onSurface: Colors.white,
            ),  
            appBarTheme: const AppBarTheme(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: Colors.white),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppConstants.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            cardColor: AppConstants.primaryColor,
          ),
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
