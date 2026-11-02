// soporte_screen.dart
// Chat real de soporte — compartido entre cliente, dueño y repartidor
// (misma idea que avisos_screen.dart: una sola pantalla, una sola ruta,
// usada desde los 3 roles). Reemplaza el placeholder "muy pronto" —
// mismo patrón de UI/realtime que chat_screen.dart (el chat interno
// cliente↔repartidor por pedido), pero el hilo es por usuario en vez de
// por pedido: cada usuario tiene un solo hilo de por vida con soporte, y
// Admin contesta desde admin_soporte_screen.dart.
//
// No hay nadie contestando al instante todavía (Admin revisa su panel
// cuando puede) — se avisa con una nota breve arriba en vez de aparentar
// que es un chatbot con IA respondiendo en el momento.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/support_message.dart';
import '../services/supabase_service.dart';

class _ChatItem {
  final String id;
  final String sender;
  final String body;
  final DateTime createdAt;
  final bool isMine;
  bool pending;
  bool failed = false;
  _ChatItem({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
    required this.isMine,
    this.pending = false,
  });
}

class SoporteScreen extends StatefulWidget {
  const SoporteScreen({super.key});

  @override
  State<SoporteScreen> createState() => _SoporteScreenState();
}

class _SoporteScreenState extends State<SoporteScreen> {
  final List<_ChatItem> _items = [];
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;
  bool _loading = true;
  int _tempCounter = 0;

  @override
  void initState() {
    super.initState();
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
    List<SupportMessage> msgs = [];
    try {
      msgs = await SupabaseService.getMySupportMessages();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items.clear();
      _items.addAll(msgs.map((m) => _ChatItem(
            id: m.id,
            sender: m.sender,
            body: m.body,
            createdAt: m.createdAt,
            isMine: m.sender == 'user',
          )));
      _loading = false;
    });
    _scrollToBottomSoon();

    // Marca como leídas las respuestas de Admin que ya se están viendo.
    try {
      await SupabaseService.markSupportMessagesRead(
        Supabase.instance.client.auth.currentUser?.id ?? '',
      );
    } catch (_) {}

    // Solo agrega por Realtime los mensajes de Admin — los míos ya se
    // muestran de inmediato (optimista) al mandarlos, así se evita
    // duplicar el mismo mensaje dos veces en la lista.
    _channel = SupabaseService.subscribeToMySupportMessages((m) {
      if (!mounted || m.sender == 'user') return;
      setState(() => _items.add(_ChatItem(
            id: m.id,
            sender: m.sender,
            body: m.body,
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
      sender: 'user',
      body: text,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    setState(() => _items.add(item));
    _scrollToBottomSoon();
    try {
      await SupabaseService.sendSupportMessage(text);
      if (mounted) setState(() => item.pending = false);
    } catch (_) {
      if (mounted) setState(() { item.pending = false; item.failed = true; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo enviar tu mensaje — toca para reintentar'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _retry(_ChatItem item) async {
    setState(() { item.failed = false; item.pending = true; });
    try {
      await SupabaseService.sendSupportMessage(item.body);
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.headset_mic_rounded, color: AppConstants.primaryColor, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Soporte', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: AppConstants.primaryColor.withValues(alpha: 0.12),
            child: Text(
              'Te contestamos lo antes posible — todavía no hay nadie respondiendo al instante.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryColor))
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text('Cuéntanos en qué podemos ayudarte',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _buildBubble(_items[i]),
                      ),
          ),
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
                    hintText: 'Escribe tu mensaje...',
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
            if (!item.isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('Soporte GOGO',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            Text(item.body, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
