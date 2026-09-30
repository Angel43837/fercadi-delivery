// order_message.dart
// Un mensaje del chat interno cliente↔repartidor de un pedido.
// Corresponde a la tabla "order_messages" en Supabase.

class OrderMessage {
  final String id;
  final String orderId;
  final String senderId;
  final String content;
  final DateTime createdAt;

  const OrderMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory OrderMessage.fromJson(Map<String, dynamic> json) => OrderMessage(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        senderId: json['sender_id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
