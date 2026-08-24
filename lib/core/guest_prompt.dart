// guest_prompt.dart
// Hoja modal reutilizable que se muestra cuando un invitado (sin sesión)
// intenta hacer algo que sí necesita cuenta (pagar, ver sus pedidos, etc.).
// Un solo lugar para este mensaje — antes checkout_screen.dart tenía su
// propio diálogo suelto para esto.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'constants.dart';

Future<void> showLoginRequiredSheet(
  BuildContext context, {
  String message = 'Necesitas iniciar sesión para continuar.',
  String? returnTo,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppConstants.surfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Icon(Icons.lock_outline, color: AppConstants.primaryColor, size: 36),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/login', extra: {'returnTo': returnTo});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Iniciar sesión', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/login', extra: {'returnTo': returnTo, 'signUp': true});
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Crear cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Seguir explorando',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
        ]),
      ),
    ),
  );
}
