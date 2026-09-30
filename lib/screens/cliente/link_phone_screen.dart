// link_phone_screen.dart
// Vincula un número de teléfono a una cuenta que ya existe (correo, Google o
// Facebook) — para que, de ahí en adelante, esa cuenta también pueda entrar
// por teléfono+OTP. Se abre desde profile_screen.dart ("Vincular número de
// teléfono", solo visible si la cuenta todavía no tiene uno).
//
// A diferencia del login por teléfono (login_screen.dart), aquí ya hay una
// sesión activa — no hace falta "completar perfil" ni decidir a dónde
// navegar: solo confirmar y volver.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../widgets/phone_otp/phone_otp_flow.dart';

class LinkPhoneScreen extends StatelessWidget {
  const LinkPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.bgColor,
        elevation: 0,
        title: const Text('Vincular teléfono', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Agrega tu número para poder entrar más rápido la próxima vez, sin correo ni contraseña.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13.5),
              ),
              const SizedBox(height: 24),
              PhoneOtpFlow(
                mode: PhoneAuthMode.linkExisting,
                onVerified: (res, {required isNewUser}) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Teléfono vinculado correctamente.'),
                      backgroundColor: Colors.green));
                  Navigator.of(context).pop(res.user?.phone);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
