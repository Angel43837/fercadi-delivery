// legal_document_screen.dart
// Pantalla genérica para mostrar un documento legal completo (Aviso de
// Privacidad o Términos y Condiciones) — recibe el título y el texto ya
// armados desde core/legal_content.dart.

import 'package:flutter/material.dart';
import '../core/constants.dart';

class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String content;
  const LegalDocumentScreen({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.primaryColor,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          content,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}
