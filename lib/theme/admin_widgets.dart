// Widgets reutilizables del nuevo diseño de Admin.
// Cada pantalla nueva (y las que se vayan restyleando por fases)
// deben construirse sobre estos en vez de repetir estilos sueltos.
import 'package:flutter/material.dart';
import 'admin_theme.dart';

/// Primeros 8 caracteres de un UUID, en mayúsculas — usado en varias
/// pantallas de Admin para mostrar repartidores/clientes sin nombre real
/// (ej. "Repartidor A1B2C3D4").
String adminShortId(String id) => id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

class AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 14),
        Text(value, style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 22)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: AdminColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

class AdminSectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AdminSectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: Text(title!,
                    style: const TextStyle(color: AdminColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              ?trailing,
            ]),
          ),
        child,
      ]),
    );
  }
}

/// Único mapeo estado→(label,color) para Admin. Cubre los 6 estados reales
/// de `orders.status` (pending/restaurant_accepted/accepted/delivering/
/// delivered/cancelled) — a diferencia de AppOrderStatus
/// (app_data_provider.dart) que solo tiene 4.
class AdminStatusBadge extends StatelessWidget {
  final String status;
  const AdminStatusBadge({super.key, required this.status});

  static (String, Color) styleFor(String status) => switch (status) {
        'pending' => ('Pendiente', AdminColors.statusPending),
        'restaurant_accepted' => ('Confirmado', const Color(0xFF00BFA5)),
        'accepted' => ('Preparando', AdminColors.statusAccepted),
        'delivering' => ('En camino', AdminColors.statusDelivering),
        'delivered' => ('Entregado', AdminColors.statusDelivered),
        'cancelled' => ('Cancelado', AdminColors.statusCancelled),
        _ => ('Desconocido', Colors.grey),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Envoltorio chico para un dropdown/selector suelto en una barra de
/// filtros (fondo de superficie + esquinas redondas de chip).
class AdminPill extends StatelessWidget {
  final Widget child;
  const AdminPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AdminColors.surface, borderRadius: BorderRadius.circular(AdminRadii.chip)),
        child: child,
      );
}

class AdminFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const AdminFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AdminColors.accent : AdminColors.surface,
          borderRadius: BorderRadius.circular(AdminRadii.chip),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : AdminColors.textSecondary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
      ),
    );
  }
}

class AdminPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const AdminPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadii.button)),
        ),
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
      ),
    );
  }
}
