// phone_otp_flow.dart
// Máquina de estados real del login/registro por teléfono + código OTP.
// Se usa en dos lugares con el mismo widget (nada duplicado):
//   - login_screen.dart, mode: login — signInWithOtp + verifyOTP(type: sms).
//   - profile_screen.dart, mode: linkExisting — vincular un teléfono a una
//     cuenta ya existente (correo/Google/Facebook), usa
//     updateUser(phone:) + verifyOTP(type: phoneChange).
//
// Dos pasos: enterPhone (teléfono → "Enviar código") y enterCode (6 dígitos
// → "Verificar"). Reglas anti-abuso del lado cliente (además de lo que ya
// hace Supabase del lado servidor): cooldown de reenvío y límite de
// intentos de código incorrecto.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'otp_code_field.dart';
import 'phone_number_field.dart';

enum PhoneAuthMode { login, linkExisting }

class PhoneOtpFlow extends StatefulWidget {
  final PhoneAuthMode mode;

  /// Se llama justo después de un verifyOTP exitoso. [isNewUser] solo es
  /// significativo en mode: login (indica que la cuenta no tenía rol
  /// todavía, es decir, es de alta nueva) — en mode: linkExisting siempre
  /// llega en false y puede ignorarse.
  final void Function(AuthResponse res, {required bool isNewUser}) onVerified;

  /// Se llama justo antes de mandar el primer código (no en un reenvío) —
  /// para que quien use el widget pueda exigir algo antes (ej. aceptar
  /// términos). Si regresa false, no se manda nada — quien implementa esto
  /// ya se encarga de avisarle al usuario por qué (ej. sacudir el checkbox
  /// de términos).
  final Future<bool> Function()? beforeFirstSend;

  /// Se llama justo antes de verifyOTP — sirve para que la pantalla que usa
  /// este widget pueda ignorar, por un instante, el evento global
  /// `AuthChangeEvent.signedIn` que Supabase dispara como efecto secundario
  /// de verifyOTP (mismo patrón que ya usa login_screen.dart para el flujo
  /// de recuperar contraseña).
  final VoidCallback? onWillVerify;

  const PhoneOtpFlow({
    super.key,
    required this.mode,
    required this.onVerified,
    this.beforeFirstSend,
    this.onWillVerify,
  });

  @override
  State<PhoneOtpFlow> createState() => _PhoneOtpFlowState();
}

enum _Step { enterPhone, enterCode }

class _PhoneOtpFlowState extends State<PhoneOtpFlow> {
  static const _maxAttempts = 5;
  static const _cooldownSeconds = 45;

  final _phoneController = PhoneController(null);
  final _codeController  = TextEditingController();
  final _codeFocus       = FocusNode();

  _Step   _step        = _Step.enterPhone;
  PhoneNumber? _phone;
  bool    _loading      = false;
  String? _error;
  bool    _codeError    = false;
  int     _attempts     = 0;
  Timer?  _cooldownTimer;
  int     _cooldown     = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String get _e164 => _phone!.international;

