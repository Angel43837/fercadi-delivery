// phone_number_field.dart
// Campo de teléfono con selector de código de país, mismo estilo visual que
// ya usa login_screen.dart (fondo translúcido oscuro, borde blanco al
// enfocar). Envuelve PhoneFormField (paquete phone_form_field) — la
// validación real (largo/formato por país) la hace el paquete mismo vía
// phone_numbers_parser, no un regex hecho a mano, así que agregar soporte
// para otro país después no necesita tocar este archivo.

import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';

class PhoneNumberField extends StatelessWidget {
  final PhoneController controller;
  final ValueChanged<PhoneNumber?> onChanged;
  final bool enabled;

  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // PhoneFormField no expone un parámetro `style` propio para el texto —
    // el TextFormField interno usa el estilo de texto ambiente del Theme.
    // Se envuelve en un Theme local para forzar texto blanco (mismo look
    // que el resto de los campos de login_screen.dart) sin tener que
    // reimplementar el widget a mano.
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      child: PhoneFormField(
        controller: controller,
        enabled: enabled,
        defaultCountry: 'MX',
        autofocus: false,
        autovalidateMode: AutovalidateMode.disabled,
        errorText: 'Número inválido',
        onChanged: onChanged,
        // El default del paquete (BottomSheetNavigator) no es modal — no
        // quita el foco del campo de teléfono, así que su teclado numérico
        // se queda abierto encima del buscador y no se puede cerrar
        // tocando afuera. Con una hoja modal propia (fondo blanco sólido +
        // tema claro forzado) sí se cierra bien, el buscador recibe su
        // propio foco/teclado, y no se ve la pantalla naranja de atrás
        // transparentándose bajo la barra de búsqueda.
        selectorNavigator: const _GogoCountrySelectorNavigator(),
        decoration: InputDecoration(
          labelText: 'Número de teléfono',
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// Hoja modal propia para elegir país — fondo blanco sólido explícito y tema
// claro forzado, en vez de heredar el canvasColor/textTheme ambiente (que en
// esta pantalla es oscuro/naranja y hacía que la barra de búsqueda y el
// fondo se vieran mezclados/transparentados encima de la pantalla de atrás).
class _GogoCountrySelectorNavigator implements CountrySelectorNavigator {
  const _GogoCountrySelectorNavigator();

  @override
  Future<Country?> navigate(BuildContext context) {
    return showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        child: Theme(
          data: ThemeData.light(),
          child: CountrySelector(
            countries: allCountries,
            onCountrySelected: (country) => Navigator.pop(sheetContext, country),
          ),
        ),
      ),
    );
  }
}

/// Valida un [PhoneNumber] usando el mismo parser que ya trae el paquete
/// (largo/formato real por país, no un regex hecho a mano).
bool isValidPhoneNumber(PhoneNumber? phone) {
  if (phone == null || phone.nsn.isEmpty) return false;
  try {
    return PhoneParser().validate(phone);
  } catch (_) {
    return false;
  }
}
