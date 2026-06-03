// ── FCM Service ───────────────────────────────────────────────────────────────
// Para activar notificaciones cuando la app está CERRADA, sigue estos pasos:
//
// 1. Ve a https://console.firebase.google.com
// 2. Crea un proyecto "GOGO" → agrega app Android (com.example.landing_test)
// 3. Descarga google-services.json → ponlo en android/app/google-services.json
// 4. En android/settings.gradle.kts → plugins{} agrega:
//       id("com.google.gms.google-services") version "4.4.2" apply false
// 5. En android/app/build.gradle.kts → plugins{} agrega:
//       id("com.google.gms.google-services")
// 6. En pubspec.yaml → dependencies agrega:
//       firebase_core: ^3.0.0
//       firebase_messaging: ^15.0.0
// 7. Corre: flutter pub get
// 8. Descomenta el código en FcmService.init() y _backgroundHandler
// 9. Despliega la Edge Function en supabase/functions/send-order-notification/
//
// Mientras tanto, las notificaciones locales (app abierta/minimizada) ya
// funcionan a través de NotificationService.
// ─────────────────────────────────────────────────────────────────────────────

class FcmService {
  static String? _token;

  static Future<void> init() async {
    // Descomentar después de completar la configuración de Firebase (pasos arriba):
    //
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // final messaging = FirebaseMessaging.instance;
    // await messaging.requestPermission();
    // _token = await messaging.getToken();
    // if (_token != null) {
    //   final user = Supabase.instance.client.auth.currentUser;
    //   if (user != null) {
    //     await Supabase.instance.client.from('user_tokens').upsert({
    //       'user_id': user.id, 'fcm_token': _token, 'updated_at': DateTime.now().toIso8601String(),
    //     });
    //   }
    // }
    // FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
    // FirebaseMessaging.onMessage.listen((msg) {
    //   final n = msg.notification;
    //   if (n != null) NotificationService.show(title: n.title ?? '', body: n.body ?? '');
    // });
  }

  static String? get token => _token;
}

// Descomentar después de configurar Firebase:
// @pragma('vm:entry-point')
// Future<void> _backgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
// }
