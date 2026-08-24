// Smoke test básico de la app Fercadi.
//
// Verifica que el widget raíz (FercadiApp) se construya sin lanzar
// excepciones. No usa pumpAndSettle porque el splash tiene un timer
// de 3s y navegación con go_router.

import 'package:flutter_test/flutter_test.dart';

import 'package:landing_test/main.dart';

void main() {
  testWidgets('FercadiApp se construye sin errores', (WidgetTester tester) async {
    await tester.pumpWidget(const FercadiApp());

    // Si llegamos aquí sin excepción, el árbol de widgets raíz es válido.
    expect(tester.takeException(), isNull);
  });
}
