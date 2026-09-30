// chat_screen.dart
// Chat interno del pedido — reemplaza la necesidad de intercambiar números
// telefónicos entre cliente y repartidor. Compartida entre la app de
// cliente y las 2 de repartidor (flota y repartidor_plus): quien la abre
// ya trae el id/nombre/foto de la contraparte (los 3 ya lo cargan para su
// propia tarjeta de "tu repartidor"/"datos del cliente").

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/order_message.dart';
import '../services/supabase_service.dart';

class _ChatItem {
  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool isMine;
  bool pending;
  bool failed = false;
  _ChatItem({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.pending = false,
  });
}

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String counterpartName;
  final String? counterpartPhoto;
  // true si el pedido ya se entregó/canceló — bloquea mandar mensajes
  // nuevos (RLS ya lo impide en el backend, esto solo evita el intento
  // fallido y explica por qué).
  final bool locked;

  const ChatScreen({
    super.key,
    required this.orderId,
    required this.counterpartName,
    this.counterpartPhoto,
    this.locked = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<_ChatItem> _items = [];
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _myId;
  int _tempCounter = 0;

  @override
  void initState() {
    super.initState();
    _myId = Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<OrderMessage> msgs = [];
    try {
      msgs = await SupabaseService.getOrderMessages(widget.orderId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items.clear();
      _items.addAll(msgs.map((m) => _ChatItem(
            id: m.id,
            senderId: m.senderId,
            content: m.content,
            createdAt: m.createdAt,
            isMine: m.senderId == _myId,
          )));
      _loading = false;
    });
    _scrollToBottomSoon();

    // Solo agrega por Realtime los mensajes de LA OTRA persona — los míos
    // ya se muestran de inmediato (optimista) al mandarlos, así se evita
    // duplicar el mismo mensaje dos veces en la lista.
    _channel = SupabaseService.subscribeToOrderMessages(widget.orderId, (m) {
      if (!mounted || m.senderId == _myId) return;
      setState(() => _items.add(_ChatItem(
            id: m.id,
            senderId: m.senderId,
            content: m.content,
            createdAt: m.createdAt,
            isMine: false,
          )));
      _scrollToBottomSoon();
    });
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    final tempId = 'temp_${_tempCounter++}';
    final item = _ChatItem(
      id: tempId,
      senderId: _myId ?? '',
      content: text,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    setState(() => _items.add(item));
    _scrollToBottomSoon();
    try {
      await SupabaseService.sendOrderMessage(widget.orderId, text);
      if (mounted) setState(() => item.pending = false);
    } catch (_) {
      if (mounted) setState(() { item.pending = false; item.failed = true; });
    }
  }

  Future<void> _retry(_ChatItem item) async {
    setState(() { item.failed = false; item.pending = true; });
    try {
      await SupabaseService.sendOrderMessage(widget.orderId, item.content);
      if (mounted) setState(() => item.pending = false);
    } catch (_) {
      if (mounted) setState(() { item.pending = false; item.failed = true; });
    }
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'a.m.' : 'p.m.';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceColor,
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppConstants.primaryColor.withValues(alpha: 0.15),
            backgroundImage: (widget.counterpartPhoto != null && widget.counterpartPhoto!.isNotEmpty)
                ? NetworkImage(widget.counterpartPhoto!)
                : null,
            child: (widget.counterpartPhoto == null || widget.counterpartPhoto!.isEmpty)
                ? const Icon(Icons.person, color: AppConstants.primaryColor, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.counterpartName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                : _items.isEmpty
                    ? Center(
                        child: Text('Manda el primer mensaje',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _buildBubble(_items[i]),
                      ),
          ),
          if (widget.locked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              color: AppConstants.surfaceColor,
              child: Text('Este pedido ya terminó — ya no se pueden enviar mensajes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              color: AppConstants.surfaceColor,
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    style: const TextStyle(color: Colors.white),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                      filled: true,
                      fillColor: AppConstants.bgColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(color: AppConstants.primaryColor, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    onPressed: _send,
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _buildBubble(_ChatItem item) {
    return Align(
      alignment: item.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: item.failed ? () => _retry(item) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          decoration: BoxDecoration(
            color: item.failed
                ? Colors.redAccent.withValues(alpha: 0.25)
                : item.isMine
                    ? AppConstants.primaryColor
                    : AppConstants.surfaceColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(item.isMine ? 16 : 4),
              bottomRight: Radius.circular(item.isMine ? 4 : 16),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(item.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (item.failed) ...[
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 12),
                const SizedBox(width: 4),
                const Text('No se envió — toca para reintentar',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10)),
              ] else ...[
                Text(_formatTime(item.createdAt),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
                if (item.isMine) ...[
                  const SizedBox(width: 4),
                  item.pending
                      ? SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white.withValues(alpha: 0.7)),
                        )
                      : Icon(Icons.check, color: Colors.white.withValues(alpha: 0.7), size: 12),
                ],
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
