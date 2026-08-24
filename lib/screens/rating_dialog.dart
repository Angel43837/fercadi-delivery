import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

const _orange = Color(0xFFFF5722);
const _orangeDark = Color(0xFFE64A19);

Future<void> showRatingDialog(
  BuildContext context, {
  required String orderId,
  required bool isDriver,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RatingDialog(orderId: orderId, isDriver: isDriver),
  );
}

class _RatingDialog extends StatefulWidget {
  final String orderId;
  final bool isDriver;
  const _RatingDialog({required this.orderId, required this.isDriver});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  double _tipAmount = 0;
  bool _sending = false;
  String? _tipError;

  static const _tipOptions = [10.0, 20.0, 50.0, 100.0];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una estrella')),
      );
      return;
    }
    setState(() { _sending = true; _tipError = null; });

    // Si hay propina, cobrar con Stripe antes de guardar calificación
    if (!widget.isDriver && _tipAmount > 0) {
      final paid = await _chargeStripeTip(_tipAmount);
      if (!paid) {
        if (mounted) setState(() { _sending = false; });
        return;
      }
    }

    await SupabaseService.submitRating(
      orderId: widget.orderId,
      stars: _stars,
      comment: _commentCtrl.text.trim(),
      tip: (!widget.isDriver && _tipAmount > 0) ? _tipAmount : null,
      isDriver: widget.isDriver,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _chargeStripeTip(double amount) async {
    try {
      // Llama a la Edge Function para crear el PaymentIntent
      final res = await Supabase.instance.client.functions.invoke(
        'create-tip-payment-intent',
        body: {
          'amount': (amount * 100).toInt(), // centavos
          'order_id': widget.orderId,
        },
      );
      final clientSecret = res.data?['client_secret'] as String?;
      if (clientSecret == null) {
        setState(() => _tipError = 'No se pudo iniciar el pago');
        return false;
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'GOGO Food — Propina',
          style: ThemeMode.light,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return false;
      if (mounted) setState(() => _tipError = 'Pago fallido: ${e.error.localizedMessage}');
      return false;
    } catch (_) {
      if (mounted) setState(() => _tipError = 'Error al procesar el pago');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = widget.isDriver ? 'Califica al cliente'    : 'Califica al repartidor';
    final subtitle = widget.isDriver ? 'Tu calificación es requerida' : '¿Cómo fue la entrega?';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: _orange,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ]),
              ),
              if (!widget.isDriver)
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.6), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ]),
            const SizedBox(height: 20),

            // Estrellas
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      i < _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i < _stars ? const Color(0xFFFFB300) : Colors.white.withValues(alpha: 0.55),
                      size: 38,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),

            // Comentario
            TextField(
              controller: _commentCtrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: widget.isDriver
                    ? 'Comentario sobre el cliente (opcional)'
                    : 'Cuéntanos tu experiencia (opcional)',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.2),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white, width: 1.5)),
              ),
            ),

            // Propina con Stripe (solo cliente)
            if (!widget.isDriver) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Propina al repartidor',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Row(
                children: _tipOptions.map((amt) {
                  final selected = _tipAmount == amt;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tipAmount = selected ? 0 : amt),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: selected
                              ? null
                              : Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Column(children: [
                          Text('\$${amt.toInt()}',
                              style: TextStyle(
                                  color: selected ? _orange : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          Text('MXN',
                              style: TextStyle(
                                  color: selected ? _orangeDark : Colors.white.withValues(alpha: 0.6),
                                  fontSize: 9)),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_tipAmount > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.credit_card, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text('Se cobrará \$${_tipAmount.toInt()} MXN con tu tarjeta',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
                ]),
              ],
              if (_tipError != null) ...[
                const SizedBox(height: 6),
                Text(_tipError!,
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ],

            const SizedBox(height: 20),

            // Botón enviar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: _sending
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: _orange, strokeWidth: 2))
                    : Text(
                        _tipAmount > 0
                            ? 'Pagar propina y calificar'
                            : 'Enviar calificación',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
