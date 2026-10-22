// Stripe expone lo que falta en un registro de Connect como códigos
// técnicos en inglés (ej. "defaults.profile.business_url") — nada de eso
// le dice algo a un rider o dueño sin conocimiento técnico. Esto los
// traduce a mensajes claros; el JSON crudo de Stripe se sigue guardando en
// connectDebugInfo para cuando SÍ hace falta diagnosticar algo raro.
List<String> friendlyStripeRequirements(Map<String, dynamic>? debugInfo) {
  final requirements = debugInfo?['requirements'];
  final entries = (requirements is Map) ? requirements['entries'] : null;
  if (entries is! List || entries.isEmpty) return const [];
  final messages = <String>{};
  for (final entry in entries) {
    final desc = (entry is Map) ? entry['description'] as String? : null;
    if (desc == null) continue;
    messages.add(_translate(desc));
  }
  return messages.toList();
}

String _translate(String code) {
  if (code.contains('business_url') || code.contains('business_profile')) {
    return 'Sitio web o descripción del negocio';
  }
  if (code.contains('external_account')) {
    return 'Cuenta bancaria (CLABE) para recibir los pagos';
  }
  if (code.contains('verification.document') || code.contains('verification.additional_document')) {
    return 'Identificación oficial (foto del documento)';
  }
  if (code.contains('id_number')) {
    return 'RFC o número de identificación';
  }
  if (code.contains('phone')) {
    return 'Número de teléfono';
  }
  if (code.contains('dob.')) {
    return 'Fecha de nacimiento';
  }
  if (code.contains('address.')) {
    return 'Dirección completa';
  }
  if (code.contains('tos_acceptance')) {
    return 'Aceptar los términos de Stripe';
  }
  if (code.contains('email')) {
    return 'Correo de contacto';
  }
  return 'Un dato más en tu registro con Stripe';
}
