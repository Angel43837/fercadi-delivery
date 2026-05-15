import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';

enum _Pay { cash, oxxo, card }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  _Pay _payment = _Pay.cash;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    final cart = context.read<CartProvider>();
    final orderData = <String, dynamic>{
      'restaurantName': cart.restaurantName ?? 'Tu restaurante',
      'address': _addressCtrl.text,
      'total': cart.total,
    };
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
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Confirmar pedido', style: TextStyle(color: Colors.white)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Resumen del pedido ───────────────────────────────────────────
            _SectionHeader(icon: Icons.receipt_long_outlined, label: 'Resumen del pedido'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ...cart.items.asMap().entries.map((e) {
                    final isLast = e.key == cart.items.length - 1;
                    return _OrderItemRow(item: e.value, isLast: isLast);
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total (${cart.count} producto${cart.count != 1 ? 's' : ''})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                        ),
                        Text(
                          '\$${cart.total.toStringAsFixed(0)} MXN',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryColor,
                            fontSize: 18,
                          ),
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
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _phoneCtrl,
              label: 'Teléfono de contacto',
              hint: 'Ej. 443 123 4567',
              icon: Icons.phone_outlined,
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
              label: 'Dirección de entrega',
              hint: 'Calle, número, colonia — Maravatío',
              icon: Icons.location_on_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa la dirección' : null,
            ),
            const SizedBox(height: 12),
            _FormField(
              controller: _refCtrl,
              label: 'Referencias (opcional)',
              hint: 'Ej. Casa azul, frente al parque',
              icon: Icons.info_outline,
            ),
            const SizedBox(height: 28),

            // ── Método de pago ───────────────────────────────────────────────
            _SectionHeader(icon: Icons.payments_outlined, label: '¿Cómo pagas?'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _PayOption(
                    value: _Pay.cash,
                    group: _payment,
                    label: 'Efectivo',
                    subtitle: 'Paga al repartidor cuando llegue',
                    iconWidget: const Icon(Icons.money, color: Colors.green, size: 28),
                    onChanged: (v) => setState(() => _payment = v!),
                  ),
                  _Divider(),
                  _PayOption(
                    value: _Pay.oxxo,
                    group: _payment,
                    label: 'OXXO Pay',
                    subtitle: 'Genera tu referencia y paga en OXXO',
                    iconWidget: _OxxoIcon(),
                    onChanged: (v) => setState(() => _payment = v!),
                  ),
                  _Divider(),
                  _PayOption(
                    value: _Pay.card,
                    group: _payment,
                    label: 'Tarjeta',
                    subtitle: 'Crédito o débito',
                    iconWidget: const Icon(Icons.credit_card, color: Color(0xFF2196F3), size: 28),
                    onChanged: (v) => setState(() => _payment = v!),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _ConfirmBar(total: cart.total, onConfirm: _confirm),
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
  const _OrderItemRow({required this.item, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(item.product.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
              Text(
                '${item.quantity}x  \$${item.total.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06), indent: 16, endIndent: 16),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
        prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
        filled: true,
        fillColor: AppConstants.surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConstants.primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
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

  const _PayOption({
    required this.value,
    required this.group,
    required this.label,
    required this.subtitle,
    required this.iconWidget,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return InkWell(
      borderRadius: BorderRadius.vertical(
        top: value == _Pay.cash ? const Radius.circular(16) : Radius.zero,
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: selected ? AppConstants.primaryColor : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppConstants.primaryColor : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.06), indent: 16, endIndent: 16);
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

class _ConfirmBar extends StatelessWidget {
  final double total;
  final VoidCallback onConfirm;
  const _ConfirmBar({required this.total, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total a pagar', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                Text('\$${total.toStringAsFixed(0)} MXN',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('CONFIRMAR PEDIDO', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
