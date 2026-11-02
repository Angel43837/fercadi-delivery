// Módulo "Soporte" del panel de Admin — chat real y bidireccional con
// cualquier usuario (cliente, dueño o repartidor) que escriba desde el
// ícono de audífonos de su panel (soporte_screen.dart). Lista de hilos
// (uno por usuario, vía el RPC get_support_threads()) + vista de chat por
// usuario, mismo patrón de burbujas/realtime que chat_screen.dart (el chat
// interno cliente↔repartidor por pedido), aquí del lado de Admin.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/support_message.dart';
import '../../services/supabase_service.dart';
import '../../theme/admin_theme.dart';
import '../../theme/admin_widgets.dart';

class AdminSoporteScreen extends StatefulWidget {
  const AdminSoporteScreen({super.key});
  @override
  State<AdminSoporteScreen> createState() => _AdminSoporteScreenState();
}

class _AdminSoporteScreenState extends State<AdminSoporteScreen> {
  bool _loading = true;
  List<SupportThread> _threads = [];
  final Map<String, Map<String, dynamic>?> _userInfo = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<SupportThread> threads = [];
    try {
      threads = await SupabaseService.getSupportThreads();
    } catch (_) {}
    if (mounted) setState(() { _threads = threads; _loading = false; });
    await _loadUserInfo(threads);
  }

  Future<void> _loadUserInfo(List<SupportThread> threads) async {
    for (final t in threads) {
      if (_userInfo.containsKey(t.userId)) continue;
      final info = await SupabaseService.lookupAuthUser(t.userId);
      _userInfo[t.userId] = info;
      if (mounted) setState(() {});
    }
  }

  String _nameFor(String userId) {
    final info = _userInfo[userId];
    final name = info?['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final email = info?['email'] as String?;
    if (email != null && email.isNotEmpty) return email;
    return 'Usuario ${userId.substring(0, userId.length < 8 ? userId.length : 8)}';
  }

  Future<void> _openThread(SupportThread t) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => _AdminSoporteChatScreen(
        userId: t.userId,
        userName: _nameFor(t.userId),
      ),
    ));
    _load();
  }

  String _fmtFecha(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'a.m.' : 'p.m.';
    if (sameDay) return '$h:$m $ampm';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: const Text('Soporte', style: TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
          : _threads.isEmpty
              ? Center(child: Text('Nadie ha escrito a soporte todavía', style: TextStyle(color: AdminColors.textFaint)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _threads.length,
                    itemBuilder: (_, i) => _buildCard(_threads[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(SupportThread t) {
    final name = _nameFor(t.userId);
    final avatarUrl = _userInfo[t.userId]?['avatarUrl'] as String?;
    final preview = t.lastSender == 'admin' ? 'Tú: ${t.lastBody}' : t.lastBody;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _openThread(t),
        child: AdminSectionCard(
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AdminColors.surfaceElevated,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
              child: (avatarUrl == null || avatarUrl.isEmpty) ? Icon(Icons.person_outline, color: AdminColors.textFaint) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtFecha(t.lastCreatedAt), style: TextStyle(color: AdminColors.textFaint, fontSize: 11)),
              const SizedBox(height: 6),
              if (t.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AdminColors.statusCancelled, borderRadius: BorderRadius.circular(10)),
                  child: Text('${t.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ChatItem {
  final String id;
  final String sender;
  final String body;
  final DateTime createdAt;
  _ChatItem({required this.id, required this.sender, required this.body, required this.createdAt});
}

class _AdminSoporteChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  const _AdminSoporteChatScreen({required this.userId, required this.userName});

  @override
  State<_AdminSoporteChatScreen> createState() => _AdminSoporteChatScreenState();
}

class _AdminSoporteChatScreenState extends State<_AdminSoporteChatScreen> {
  final List<_ChatItem> _items = [];
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;

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
      msgs = await SupabaseService.getSupportMessagesForUser(widget.userId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _items.clear();
      _items.addAll(msgs.map((m) => _ChatItem(id: m.id, sender: m.sender, body: m.body, createdAt: m.createdAt)));
      _loading = false;
    });
    _scrollToBottomSoon();

    // Marca como leídos los mensajes del usuario que Admin está viendo
    // ahora — esto es lo que baja el badge de "Más → Soporte".
    try {
      await SupabaseService.markSupportMessagesRead(widget.userId);
    } catch (_) {}

    _channel = SupabaseService.subscribeToSupportMessagesForUser(widget.userId, (m) {
      if (!mounted || m.sender == 'admin') return;
      setState(() => _items.add(_ChatItem(id: m.id, sender: m.sender, body: m.body, createdAt: m.createdAt)));
      _scrollToBottomSoon();
      SupabaseService.markSupportMessagesRead(widget.userId).catchError((_) {});
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
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() => _sending = true);
    try {
      await SupabaseService.sendSupportMessageAsAdmin(widget.userId, text);
      if (mounted) {
        setState(() {
          _items.add(_ChatItem(id: 'local_${_items.length}', sender: 'admin', body: text, createdAt: DateTime.now()));
          _sending = false;
        });
        _scrollToBottomSoon();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        _textCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo enviar: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AdminColors.statusCancelled,
        ));
      }
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
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        title: Text(widget.userName, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AdminColors.accent))
                : _items.isEmpty
                    ? Center(child: Text('Todavía no hay mensajes en este hilo', style: TextStyle(color: AdminColors.textFaint)))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _buildBubble(_items[i]),
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: AdminColors.surface,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  style: const TextStyle(color: AdminColors.textPrimary),
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribe tu respuesta...',
                    hintStyle: TextStyle(color: AdminColors.textFaint),
                    filled: true,
                    fillColor: AdminColors.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(color: AdminColors.accent, shape: BoxShape.circle),
                child: IconButton(
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  onPressed: _sending ? null : _send,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildBubble(_ChatItem item) {
    final isMine = item.sender == 'admin';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMine ? AdminColors.accent : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(item.body, style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          Text(_formatTime(item.createdAt), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
        ]),
      ),
    );
  }
}
