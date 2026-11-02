// checkout_screen.dart
// Pantalla de confirmación del pedido.
// El cliente revisa su dirección de entrega, elige método de pago y confirma.
// Al confirmar:
//   1. Crea el pedido en Supabase con estado "pending"
//   2. Guarda el pedido en el historial local
//   3. Limpia el carrito
//   4. Redirige a la pantalla de tracking en tiempo real

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/guest_prompt.dart';
import '../../models/cart_item.dart';
import '../../models/restaurant.dart';
import '../../models/promotion_claim.dart';
import '../../providers/cart_provider.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../map_picker_screen.dart';
import '../../services/auth_service.dart';
import '../../services/order_history_service.dart';

enum _Pay { cash, card }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final _refCtrl = TextEditingController();
  _Pay _payment = _Pay.cash;
  bool _loading = false;
  bool _promoValidating = false;
  LatLng? _selectedPos;
  List<Map<String, dynamic>> _savedAddresses = [];
  final Map<String, Restaurant> _restaurants = {}; // restaurantId → Restaurant

  Restaurant? get _primaryRestaurant =>
      _restaurants.values.firstOrNull;

  // Una promoción solo se puede aplicar cuando el carrito es de un solo
  // restaurante — con varios a la vez no hay una forma clara de a cuál de
  // los pedidos resultantes aplicarle el descuento, así que se desactiva.
  String? get _singleRestaurantId {
    final byRestaurant = context.read<CartProvider>().itemsByRestaurant;
    return byRestaurant.length == 1 ? byRestaurant.keys.first : null;
  }

  // Envío de UN restaurante en concreto, con la misma fórmula de siempre
  // (tarifaBase + tarifaPorKm*distancia) — sin recargo todavía, eso se suma
  // aparte en _deliveryFeesByRestaurant solo para una de las 2 piernas de
  // un pedido de 2 restaurantes.
  double _soloDeliveryFee(Restaurant? r) {
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

  // Envío independiente de CADA restaurante del carrito (clave =
  // restaurantId). Con 2 restaurantes, el recargo fijo de pedido combinado
  // (LocationService.multiRestaurantSurcharge) se suma a UNA sola pierna —
  // siempre la primera en el orden de iteración de itemsByRestaurant, de
  // forma determinista — para que cada fila de "orders" quede completa y
  // correcta por sí sola sin depender de la otra (ver nota de la
  // migración 20261031000000_multi_restaurant_orders.sql).
  Map<String, double> get _deliveryFeesByRestaurant {
    final ids = context.read<CartProvider>().itemsByRestaurant.keys.toList();
    final fees = <String, double>{};
    for (final id in ids) {
      fees[id] = _soloDeliveryFee(_restaurants[id]);
    }
    if (ids.length == 2) {
      fees[ids.first] = fees[ids.first]! + LocationService.multiRestaurantSurcharge;
    }
    return fees;
  }

  double get _deliveryFee =>
      _deliveryFeesByRestaurant.values.fold(0.0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
    _loadRestaurants();
    _loadPreferredPayment();
  }

  // Antes el checkout siempre arrancaba en "efectivo" sin importar lo que
  // el usuario hubiera guardado como método preferido en su perfil — tenía
  // que volver a elegir tarjeta cada vez que pedía.
  Future<void> _loadPreferredPayment() async {
    final saved = await AuthService.getPreferredPayment();
    if (!mounted) return;
    setState(() => _payment = saved == 'card' ? _Pay.card : _Pay.cash);
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

  // ── Promoción ────────────────────────────────────────────────────────────

  Future<void> _pickPromotion() async {
    final rid = _singleRestaurantId;
    final nav = GoRouter.of(context);
    final claim = await nav.push<PromotionClaim>('/my-promotions', extra: {
      'selectionMode': true,
      if (rid != null) 'restaurantId': rid,
    });
    if (claim == null || !mounted) return;
    context.read<CartProvider>().selectPromo(claim);
    await _revalidatePromo();
  }

  // Le pide al servidor el descuento real para la promoción ya elegida — se
  // llama al elegirla y de nuevo cada vez que el carrito cambia (ver
  // CartProvider, que limpia _promoValidation en cada cambio). El número
  // que se muestra siempre es el que regresa esta llamada, nunca uno
  // calculado aquí.
  Future<void> _revalidatePromo() async {
    final cart = context.read<CartProvider>();
    final claim = cart.selectedPromoClaim;
    final rid = _singleRestaurantId;
    if (claim == null || rid == null) return;
    setState(() => _promoValidating = true);
    try {
      final items = cart.itemsByRestaurant[rid] ?? [];
      final result = await SupabaseService.validatePromotionForOrder(
        claimId: claim.id,
        restaurantId: rid,
        cartItems: items.map((i) => {
          'product_id': i.product.id,
          'category_id': i.product.categoryId,
          'quantity': i.quantity,
          'unit_price': i.product.price,
        }).toList(),
        subtotal: items.fold(0.0, (s, i) => s + i.total),
        deliveryFee: _deliveryFee,
      );
      if (!mounted) return;
      cart.setPromoValidation(result);
      if (result['valid'] != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mapPromoError(result['reason'] as String?)),
          backgroundColor: Colors.redAccent,
        ));
      }
    } catch (e) {
      if (mounted) {
        cart.setPromoValidation({'valid': false, 'reason': 'error'});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo validar la promoción. Intenta de nuevo.'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _promoValidating = false);
    }
  }

  String _mapPromoError(String? reason) {
    switch (reason) {
      case 'promocion_expirada': return 'Esta promoción ya venció.';
      case 'promocion_no_iniciada': return 'Esta promoción todavía no empieza.';
      case 'restaurante_no_coincide': return 'Esta promoción no aplica en este restaurante.';
      case 'fuera_de_horario': return 'Esta promoción no está disponible en este horario.';
      case 'dia_no_valido': return 'Esta promoción no aplica hoy.';
      case 'compra_minima_no_alcanzada': return 'Te falta para llegar a la compra mínima de esta promoción.';
      case 'productos_no_elegibles': return 'Ningún producto en tu carrito califica para esta promoción.';
      case 'usos_agotados': return 'Esta promoción ya se agotó.';
      case 'ya_utilizada': return 'Ya usaste esta promoción antes.';
      case 'requiere_producto_gratis_en_carrito': return 'Agrega el producto gratis de esta promoción a tu carrito para usarla.';
      default: return 'Esta promoción no se puede usar en este pedido.';
    }
  }

  void _removePromo() {
    context.read<CartProvider>().clearPromo();
    setState(() {});
  }

  double _orderTotalDisplay(CartProvider cart) =>
      cart.total + _deliveryFee - (cart.hasValidPromo ? cart.promoDiscount : 0);

  Widget _buildPromoSection(CartProvider cart, Color textMain, Color textSub, Color cardBg) {
    final canApply = _singleRestaurantId != null;
    final claim = cart.selectedPromoClaim;

    if (!canApply) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.local_offer_outlined, color: textSub, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Las promociones no aplican a pedidos de varios restaurantes a la vez.',
              style: TextStyle(color: textSub, fontSize: 12.5),
            ),
          ),
        ]),
      );
    }

    if (claim == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _pickPromotion,
          icon: const Icon(Icons.local_offer_outlined, color: AppConstants.primaryColor, size: 18),
          label: const Text('Gastar cupón', style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            backgroundColor: cardBg,
            side: const BorderSide(color: AppConstants.primaryColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
    }

    final valid = cart.hasValidPromo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: valid ? Colors.green : Colors.redAccent, width: 1),
      ),
      child: Row(children: [
        Icon(valid ? Icons.check_circle : Icons.error_outline, color: valid ? Colors.green : Colors.redAccent, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(claim.promotion?.title ?? 'Promoción',
                  style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (_promoValidating)
                Text('Validando…', style: TextStyle(color: textSub, fontSize: 12))
              else
                Text(
                  valid ? '-\$${cart.promoDiscount.toStringAsFixed(0)} MXN de descuento' : 'No se pudo aplicar',
                  style: TextStyle(color: valid ? Colors.green : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        if (_promoValidating)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryColor))
        else
          IconButton(
            onPressed: _removePromo,
            icon: Icon(Icons.close, color: textSub, size: 18),
            tooltip: 'Quitar promoción',
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
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
    // Respaldo por si se llega aquí sin pasar por el botón de cart_screen.dart
    // (que ya filtra esto antes) — mismo aviso reutilizable en toda la app.
    showLoginRequiredSheet(context,
        message: 'Para continuar con tu pedido necesitas iniciar sesión.',
        returnTo: '/checkout');
  }

  void _showPaymentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 5),
    ));
  }

  // Cobra con tarjeta pedidos YA creados: el monto lo pone el servidor (suma
  // de orders.total), nunca este celular. Obtiene el clientSecret y abre el
  // PaymentSheet de Stripe.
  // Cada etapa tiene su propio timeout: si Stripe se cuelga (bug conocido de
  // flutter_stripe en ciertas versiones de iOS, donde el PaymentSheet se
  // queda cargando para siempre sin lanzar error), esto evita que el botón
  // "Confirmar pedido" se quede pegado indefinidamente.
  // Regresa true si el pago se completó, false si falló o se canceló.
  Future<bool> _payWithStripe(List<String> orderIds) async {
    try {
      // 1. Pedir clientSecret al backend (Edge Function)
      debugPrint('[Stripe] Solicitando payment intent al backend...');
      final res = await SupabaseService.createCardPayment(orderIds)
          .timeout(const Duration(seconds: 20));
      final clientSecret = res['clientSecret'] as String?;
      if (clientSecret == null) {
        debugPrint('[Stripe] El backend no devolvió clientSecret: $res');
        final backendError = res['error'] as String?;
        _showPaymentError(backendError ?? 'No se pudo iniciar el pago. Intenta de nuevo.');
        return false;
      }
      debugPrint('[Stripe] Payment intent recibido, iniciando PaymentSheet...');

      // 2. Inicializar el PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'GOGO FOOD',
          returnURL: 'gogofood://stripe-return',
          style: ThemeMode.light,
        ),
      ).timeout(const Duration(seconds: 20));
      debugPrint('[Stripe] PaymentSheet inicializado, presentando...');

      // 3. Mostrar la hoja de pago. Sin timeout propio: un pago con 3DS puede
      // tardar legítimamente más de 90s (esperando al banco), y aunque esto
      // se quede esperando, confirmCardPayment/abandonCardPayment después
      // verifican con Stripe el resultado real — no se necesita un límite
      // artificial aquí encima del que ya tiene el SDK de Stripe.
      await Stripe.instance.presentPaymentSheet();
      debugPrint('[Stripe] Pago confirmado.');
      return true;
    } on TimeoutException {
      debugPrint('[Stripe] Timeout esperando respuesta de Stripe.');
      _showPaymentError('El pago está tardando demasiado. Revisa tu conexión e intenta de nuevo.');
      return false;
    } on StripeException catch (e) {
      debugPrint('[Stripe] StripeException: ${e.error.code} ${e.error.message}');
      _showPaymentError(e.error.localizedMessage ?? 'Pago cancelado');
      return false;
    } catch (e) {
      debugPrint('[Stripe] Error inesperado: $e');
      _showPaymentError('No se pudo procesar el pago. Revisa tu conexión e intenta de nuevo.');
      return false;
    }
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
    // Tope de 2 restaurantes por pedido — ya se bloquea en
    // restaurants_screen.dart al agregar el 3ro, esto es solo un candado
    // defensivo por si el carrito llegara aquí de otra forma (ej. "volver a
    // pedir" desde el historial).
    final byRestaurantCheck = context.read<CartProvider>().itemsByRestaurant;
    if (byRestaurantCheck.length > 2) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Un pedido solo puede tener hasta 2 restaurantes. Quita los de uno de ellos.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    setState(() => _loading = true);
    final cart = context.read<CartProvider>();
    final isCard = _payment == _Pay.card;
    // La promoción solo se manda si el servidor ya la validó (ver
    // _revalidatePromo) — place_order la vuelve a validar y calcula el
    // descuento real por su cuenta; nunca se usa uno calculado aquí.
    final promoClaim = cart.hasValidPromo ? cart.selectedPromoClaim : null;

    if (isCard && kIsWeb) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El pago con tarjeta solo está disponible en la app móvil. Descarga la app para pagar con tarjeta.'),
          backgroundColor: Color(0xFFBF360C),
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
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

    // 1. Crear los pedidos ANTES de cobrar — antes se cobraba primero y, si
    // el pedido fallaba, el cliente quedaba cobrado sin pedido. Un pedido
    // por restaurante, ligados por el mismo group_id cuando son 2 (para que
    // el repartidor los vea/reclame como un solo viaje, ver
    // claim_group_order). Precios, envío (con el recargo de pedido
    // combinado en la primera pierna) y descuento los calcula place_order()
    // en el servidor; aquí solo se manda qué se pidió y a dónde. Con tarjeta
    // los pedidos nacen 'awaiting_payment' y nadie los ve hasta confirmar el
    // pago.
    final groupId = byRestaurant.length == 2 ? SupabaseService.generateGroupId() : null;
    final orderIds = <String>[];
    double orderTotal = 0;
    String firstOrderId = 'local';
    String firstRestaurantName = byRestaurant.values.first.first.restaurantName;
    bool anyError = false;

    for (final entry in byRestaurant.entries) {
      final rItems = entry.value;
      try {
        final order = await SupabaseService.placeOrder(
          restaurantId: entry.key,
          groupId: groupId,
          customerName: _nameCtrl.text.trim(),
          // Ya no se pide de nuevo en el checkout — se usa el que la cuenta
          // ya tiene asociado (login por teléfono, o vinculado después desde
          // el perfil). Si la cuenta no tiene uno todavía (correo/Google sin
          // vincular), simplemente no hay — el repartidor tiene el chat en
          // vivo del pedido para contactar al cliente de todos modos.
          customerPhone: Supabase.instance.client.auth.currentUser?.phone ?? '',
          address: _addressCtrl.text.trim(),
          paymentMethod: _payment.name,
          lat: _selectedPos?.latitude,
          lng: _selectedPos?.longitude,
          // Solo se puede elegir una promoción con carrito de un solo
          // restaurante (ver _singleRestaurantId), así que siempre es este.
          promotionClaimId: promoClaim?.id,
          items: rItems.map((i) => {
            'product_id': i.product.id,
            'quantity': i.quantity,
            if (i.notes.isNotEmpty) 'notes': i.notes,
          }).toList(),
        );
        final oid = order['id'] as String;
        orderIds.add(oid);
        orderTotal += (order['total'] as num).toDouble();
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
        // Con tarjeta es todo o nada: un solo cobro cubre los 2 pedidos.
        if (isCard) break;
      }
    }

    if (anyError) {
      // Todo o nada: si una pierna se creó pero la otra falló, se cancela la
      // que sí se creó en vez de dejarla huérfana (antes esto solo pasaba
      // con tarjeta; en efectivo las piernas nacen 'pending' directo, así
      // que necesitan la misma limpieza).
      if (orderIds.isNotEmpty) {
        if (isCard) {
          await SupabaseService.abandonCardPayment(orderIds);
        } else {
          for (final oid in orderIds) {
            try {
              await SupabaseService.rejectOrder(oid, reason: 'Falló al crear el pedido combinado');
            } catch (_) {}
          }
        }
      }
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 2. Tarjeta: se cobra exactamente lo que guardó el servidor (la suma de
    // los pedidos del grupo, en un solo cobro).
    var paymentAwaitingVerification = false;
    if (isCard) {
      final paid = await _payWithStripe(orderIds);
      if (!paid) {
        // abandonCardPayment cancela el cobro y los pedidos — salvo que
        // Stripe sí alcanzó a cobrar justo cuando la app decidió que había
        // fallado (ej. el sheet se cerró tarde): ahí el servidor regresa
        // paid:true en vez de cancelar, y entonces sí se trata como pago
        // exitoso en vez de perder el pedido.
        final reallyPaid = await SupabaseService.abandonCardPayment(orderIds);
        if (!reallyPaid) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      } else {
        // Confirma con el servidor que el cobro se completó, con reintentos
        // y espera creciente — el webhook puede tardar, o la red del celular
        // puede fallar justo aquí. Si tras los reintentos sigue sin
        // confirmarse, NO se muestra éxito: el pedido se queda
        // 'awaiting_payment' (el webhook o el job de limpieza lo resuelven
        // después) y el cliente lo sigue desde tracking_screen.
        var confirmed = false;
        const waits = [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)];
        for (var attempt = 0; !confirmed && attempt <= waits.length; attempt++) {
          if (attempt > 0) await Future.delayed(waits[attempt - 1]);
          confirmed = await SupabaseService.confirmCardPayment(orderIds);
        }
        paymentAwaitingVerification = !confirmed;
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
    // Con el tope de 2 restaurantes, "Varios restaurantes" ya no hace
    // falta como genérico — se muestran los 2 nombres de verdad, igual que
    // en el resumen combinado de tracking_screen.dart.
    final restaurantNames = byRestaurant.keys
        .map((rid) => _restaurants[rid]?.name ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final restaurantLabel = byRestaurant.length > 1 && restaurantNames.length > 1
        ? restaurantNames.join(' + ')
        : firstRestaurantName;
    // Un logo por restaurante del pedido — con un solo restaurante es una
    // lista de un elemento (el widget nativo espera siempre una lista, así
    // no necesita dos caminos distintos para "uno" vs "varios").
    final restaurantsList = byRestaurant.keys.map((rid) {
      final r = _restaurants[rid];
      return {'name': r?.name ?? '', 'imageUrl': r?.imageUrl ?? ''};
    }).toList();
    final orderData = <String, dynamic>{
      'restaurantName': restaurantLabel,
      'address': _addressCtrl.text.trim(),
      'total': orderTotal,
      'orderId': firstOrderId,
      'orderIds': orderIds,
      'restaurants': restaurantsList,
      if (_selectedPos != null) 'lat': _selectedPos!.latitude,
      if (_selectedPos != null) 'lng': _selectedPos!.longitude,
      // Solo con un restaurante hay un logo/posición clara que mostrar — con
      // "Varios restaurantes" no hay uno solo que tenga sentido elegir.
      if (byRestaurant.length == 1 && _primaryRestaurant?.imageUrl != null)
        'restaurantImageUrl': _primaryRestaurant!.imageUrl,
      if (byRestaurant.length == 1 && _primaryRestaurant?.lat != null)
        'restaurantLat': _primaryRestaurant!.lat,
      if (byRestaurant.length == 1 && _primaryRestaurant?.lng != null)
        'restaurantLng': _primaryRestaurant!.lng,
    };
    // Resumen tipo "2x Tacos, 1x Refresco" — se guarda ya armado para no
    // tener que volver a pedirle los productos a Supabase solo para mostrar
    // la tarjeta en "Mis pedidos".
    final itemsSummary = byRestaurant.values
        .expand((items) => items)
        .map((i) => '${i.quantity}x ${i.product.name}')
        .join(', ');
    await OrderHistoryService.add(
      orderId: firstOrderId,
      restaurantName: restaurantLabel,
      total: orderTotal,
      address: _addressCtrl.text.trim(),
      restaurantImageUrl: byRestaurant.length == 1 ? _primaryRestaurant?.imageUrl : null,
      itemsSummary: itemsSummary,
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
      restaurantLat: byRestaurant.length == 1 ? _primaryRestaurant?.lat : null,
      restaurantLng: byRestaurant.length == 1 ? _primaryRestaurant?.lng : null,
      restaurantImageUrl: byRestaurant.length == 1 ? _primaryRestaurant?.imageUrl : null,
    );
    cart.clear();
    if (paymentAwaitingVerification) {
      // No se muestra la pantalla de éxito todavía: el pago sigue sin
      // confirmarse del lado del servidor. El cliente ya puede ver y seguir
      // su pedido en tracking_screen (que ahora sabe mostrar el estado
      // 'awaiting_payment'); si el pago en realidad sí se completó, el
      // webhook/job lo confirma solo y el pedido avanza sin que el cliente
      // tenga que hacer nada más.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tu pago se está verificando. Te avisamos en cuanto se confirme.'),
        backgroundColor: Color(0xFFBF360C),
        duration: Duration(seconds: 5),
      ));
      context.go('/tracking', extra: orderData);
      return;
    }
    _showSuccess(orderData);
  }

  void _showSuccess(Map<String, dynamic> orderData) {
    final nav = context;
    showDialog(
      context: nav,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          width: 312,
          height: 392,
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          decoration: BoxDecoration(
            color: AppConstants.primaryColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(color: Color(0xFF0CB6F4), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppConstants.primaryColor, size: 40),
              ),
              const SizedBox(height: 10),
              Center(
                child: SvgPicture.asset(
                  'assets/images/pedido_confirmado_title.svg',
                  width: 196,
                  height: 100,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Rastrea Tu Pedido en Tiempo Real',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  color: Color(0xFF0CB6F4),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 277,
                height: 55,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x6E000000), offset: Offset(0, 1), blurRadius: 3.8, spreadRadius: 1),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    nav.go('/tracking', extra: orderData);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0CB6F4),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text(
                    'RASTREAR PEDIDO',
                    style: TextStyle(fontFamily: 'Baloo2', fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 277,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x6E000000), offset: Offset(0, 1), blurRadius: 3.8, spreadRadius: 1),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    nav.go('/restaurants');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppConstants.primaryColor,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text(
                    'INICIO',
                    style: TextStyle(fontFamily: 'Baloo2', fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Image.asset('assets/images/gogofood_wordmark.png', width: 93, height: 11),
            ],
          ),
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
            // Aviso honesto: con 2 restaurantes el pedido tarda más (hay que
            // pasar por los 2 locales) y el envío es mayor (cada pierna
            // cobra su propia tarifa, más un recargo fijo) — el dueño pidió
            // que esto se le avisara claro al cliente antes de pagar.
            if (cart.itemsByRestaurant.length > 1) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: isDark ? 0.15 : 1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppConstants.primaryColor.withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: isDark ? AppConstants.primaryColor : Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pedido de 2 restaurantes — tardará un poco más y el envío es mayor.',
                      style: TextStyle(
                        color: isDark ? AppConstants.primaryColor : Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
            ],
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
                        if (cart.hasValidPromo) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Descuento', style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(
                                '-\$${cart.promoDiscount.toStringAsFixed(0)} MXN',
                                style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
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
                              '\$${_orderTotalDisplay(cart).toStringAsFixed(0)} MXN',
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
            const SizedBox(height: 20),

            // ── Promoción ────────────────────────────────────────────────────
            _buildPromoSection(cart, textMain, textSub, cardBg),
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
            const SizedBox(height: 10),
            // Antes había hasta 3 botones apilados aquí (Ubicaciones
            // guardadas, GPS guardado · Cambiar pin / Detectar mi ubicación)
            // — se simplifica a UN botón principal ("Usar mi ubicación
            // actual") y las otras dos opciones (ajustar pin en el mapa,
            // ver ubicaciones guardadas) quedan como acciones chiquitas y
            // compactas debajo, sin perder ninguna función.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.55),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _locateAndPick,
                  icon: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location, size: 20),
                  label: const Text('Usar mi ubicación actual',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blue.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                  ),
                ),
              ),
            ),
            if (_selectedPos != null || _savedAddresses.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                if (_selectedPos != null)
                  TextButton.icon(
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
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 15),
                    label: const Text('Ajustar pin', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (_selectedPos != null && _savedAddresses.isNotEmpty)
                  Text('·', style: TextStyle(color: textSub, fontSize: 12)),
                if (_savedAddresses.isNotEmpty)
                  TextButton.icon(
                    onPressed: _showSavedAddressesSheet,
                    icon: const Icon(Icons.bookmark_outline, size: 15),
                    label: const Text('Ubicaciones guardadas', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ]),
            ],
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
      bottomNavigationBar: _ConfirmBar(total: _orderTotalDisplay(cart), onConfirm: _confirm, loading: _loading, isDark: isDark),
    );
  }

  void _showSavedAddressesSheet() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppConstants.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ubicación usada recientemente',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _buildAddressChip(_savedAddresses.first),
              if (_savedAddresses.length > 1) ...[
                const SizedBox(height: 18),
                const Text('Ubicaciones',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final a in _savedAddresses.sublist(1)) ...[
                  _buildAddressChip(a),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressChip(Map<String, dynamic> a) {
    final label = a['label'] as String? ?? 'Dirección';
    final addr  = a['address'] as String? ?? '';
    // Siempre se muestra la dirección real, nunca la etiqueta genérica
    // ("Mi ubicación", "Reciente", etc.) — con varias guardadas, el nombre
    // genérico no ayuda a distinguir cuál es cuál.
    final displayLabel = addr.length > 34 ? '${addr.substring(0, 34)}…' : addr;
    final isSelected = _addressCtrl.text == addr;
    final bg = isSelected ? Colors.white : Colors.blue;
    final fg = isSelected ? Colors.blue : Colors.white;
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
        Navigator.of(context).pop();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: isSelected ? Border.all(color: Colors.blue, width: 1.5) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Icon(
            label == 'Casa' ? Icons.home_outlined
                : label == 'Trabajo' ? Icons.work_outline
                : Icons.location_on_outlined,
            size: 18, color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(displayLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg, fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                )),
          ),
          const SizedBox(width: 8),
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
              if (mounted) Navigator.of(context).pop();
            },
            child: Icon(Icons.close, size: 16, color: fg),
          ),
        ]),
      ),
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
    final labelColor = isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade300;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pastilla con el nombre del campo — redonda por completo, separada
        // de la caja (a petición del dueño), en vez de la pestaña cuadrada.
        Container(
          margin: const EdgeInsets.only(left: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(color: labelColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(color: textMain),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5)),
            errorStyle: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
          ),
        ),
      ],
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
