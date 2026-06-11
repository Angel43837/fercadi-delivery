// notification_service.dart
// Maneja las notificaciones locales (cuando la app está abierta o minimizada).
// Para notificaciones cuando la app está CERRADA se necesita FCM (ver fcm_service.dart).
// Cada método corresponde a un evento específico del flujo de pedidos.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gogo_channel',
          'GOGO Notificaciones',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  }

  static Future<void> nuevoPedido(String clienteName, double total) =>
      show(
        id: 1,
        title: '🔔 ¡Nuevo pedido!',
        body: '$clienteName • \$${total.toStringAsFixed(0)} MXN',
      );

  static Future<void> pedidoDisponible(String restaurante, double total) =>
      show(
        id: 2,
        title: '🛵 ¡Pedido disponible!',
        body: '$restaurante • \$${total.toStringAsFixed(0)} MXN',
      );

  static Future<void> pedidoEntregado() =>
      show(
        id: 3,
        title: '✅ ¡Pedido entregado!',
        body: 'Tu pedido ha llegado. ¡Buen provecho!',
      );

  static Future<void> pedidoAceptado() =>
      show(
        id: 4,
        title: '🍳 ¡Pedido aceptado!',
        body: 'Tu pedido está siendo preparado en el restaurante.',
      );

  static Future<void> repartidorEnCamino() =>
      show(
        id: 5,
        title: '🛵 ¡Repartidor en camino!',
        body: 'Tu pedido ya viene. ¡Prepárate para recibirlo!',
      );
}
