// checkout_screen.dart
// Pantalla de confirmación del pedido.
// El cliente revisa su dirección de entrega, elige método de pago y confirma.
// Al confirmar:
//   1. Crea el pedido en Supabase con estado "pending"
//   2. Guarda el pedido en el historial local
//   3. Limpia el carrito
//   4. Redirige a la pantalla de tracking en tiempo real

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../models/cart_item.dart';
import '../models/restaurant.dart';
import '../providers/cart_provider.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'map_picker_screen.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/order_history_service.dart';

enum _Pay { cash, oxxo, card }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final _refCtrl = TextEditingController();
  _Pay _payment = _Pay.cash;
  bool _loading = false;
  LatLng? _selectedPos;
  List<Map<String, dynamic>> _savedAddresses = [];
  final Map<String, Restaurant> _restaurants = {}; // restaurantId → Restaurant

  Restaurant? get _primaryRestaurant =>
      _restaurants.values.firstOrNull;

  double get _deliveryFee {
    final r = _primaryRestaurant;
    if (r?.lat == null || r?.lng == null || _selectedPos == null) {
      return LocationService.calcularCostoEnvio(null);
    }
    final distanciaKm = Geolocator.distanceBetween(
          r!.lat!,
          r.lng!,
          _selectedPos!.latitude,
          _selectedPos!.longitude,
        ) /
        1000;
    return LocationService.calcularCostoEnvio(distanciaKm);
  }

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    final ids = context.read<CartProvider>().itemsByRestaurant.keys.toList();
    for (final id in ids) {
      final restaurant = await SupabaseService.getRestaurantById(id);
      if (!mounted) return;
      if (restaurant != null) {
        setState(() => _restaurants[id] = restaurant);
      }
    }
  }

  Future<void> _loadSavedAddresses() async {
    final addresses = await AuthService.getSavedAddresses();
    if (!mounted) return;
    setState(() => _savedAddresses = addresses);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  // Detecta GPS y luego abre el mapa con el pin en la posición detectada (móvil)
  // En web solo guarda las coordenadas GPS
  Future<void> _locateAndPick() async {
    // Capturar antes de cualquier await para evitar uso cross-async de context
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Permite el acceso a tu ubicación'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final gpsLatLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _loading = false);
      final result = await nav.push<LatLng>(
        MaterialPageRoute(builder: (_) => MapPickerScreen(initial: gpsLatLng)),
      );
      if (result != null && mounted) {
        setState(() => _selectedPos = result);
        final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
        if (addr != null && mounted) {
          setState(() => _addressCtrl.text = addr);
          _addressCtrl.selection = TextSelection(baseOffset: 0, extentOffset: addr.length);
          _addressFocus.requestFocus();
        }
      }
      return;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo detectar la ubicación: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showLoginRequired() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: AppConstants.primaryColor, size: 36),
          ),
          const SizedBox(height: 20),
          const Text('¿Aún no tienes cuenta?',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('Crea una cuenta gratis para hacer pedidos y rastrear tu entrega.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); context.go('/login'); },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Crear cuenta / Iniciar sesión',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  // Llama a la Supabase Edge Function, obtiene el clientSecret y abre el PaymentSheet de Stripe
  Future<bool> _payWithStripe(double total) async {
    try {
      // 1. Pedir clientSecret al backend (Edge Function)
      final res = await Supabase.instance.client.functions.invoke(
        'create-payment-intent',
        body: {'amount': total, 'currency': 'mxn'},
      );
      final clientSecret = res.data['clientSecret'] as String?;
      if (clientSecret == null) throw Exception('No se obtuvo clientSecret');

      // 2. Inicializar el PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'GOGO FOOD',
          returnURL: 'gogofood://stripe-return',
          style: ThemeMode.light,
        ),
      );

      // 3. Mostrar la hoja de pago
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.error.localizedMessage ?? 'Pago cancelado'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return false;
    }
  }

  // Crea el PaymentIntent de OXXO, lo confirma con Stripe y muestra la ficha
  // de pago al cliente. Devuelve el id del PaymentIntent (para guardarlo en
  // el pedido y que el webhook lo marque como pagado cuando se pague en
  // tienda), o null si se canceló/falló.
  Future<String?> _payWithOxxo(double total) async {
    // OXXO exige nombre y apellido (mínimo 2 letras cada uno) para generar
    // la ficha — si falta, Stripe lo rechaza con un mensaje genérico poco
    // claro. Se valida antes de llamar a Stripe para dar un mensaje útil.
    final nameParts = _nameCtrl.text.trim().split(RegExp(r'\s+'));
    final hasFullName = nameParts.length >= 2 && nameParts.every((p) => p.length >= 2);
    if (!hasFullName) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Para pagar con OXXO escribe tu nombre completo (nombre y apellido) en "Nombre del destinatario".'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 4),
        ));
      }
      return null;
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'create-payment-intent',
        body: {'amount': total, 'currency': 'mxn', 'paymentMethodType': 'oxxo'},
      );
      final clientSecret = res.data['clientSecret'] as String?;
      final intentId = res.data['id'] as String?;
      if (clientSecret == null || intentId == null) {
        throw Exception('No se pudo generar el pago de OXXO');
      }

      final email = Supabase.instance.client.auth.currentUser?.email;
      PaymentIntent intent;
      try {
        intent = await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: clientSecret,
          data: PaymentMethodParams.oxxo(
            paymentMethodData: PaymentMethodData(
              billingDetails: BillingDetails(
                name: _nameCtrl.text.trim(),
                email: email,
              ),
            ),
          ),
        );
      } on StripeException catch (e) {
        // Bug conocido del plugin de Stripe en iOS con apps que usan el
        // ciclo de vida "Scene" (SceneDelegate): el confirm SÍ se procesa
        // bien en el servidor de Stripe, pero el SDK falla al intentar
        // mostrar la UI de siguiente acción localmente. Como el pago ya
        // se confirmó del lado de Stripe, se recupera el estado actual del
        // PaymentIntent (sin volver a confirmar) para seguir el flujo normal.
        if (e.error.message?.contains('window hierarchy') == true) {
          intent = await Stripe.instance.retrievePaymentIntent(clientSecret);
        } else {
          rethrow;
        }
      }

      final voucher = intent.nextAction?.maybeWhen(
        displayOxxoDetails: (expiration, voucherURL, voucherNumber) =>
            (url: voucherURL, number: voucherNumber, expiration: expiration),
        orElse: () => null,
      );

      if (voucher == null || voucher.url == null) {
        throw Exception('No se generó la ficha de pago de OXXO');
      }

      if (!mounted) return null;
      final continued = await _showOxxoVoucher(voucher.url!, voucher.number, voucher.expiration);
      return continued ? intentId : null;
    } on StripeException catch (e) {
      // ignore: avoid_print
      print('OXXO StripeException: code=${e.error.code} message=${e.error.message} '
          'localizedMessage=${e.error.localizedMessage} declineCode=${e.error.declineCode}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.error.localizedMessage ?? e.error.message ?? 'No se pudo generar el pago OXXO'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return null;
    }
  }

  // Muestra la ficha de pago OXXO (referencia + link) y espera a que el
  // cliente confirme que la vio antes de crear el pedido.
  Future<bool> _showOxxoVoucher(String url, String? number, int? expirationEpoch) async {
    final expiry = expirationEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(expirationEpoch * 1000).toLocal()
        : null;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ficha de pago OXXO', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (number != null) ...[
              Text('Referencia: $number', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
            ],
            if (expiry != null) ...[
              Text('Vence: ${expiry.day}/${expiry.month}/${expiry.year}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
            ],
            const Text(
              'Paga en cualquier tienda OXXO con esta ficha. Tu pedido se confirmará '
              'automáticamente en cuanto se registre el pago.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: const Text('Abrir ficha'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirm() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showLoginRequired();
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      return;
    }
    setState(() => _loading = true);
    final cart = context.read<CartProvider>();
    final deliveryFee = _deliveryFee;
    final orderTotal = cart.total + deliveryFee;

    // Si el pago es con tarjeta u OXXO, procesar Stripe primero
    String? oxxoPaymentIntentId;
    if (_payment == _Pay.card || _payment == _Pay.oxxo) {
      if (kIsWeb) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_payment == _Pay.card
                ? 'El pago con tarjeta solo está disponible en la app móvil. Descarga la app para pagar con tarjeta.'
                : 'El pago con OXXO solo está disponible en la app móvil. Descarga la app para pagar en OXXO.'),
            backgroundColor: const Color(0xFFBF360C),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      if (_payment == _Pay.card) {
        final paid = await _payWithStripe(orderTotal);
        if (!paid) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      } else {
        oxxoPaymentIntentId = await _payWithOxxo(orderTotal);
        if (oxxoPaymentIntentId == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      }
    }

    final byRestaurant = cart.itemsByRestaurant;
    if (byRestaurant.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error: carrito vacío. Vuelve e intenta de nuevo.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    // Create one order per restaurant; share the same delivery fee split equally
    final perOrderFee = deliveryFee / byRestaurant.length;
    String firstOrderId = 'local';
    String firstRestaurantName = byRestaurant.values.first.first.restaurantName;
    bool anyError = false;

    for (final entry in byRestaurant.entries) {
      final rid = entry.key;
      final rItems = entry.value;
      final rSubtotal = rItems.fold(0.0, (s, i) => s + i.total);
      try {
        final oid = await SupabaseService.createOrder(
          restaurantId: rid,
          total: rSubtotal + perOrderFee,
          deliveryFee: perOrderFee,
          customerName: _nameCtrl.text.trim(),
          customerPhone: _phoneCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          paymentMethod: _payment.name,
          lat: _selectedPos?.latitude,
          lng: _selectedPos?.longitude,
          clientFcmToken: FcmService.token,
          paymentStatus: _payment == _Pay.oxxo
              ? 'pending'
              : (_payment == _Pay.card ? 'paid' : null),
          stripePaymentIntentId: _payment == _Pay.oxxo ? oxxoPaymentIntentId : null,
          items: rItems.map((i) => {
            'product_id': i.product.id,
            'quantity': i.quantity,
            'price': i.product.price,
            if (i.notes.isNotEmpty) 'notes': i.notes,
          }).toList(),
        );
        if (firstOrderId == 'local') {
          firstOrderId = oid;
          firstRestaurantName = rItems.first.restaurantName;
        }
      } catch (e) {
        anyError = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error en pedido de ${rItems.first.restaurantName}: $e'),
            backgroundColor: Colors.redAccent,
          ));
        }
      }
    }

    if (anyError && firstOrderId == 'local') {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    final restaurantLabel = byRestaurant.length > 1
        ? 'Varios restaurantes'
        : firstRestaurantName;
    final orderData = <String, dynamic>{
      'restaurantName': restaurantLabel,
      'address': _addressCtrl.text.trim(),
      'total': orderTotal,
      'orderId': firstOrderId,
      if (_selectedPos != null) 'lat': _selectedPos!.latitude,
      if (_selectedPos != null) 'lng': _selectedPos!.longitude,
    };
    await OrderHistoryService.add(
      orderId: firstOrderId,
      restaurantName: restaurantLabel,
      total: orderTotal,
      address: _addressCtrl.text.trim(),
    );
    await AuthService.saveAddress(
      label: 'Reciente',
      address: _addressCtrl.text.trim(),
      lat: _selectedPos?.latitude,
      lng: _selectedPos?.longitude,
    );
    await OrderHistoryService.saveActiveOrder(
      orderId: firstOrderId,
      restaurantName: restaurantLabel,
      total: orderTotal,
      address: _addressCtrl.text.trim(),
      lat: _selectedPos?.latitude,
      lng: _selectedPos?.longitude,
    );
    cart.clear();
    _showSuccess(orderData);
  }

  void _showSuccess(Map<String, dynamic> orderData) {
    final nav = context;
    showDialog(
      context: nav,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 54),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Pedido confirmado!',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Tu pedido está siendo preparado.\nTiempo estimado: 30 – 45 min.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  nav.go('/tracking', extra: orderData);
                },
                icon: const Icon(Icons.map_outlined, size: 20),
                label: const Text('Rastrear mi pedido', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                nav.go('/restaurants');
              },
              child: Text('Volver al inicio',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart  = context.watch<CartProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppConstants.bgColor : AppConstants.primaryColor;
    final cardBg     = isDark ? AppConstants.surfaceColor : Colors.white;
    final textMain   = isDark ? Colors.white : Colors.black87;
    final textSub    = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54;
    final divColor   = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black12;
    final chipUnsel  = isDark ? AppConstants.surfaceColor : Colors.white.withValues(alpha: 0.3);
    final chipBorder = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Confirmar pedido'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            // ── Resumen del pedido ───────────────────────────────────────────
            _SectionHeader(icon: Icons.receipt_long_outlined, label: 'Resumen del pedido'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ...cart.items.asMap().entries.map((e) {
                    final isLast = e.key == cart.items.length - 1;
                    return _OrderItemRow(item: e.value, isLast: isLast, textMain: textMain, textSub: textSub, divColor: divColor);
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal (${cart.count} producto${cart.count != 1 ? 's' : ''})',
                              style: TextStyle(color: textSub, fontSize: 14),
                            ),
                            Text(
                              '\$${cart.total.toStringAsFixed(0)} MXN',
                              style: TextStyle(color: textMain, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Envío', style: TextStyle(color: textSub, fontSize: 14)),
                            Text(
                              '\$${_deliveryFee.toStringAsFixed(0)} MXN',
                              style: TextStyle(color: textMain, fontSize: 14),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: divColor, height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total',
                                style: TextStyle(fontWeight: FontWeight.bold, color: textMain, fontSize: 15)),
                            Text(
                              '\$${(cart.total + _deliveryFee).toStringAsFixed(0)} MXN',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppConstants.primaryColor, fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Datos de entrega ─────────────────────────────────────────────
            _SectionHeader(icon: Icons.local_shipping_outlined, label: '¿A dónde te lo llevamos?'),
            const SizedBox(height: 12),
            _FormField(
              controller: _nameCtrl,
              label: 'Nombre del destinatario',
              hint: 'Ej. Juan Pérez',
              icon: Icons.person_outline,
              isDark: isDark,
              cardBg: cardBg,
              textMain: textMain,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _phoneCtrl,
              label: 'Teléfono de contacto',
              hint: 'Ej. 443 123 4567',
              icon: Icons.phone_outlined,
              isDark: isDark,
              cardBg: cardBg,
              textMain: textMain,
              keyboardType: TextInputType.phone,
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) return 'Ingresa el teléfono';
                if (digits.length < 10) return 'Mínimo 10 dígitos';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _addressCtrl,
              focusNode: _addressFocus,
              label: 'Dirección de entrega',
              hint: 'Calle, número, colonia — Maravatío',
              icon: Icons.location_on_outlined,
              isDark: isDark,
              cardBg: cardBg,
              textMain: textMain,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa la dirección' : null,
            ),
            if (_savedAddresses.isNotEmpty) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _savedAddresses.map((a) {
                    final label = a['label'] as String? ?? 'Dirección';
                    final addr  = a['address'] as String? ?? '';
                    final isSelected = _addressCtrl.text == addr;
                    final chipColor = isSelected ? AppConstants.primaryColor : chipBorder;
                    final labelColor = isSelected
                        ? AppConstants.primaryColor
                        : Colors.white.withValues(alpha: 0.85);
                    return GestureDetector(
                      onTap: () {
                        final lat = a['lat'];
                        final lng = a['lng'];
                        setState(() {
                          _addressCtrl.text = addr;
                          _selectedPos = (lat != null && lng != null)
                              ? LatLng((lat as num).toDouble(), (lng as num).toDouble())
                              : null;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppConstants.primaryColor.withValues(alpha: 0.15) : chipUnsel,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: chipColor),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            label == 'Casa' ? Icons.home_outlined
                                : label == 'Trabajo' ? Icons.work_outline
                                : Icons.location_on_outlined,
                            size: 14, color: labelColor,
                          ),
                          const SizedBox(width: 4),
                          Text(label, style: TextStyle(
                            color: labelColor, fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          )),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () async {
                              await AuthService.removeAddress(addr);
                              if (!mounted) return;
                              setState(() {
                                _savedAddresses.removeWhere((x) => x['address'] == addr);
                                if (_addressCtrl.text == addr) {
                                  _addressCtrl.clear();
                                  _selectedPos = null;
                                }
                              });
                            },
                            child: Icon(Icons.close, size: 14, color: labelColor),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _selectedPos != null
                  ? OutlinedButton.icon(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final result = await nav.push<LatLng>(
                          MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _selectedPos)),
                        );
                        if (result != null && mounted) {
                          setState(() => _selectedPos = result);
                          final addr = await LocationService.reverseGeocode(result.latitude, result.longitude);
                          if (addr != null && mounted) {
                            setState(() => _addressCtrl.text = addr);
                            _addressCtrl.selection = TextSelection(baseOffset: 0, extentOffset: addr.length);
                            _addressFocus.requestFocus();
                          }
                        }
                      },
                      icon: const Icon(Icons.my_location, size: 16, color: Colors.green),
                      label: const Text('GPS guardado · Cambiar pin',
                          style: TextStyle(color: Colors.green, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.primaryColor.withValues(alpha: 0.55),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _locateAndPick,
                        icon: _loading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.pin_drop_rounded, size: 20),
                        label: const Text('Detectar mi ubicación',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppConstants.primaryColor.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _refCtrl,
              label: 'Referencias (opcional)',
              hint: 'Ej. Casa azul, frente al parque',
              icon: Icons.info_outline,
              isDark: isDark,
              cardBg: cardBg,
              textMain: textMain,
            ),
            const SizedBox(height: 28),

            // ── Método de pago ───────────────────────────────────────────────
            _SectionHeader(icon: Icons.payments_outlined, label: '¿Cómo pagas?'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                _PayOption(
                  value: _Pay.cash, group: _payment,
                  label: 'Efectivo', subtitle: 'Paga al repartidor cuando llegue',
                  iconWidget: const Icon(Icons.money, color: Colors.green, size: 28),
                  onChanged: (v) => setState(() => _payment = v!),
                  textMain: textMain, textSub: textSub, divColor: divColor,
                ),
                _PayOption(
                  value: _Pay.oxxo, group: _payment,
                  label: 'OXXO Pay', subtitle: 'Genera tu referencia y paga en OXXO',
                  iconWidget: _OxxoIcon(),
                  onChanged: (v) => setState(() => _payment = v!),
                  textMain: textMain, textSub: textSub, divColor: divColor,
                ),
                _PayOption(
                  value: _Pay.card, group: _payment,
                  label: 'Tarjeta', subtitle: 'Crédito o débito — procesado por Stripe',
                  iconWidget: const _StripeIcon(),
                  onChanged: (v) => setState(() => _payment = v!),
                  isLast: true,
                  textMain: textMain, textSub: textSub, divColor: divColor,
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline, size: 13, color: textSub),
              const SizedBox(width: 4),
              Text('Pagos seguros con', style: TextStyle(color: textSub, fontSize: 11)),
              const SizedBox(width: 5),
              const _StripeWordmark(),
            ]),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _ConfirmBar(total: cart.total + _deliveryFee, onConfirm: _confirm, loading: _loading, isDark: isDark),
    );
  }
}

// ── Widgets privados ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppConstants.primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final CartItem item;
  final bool isLast;
  final Color textMain;
  final Color textSub;
  final Color divColor;
  const _OrderItemRow({required this.item, this.isLast = false, required this.textMain, required this.textSub, required this.divColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.product.name, style: TextStyle(color: textMain, fontSize: 14)),
                  ),
                  Text(
                    '${item.quantity}x  \$${item.total.toStringAsFixed(0)}',
                    style: TextStyle(color: textSub, fontSize: 14),
                  ),
                ],
              ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.notes, size: 12, color: textSub),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(item.notes,
                        style: TextStyle(color: textSub, fontSize: 11, fontStyle: FontStyle.italic)),
                  ),
                ]),
              ],
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: divColor, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool isDark;
  final Color cardBg;
  final Color textMain;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDark,
    required this.cardBg,
    required this.textMain,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black38;
    final labelColor = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: textMain),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: labelColor),
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
        errorStyle: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
      ),
    );
  }
}

