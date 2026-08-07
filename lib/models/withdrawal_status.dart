import 'package:flutter/material.dart';

/// Estados conocidos hoy. La columna en la base de datos es TEXT libre — se
/// puede agregar un estado nuevo sin tocar el esquema, solo sumándolo aquí
/// (y en la máquina de estados de `admin_transition_withdrawal`).
class WithdrawalStatus {
  WithdrawalStatus._();

  static const pendiente = 'pendiente';
  static const enProceso = 'en_proceso';
  static const completado = 'completado';
  static const rechazado = 'rechazado';
  static const cancelado = 'cancelado';

  static const abiertos = [pendiente, enProceso];

  static (String, Color) styleFor(String status) => switch (status) {
        pendiente => ('Pendiente', const Color(0xFFFFB300)),
        enProceso => ('En proceso', const Color(0xFF2196F3)),
        completado => ('Completado', const Color(0xFF34C759)),
        rechazado => ('Rechazado', const Color(0xFFFF453A)),
        cancelado => ('Cancelado', Colors.grey),
        _ => ('Desconocido', Colors.grey),
      };
}