  Future<void> _sendCode({required bool isResend}) async {
    if (!isValidPhoneNumber(_phone)) {
      setState(() => _error = 'Ingresa un número de teléfono válido.');
      return;
    }
    if (!isResend && widget.beforeFirstSend != null) {
      final ok = await widget.beforeFirstSend!();
      if (!ok) return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.mode == PhoneAuthMode.login) {
        await Supabase.instance.client.auth
            .signInWithOtp(phone: _e164, shouldCreateUser: true);
      } else {
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(phone: _e164));
      }
      if (!mounted) return;
      setState(() {
        _step        = _Step.enterCode;
        _attempts    = 0;
        _codeError   = false;
        _error       = null;
        _codeController.clear();
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _mapAuthError(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo enviar el código. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != OtpCodeField.length || _loading) return;
    setState(() { _loading = true; _error = null; _codeError = false; });
    widget.onWillVerify?.call();
    try {
      final type = widget.mode == PhoneAuthMode.login ? OtpType.sms : OtpType.phoneChange;
      final res = await Supabase.instance.client.auth.verifyOTP(
        phone: _e164,
        token: code,
        type: type,
      );
      final user = res.user;
      final isNewUser = user != null &&
          user.appMetadata['role'] == null &&
          user.userMetadata?['role'] == null;
      widget.onVerified(res, isNewUser: isNewUser);
    } on AuthException catch (e) {
      _attempts++;
      if (mounted) {
        setState(() {
          _codeError = true;
          _error     = _mapAuthError(e);
          _codeController.clear();
        });
      }
    } catch (_) {
      _attempts++;
      if (mounted) {
        setState(() {
          _codeError = true;
          _error     = 'No se pudo verificar el código. Intenta de nuevo.';
          _codeController.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Códigos de error de Supabase Auth (string literal, no un enum importado
  // — gotrue no expone su ErrorCode públicamente fuera de lib/src). Lista
  // completa: https://supabase.com/docs/guides/auth/debugging/error-codes
  String _mapAuthError(AuthException e) {
    switch (e.code) {
      case 'otp_expired':
        return 'El código expiró. Solicita uno nuevo.';
      case 'over_sms_send_rate_limit':
        return 'Espera un momento antes de pedir otro código.';
      case 'phone_exists':
        return 'Este número ya está vinculado a otra cuenta.';
      case 'phone_provider_disabled':
        return 'El login por teléfono todavía no está activado. Intenta con correo o Google.';
      case 'sms_send_failed':
        return 'No se pudo enviar el SMS. Verifica el número e intenta de nuevo.';
      case 'validation_failed':
        return 'Número de teléfono inválido.';
      default:
        // Supabase no expone un código específico para "código incorrecto" —
        // llega como un error genérico (403), así que se asume eso cuando no
        // coincide con ninguno de los códigos de arriba.
        return _step == _Step.enterCode
            ? 'Código incorrecto. Verifica los 6 dígitos e intenta de nuevo.'
            : e.message;
    }
  }

  void _backToPhone() {
    _cooldownTimer?.cancel();
    setState(() {
      _step      = _Step.enterPhone;
      _error     = null;
      _codeError = false;
      _attempts  = 0;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _step == _Step.enterPhone ? _buildPhoneStep() : _buildCodeStep(),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      key: const ValueKey('enterPhone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneNumberField(
          controller: _phoneController,
          enabled: !_loading,
          onChanged: (p) => setState(() => _phone = p),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorBanner(_error!),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _loading ? null : () => _sendCode(isResend: false),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('ENVIAR CÓDIGO', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    final canVerify = _codeController.text.trim().length == OtpCodeField.length &&
        _attempts < _maxAttempts;
    final blockedByAttempts = _attempts >= _maxAttempts;
    return Column(
      key: const ValueKey('enterCode'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _loading ? null : _backToPhone,
              icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Código enviado a ${_phone?.international ?? ''}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: OtpCodeField(
            controller: _codeController,
            focusNode: _codeFocus,
            enabled: !_loading && !blockedByAttempts,
            hasError: _codeError,
            onChanged: (_) => setState(() {}),
            onCompleted: (_) => _verifyCode(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(_error!),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: (!canVerify || _loading) ? null : _verifyCode,
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('VERIFICAR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: (_cooldown > 0 || _loading) ? null : () => _sendCode(isResend: true),
            child: Text(
              _cooldown > 0 ? 'Reenviar en 0:${_cooldown.toString().padLeft(2, '0')}' : 'Reenviar código',
              style: TextStyle(color: Colors.white.withValues(alpha: _cooldown > 0 ? 0.4 : 0.85)),
            ),
          ),
        ),
        if (blockedByAttempts)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Demasiados intentos. Pide un código nuevo para volver a intentar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.redAccent, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );
  }
}
