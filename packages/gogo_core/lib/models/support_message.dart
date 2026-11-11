// support_message.dart
// Un mensaje del chat de soporte (usuario↔Admin). Corresponde a la tabla
// "support_messages" en Supabase. Mismo rol que order_message.dart pero el
// hilo se identifica por user_id (un usuario, un solo hilo de por vida) en
// vez de por pedido.

class SupportMessage {
  final String id;
  final String userId;
  final String sender; // 'user' | 'admin'
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  const SupportMessage({
    required this.id,
    required this.userId,
    required this.sender,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  bool get isFromAdmin => sender == 'admin';

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        sender: json['sender'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] != null
            ? DateTime.parse(json['read_at'] as String).toLocal()
            : null,
      );
}

// Un hilo de soporte, visto desde el panel de Admin — un renglón por
// usuario, con su mensaje más reciente y cuántos mensajes de ESE usuario
// Admin todavía no ha leído. Corresponde a una fila que regresa el RPC
// get_support_threads().
class SupportThread {
  final String userId;
  final String lastBody;
  final String lastSender;
  final DateTime lastCreatedAt;
  final int unreadCount;

  const SupportThread({
    required this.userId,
    required this.lastBody,
    required this.lastSender,
    required this.lastCreatedAt,
    required this.unreadCount,
  });

  factory SupportThread.fromJson(Map<String, dynamic> json) => SupportThread(
        userId: json['user_id'] as String,
        lastBody: json['last_body'] as String,
        lastSender: json['last_sender'] as String,
        lastCreatedAt: DateTime.parse(json['last_created_at'] as String).toLocal(),
        unreadCount: (json['unread_count'] as num).toInt(),
      );
}
