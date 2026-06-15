import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'providers/app_data_provider.dart';
import 'screens/admin_screen.dart';
import 'screens/admin_login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
  runApp(const AdminApp());
}

final _adminRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    if (state.matchedLocation == '/login') return null;
    final session = await AuthService.getSession();
    if (session == null) return '/login';
    if (session.role != '/admin') return '/login';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, _) => const AdminLoginScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, _) => const AdminScreen(),
    ),
  ],
);

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppDataProvider(),
      child: MaterialApp.router(
        title: 'GOGO Food — Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: AppConstants.bgColor,
          colorScheme: const ColorScheme.dark(primary: AppConstants.primaryColor),
        ),
        routerConfig: _adminRouter,
      ),
    );
  }
}
