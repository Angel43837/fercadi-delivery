// otp_code_field.dart
// Casillas de código de 6 dígitos (paquete pinput), mismo estilo visual que
// el resto del login. Incluye autofill del código SMS en iOS de fábrica.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

class OtpCodeField extends StatelessWidget {
  static const length = 6;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool hasError;

  const OtpCodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultTheme = PinTheme(
      width: 46,
      height: 54,
      textStyle: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
    );
    final focusedTheme = defaultTheme.copyDecorationWith(
      border: Border.all(color: Colors.white, width: 1.5),
    );
    final errorTheme = defaultTheme.copyDecorationWith(
      border: Border.all(color: Colors.redAccent, width: 1.5),
    );

    return Pinput(
      length: length,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      defaultPinTheme: defaultTheme,
      focusedPinTheme: focusedTheme,
      submittedPinTheme: defaultTheme,
      errorPinTheme: errorTheme,
      forceErrorState: hasError,
      onCompleted: onCompleted,
      onChanged: onChanged,
    );
  }
}