class _PayOption extends StatelessWidget {
  final _Pay value;
  final _Pay group;
  final String label;
  final String subtitle;
  final Widget iconWidget;
  final ValueChanged<_Pay?> onChanged;
  final bool isLast;
  final Color textMain;
  final Color textSub;
  final Color divColor;

  const _PayOption({
    required this.value,
    required this.group,
    required this.label,
    required this.subtitle,
    required this.iconWidget,
    required this.onChanged,
    required this.textMain,
    required this.textSub,
    required this.divColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return Column(children: [
      InkWell(
        borderRadius: BorderRadius.vertical(
          top: value == _Pay.cash ? const Radius.circular(16) : Radius.zero,
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        onTap: () => onChanged(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            iconWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(
                    color: selected ? AppConstants.primaryColor : textMain,
                    fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: textSub, fontSize: 12)),
              ]),
            ),
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppConstants.primaryColor : textSub,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(child: Container(width: 11, height: 11,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppConstants.primaryColor)))
                  : null,
            ),
          ]),
        ),
      ),
      if (!isLast) Divider(height: 1, color: divColor, indent: 16, endIndent: 16),
    ]);
  }
}

class _OxxoIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: const Text(
        'OXXO',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5),
      ),
    );
  }
}

class _StripeIcon extends StatelessWidget {
  const _StripeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF635BFF),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: const Text(
        'S',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
          fontStyle: FontStyle.italic,
          height: 1,
        ),
      ),
    );
  }
}

class _StripeWordmark extends StatelessWidget {
  const _StripeWordmark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF635BFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'stripe',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final double total;
  final VoidCallback onConfirm;
  final bool loading;
  final bool isDark;
  const _ConfirmBar({required this.total, required this.onConfirm, this.loading = false, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppConstants.surfaceColor : AppConstants.primaryColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      color: bg,
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total a pagar', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
            Text('\$${total.toStringAsFixed(0)} MXN',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.white,
                foregroundColor: AppConstants.primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: loading
                  ? const SizedBox(height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppConstants.primaryColor))
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle_outline, size: 20),
                      SizedBox(width: 8),
                      Text('CONFIRMAR PEDIDO', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}
