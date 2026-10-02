// avisos_screen.dart
// Mensajes que Admin le manda directo a esta cuenta (ej. "tu identificación
// salió borrosa, vuelve a subirla"). Compartida entre cliente y repartidor
// (igual que profile_screen.dart) — quien la abre solo ve los suyos, RLS
// ya lo garantiza.

import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/supabase_service.dart';

class AvisosScreen extends StatefulWidget {
  const AvisosScreen({super.key});

  @override
  State<AvisosScreen> createState() => _AvisosScreenState();
}

class _AvisosScreenState extends State<AvisosScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await SupabaseService.getMyAdminMessages();
    if (!mounted) return;
    setState(() {
      _messages = data;
      _loading = false;
    });
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _open(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final wasUnread = m['read_at'] == null;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: Text(m['title'] as String? ?? 'Aviso',
            style: const TextStyle(color: Colors.white)),
        content: Text(m['body'] as String? ?? '',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (wasUnread) {
      await SupabaseService.markAdminMessageRead(id);
      if (mounted) {
        setState(() {
          m['read_at'] = DateTime.now().toIso8601String();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Avisos', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryColor),
            )
          : _messages.isEmpty
              ? Center(
                  child: Text('No tienes avisos todavía',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final unread = m['read_at'] == null;
                    final createdAt =
                        DateTime.tryParse(m['created_at'] as String? ?? '') ??
                            DateTime.now();
                    return GestureDetector(
                      onTap: () => _open(m),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppConstants.surfaceColor,
                          borderRadius: BorderRadius.circular(14),
                          border: unread
                              ? Border.all(color: AppConstants.primaryColor.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (unread)
                              Container(
                                margin: const EdgeInsets.only(top: 5, right: 10),
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: AppConstants.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['title'] as String? ?? 'Aviso',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m['body'] as String? ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatDate(createdAt),
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
