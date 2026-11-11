import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gogo_core/services/supabase_service.dart';

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
  // true en cuanto la calificación ya quedó guardada de verdad — a partir de
  // ahí, si la propina falló/se canceló, el botón de abajo cambia a
  // "Reintentar propina" en vez de volver a mandar toda la calificación.
  bool _ratingSaved = false;

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

    // Si hay propina, se intenta cobrar con Stripe — pero la calificación se
    // guarda de todos modos aunque la propina falle o se cancele. Antes un
    // pago de propina rechazado se llevaba entre las patas la calificación
    // completa (el cliente perdía su estrella/comentario sin enterarse).
    // El monto que se guarda es el que el SERVIDOR confirma que de verdad
    // va a cobrar (puede no ser _tipAmount si se reusó el de un intento
    // anterior), nunca el elegido en la UI a ciegas.
    double? chargedTip;
    if (!widget.isDriver && _tipAmount > 0) {
      chargedTip = await _chargeStripeTip(_tipAmount);
    }

    try {
      await SupabaseService.submitRating(
        orderId: widget.orderId,
        stars: _stars,
        comment: _commentCtrl.text.trim(),
        tip: chargedTip,
        isDriver: widget.isDriver,
      );
      _ratingSaved = true;
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar tu calificación. Intenta de nuevo.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    if (!mounted) return;
    setState(() { _sending = false; });
    if (!widget.isDriver && _tipAmount > 0 && chargedTip == null) {
      // No se cierra solo: la calificación ya quedó guardada, pero se deja
      // ver el error de la propina con el botón de "Reintentar propina" para
      // que el cliente decida si reintenta o cierra sin ella.
      return;
    }
    Navigator.of(context).pop();
  }

  // Reintento SOLO de la propina — la calificación ya se guardó en _submit,
  // aquí solo se vuelve a cobrar y, si sale bien, se actualiza ratings.tip
  // (upsert por order_id+is_driver, ver submitRating).
  Future<void> _retryTip() async {
    setState(() { _sending = true; _tipError = null; });
    final chargedTip = await _chargeStripeTip(_tipAmount);
    if (chargedTip != null) {
      try {
        await SupabaseService.submitRating(
          orderId: widget.orderId,
          stars: _stars,
          comment: _commentCtrl.text.trim(),
          tip: chargedTip,
          isDriver: widget.isDriver,
        );
      } catch (_) {
        // La propina sí se cobró (Stripe y order_tips ya la tienen) — que no
        // se haya podido reflejar en ratings.tip no es grave, solo se avisa.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tu propina sí se cobró, aunque no se pudo actualizar en tu calificación.'),
          ));
        }
      }
    }
    if (!mounted) return;
    setState(() { _sending = false; });
    if (chargedTip != null) Navigator.of(context).pop();
  }

  // Regresa el monto REAL que el servidor va a cobrar (puede diferir del
  // pedido si se reusó un intento anterior) si el pago se completa; null si
  // falla o el cliente lo cancela — en los dos casos deja _tipError puesto
  // para que el usuario sepa exactamente qué pasó.
  Future<double?> _chargeStripeTip(double amount) async {
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
      final chargedAmount = (res.data?['amount'] as num?)?.toDouble();
      if (clientSecret == null) {
        setState(() => _tipError = 'No se pudo iniciar el pago');
        return null;
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'GOGO Food — Propina',
          style: ThemeMode.light,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return chargedAmount ?? amount;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        // Antes esto regresaba false sin dejar ningún mensaje — el cliente
        // se quedaba viendo el diálogo sin entender qué había pasado.
        if (mounted) setState(() => _tipError = 'Cancelaste el pago de la propina.');
        return null;
      }
      if (mounted) setState(() => _tipError = 'Pago fallido: ${e.error.localizedMessage}');
      return null;
    } catch (_) {
      if (mounted) setState(() => _tipError = 'Error al procesar el pago');
      return null;
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

            if (_ratingSaved) ...[
              Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Tu calificación ya se guardó.',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
            ],

            // Botón enviar — una vez guardada la calificación, si sigue
            // pendiente la propina, este botón reintenta SOLO la propina en
            // vez de volver a mandar toda la calificación.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : (_ratingSaved ? _retryTip : _submit),
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
                        _ratingSaved
                            ? 'Reintentar propina'
                            : (_tipAmount > 0 ? 'Pagar propina y calificar' : 'Enviar calificación'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (_ratingSaved) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _sending ? null : () => Navigator.of(context).pop(),
                  child: Text('Cerrar sin propina',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
