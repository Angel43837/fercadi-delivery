// soporte_screen.dart
// Entrada al chat de soporte — compartida entre cliente, dueño y
// repartidor (misma idea que avisos_screen.dart: una sola pantalla, una
// sola ruta, usada desde los 3 roles).
//
// El dueño del negocio quiere que esto sea un chatbot con IA más adelante
// ("eso se lo va a poner él") — hoy solo existe el punto de entrada (el
// ícono de audífonos arriba en cada panel) y este aviso de "muy pronto",
// sin inventar un chat que todavía no responde nada de verdad.
import 'package:flutter/material.dart';
import '../core/constants.dart';

class SoporteScreen extends StatelessWidget {
  const SoporteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.primaryColor,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Soporte', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 24),
              const Text('Chat de soporte',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 12),
              Text(
                'Muy pronto vas a poder platicar aquí con nuestro asistente y resolver tus dudas al instante.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
