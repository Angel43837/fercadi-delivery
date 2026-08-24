// fcm_service.dart
// Notificaciones push reales (app cerrada o en segundo plano), vía Firebase
// Cloud Messaging + Apple Push Notification service.
//
// Requiere un proyecto de Firebase con:
//   - ios/Runner/GoogleService-Info.plist
//   - android/app/google-services.json  (+ aplicar el plugin de Gradle,
//     ver android/app/build.gradle.kts)
//
// Sin esos archivos, Firebase.initializeApp() lanza una excepción que se
// atrapa abajo — la app sigue funcionando exactamente igual que antes, solo
// con las notificaciones locales de NotificationService (app abierta/recién
// en segundo plano). En cuanto los archivos existan, esto se activa solo,
// sin volver a tocar código.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';

// Debe ser una función de nivel superior (no un método de clase) para que el
// motor de Dart pueda lanzarla en un isolate aparte cuando llega un mensaje
// con la app completamente cerrada.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FcmService {
  static String? _token;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      _token = await messaging.getToken();
      messaging.onTokenRefresh.listen((newToken) => _token = newToken);

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // En primer plano, FCM no muestra la notificación del sistema sola —
      // se dispara como notificación local, mismo camino que ya existe.
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n != null) {
          NotificationService.show(title: n.title ?? '', body: n.body ?? '');
        }
      });
    } catch (_) {
      // Firebase todavía no configurado — no pasa nada, ver comentario arriba.
    }
  }

  static String? get token => _token;
}
