import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'providers/cart_provider.dart';
import 'providers/app_data_provider.dart';
import 'router.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseService.useMock) {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }
  runApp(const FercadiApp());
}

class FercadiApp extends StatelessWidget {
  const FercadiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => AppDataProvider()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Grupo Fercadi',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppConstants.bgColor,
          colorScheme: const ColorScheme.dark(
            primary: AppConstants.primaryColor,
            surface: AppConstants.surfaceColor,
            onSurface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppConstants.bgColor,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
          cardColor: AppConstants.surfaceColor,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
