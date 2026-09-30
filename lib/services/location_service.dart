// location_service.dart
// Maneja todo lo relacionado con la ubicación GPS del usuario.
// Verifica si el usuario está dentro del radio de servicio de Maravatío
// y convierte coordenadas a direcciones de texto (geocoding inverso).

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

class LocationService {
  // Centro del municipio de Maravatío, Michoacán
  static const double _lat = 19.8969;
  static const double _lng = -100.4447;

  // Centro del municipio de Acámbaro, Guanajuato
  static const double _latAcambaro = 20.0386;
  static const double _lngAcambaro = -100.7284;

  // Centro de Morelia, Michoacán (Catedral) — zona nueva agregada a
  // petición del dueño (septiembre 2026). A diferencia de Acámbaro, Morelia
  // está a ~80 km de Maravatío (fuera del radio de servicio), así que
  // necesita su propio centro y su propia verificación de radio — no basta
  // con el radio de Maravatío como pasa con Acámbaro.
  static const double _latMorelia = 19.7059;
  static const double _lngMorelia = -101.1949;

  // Radio de servicio en metros — cubre Maravatío y también Acámbaro
  // (~33-34 km entre centros), a petición del dueño para que alguien en
  // Acámbaro pueda pedirle a un restaurante de Maravatío. Morelia usa este
  // mismo radio pero contado desde su propio centro (ver verificarUbicacion).
  static const double _radioMetros = 50000;

  // Nombre para mostrar de cada zona — centralizado aquí para no repetir el
  // mismo ternario/switch en cada pantalla que muestra la zona.
  static String zonaLabel(String zona) => switch (zona) {
        'acambaro' => 'Acámbaro',
        'morelia'  => 'Morelia',
        _          => 'Maravatío',
      };

  // Tarifa de envío: cuota base + costo por kilómetro recorrido
  // Valores por defecto usados si Supabase no está disponible
  static double tarifaBase = 15.0;   // MXN, se cobra siempre
  static double tarifaPorKm = 5.0;   // MXN por cada km entre restaurante y cliente

  // % que se queda la plataforma (GOGO) — de cada envío que gana un
  // repartidor, y de cada venta de un restaurante. Configurable en
  // platform_config (comision_repartidor_pct/comision_restaurante_pct);
  // 10% por default si no hay nada configurado.
  static double comisionRepartidorPct = 10.0;
  static double comisionRestaurantePct = 10.0;

  // Carga las tarifas desde Supabase (platform_config). Se llama en main.dart al iniciar.
  static Future<void> loadTarifas() async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_config')
          .select('key, value');
      for (final row in rows as List) {
        final v = double.tryParse(row['value'] as String? ?? '');
        if (v == null) continue;
        if (row['key'] == 'tarifa_base')   tarifaBase   = v;
        if (row['key'] == 'tarifa_por_km') tarifaPorKm  = v;
        if (row['key'] == 'comision_repartidor_pct')  comisionRepartidorPct  = v;
        if (row['key'] == 'comision_restaurante_pct') comisionRestaurantePct = v;
      }
    } catch (_) {
      // Si falla, se usan los valores por defecto definidos arriba
    }
  }

  // Calcula el costo de envío en MXN dada la distancia en km.
  // Si no se conoce la distancia (faltan coordenadas), regresa solo la tarifa base.
  static double calcularCostoEnvio(double? distanciaKm) {
    if (distanciaKm == null) return tarifaBase;
    return tarifaBase + (tarifaPorKm * distanciaKm);
  }

  // Cuánto ganaría un repartidor específico por entregar ESTE pedido, ya con
  // la comisión de la plataforma descontada — a diferencia de la tarifa que
  // se le cobró al cliente en el checkout (que solo cuenta restaurante→
  // cliente), aquí también se cuenta lo que el repartidor tiene que recorrer
  // desde donde está parado ahorita hasta el restaurante, antes de ir a
  // entregar — dos repartidores en lugares distintos ven un estimado
  // distinto para el mismo pedido.
  static double estimarGananciaRepartidor({
    required double riderLat,
    required double riderLng,
    required double restaurantLat,
    required double restaurantLng,
    required double customerLat,
    required double customerLng,
  }) {
    final distRiderRestaurante = Geolocator.distanceBetween(
          riderLat, riderLng, restaurantLat, restaurantLng,
        ) /
        1000;
    final distRestauranteCliente = Geolocator.distanceBetween(
          restaurantLat, restaurantLng, customerLat, customerLng,
        ) /
        1000;
    final envio = calcularCostoEnvio(distRiderRestaurante + distRestauranteCliente);
    return envio * (1 - comisionRepartidorPct / 100);
  }

  // Pide el permiso de ubicación y, si ya quedó denegado permanentemente
  // (iOS ya no vuelve a mostrar su propio aviso en ese caso), muestra un
  // diálogo dentro de la app para guiar al usuario a Ajustes — así sí se
  // le "pide" la ubicación cada vez, aunque sea con un diálogo propio.
  static Future<bool> ensureLocationPermission(BuildContext context) async {
    // El permiso de la app y el GPS general del teléfono son cosas
    // distintas — con el permiso concedido pero el GPS apagado, tampoco
    // llega ninguna posición.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return false;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Activa tu ubicación'),
          content: const Text(
              'El GPS de tu teléfono está apagado. Actívalo para mostrar tu posición en el mapa.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openLocationSettings();
              },
              child: const Text('Activar GPS'),
            ),
          ],
        ),
      );
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      return true;
    }
    if (!context.mounted) return false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se necesita tu ubicación'),
        content: const Text(
            'Para mostrar tu posición en el mapa, activa el permiso de ubicación en Ajustes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Abrir Ajustes'),
          ),
        ],
      ),
    );
    return false;
  }

  // Verifica si el usuario tiene GPS activado, permisos concedidos y está dentro del radio
  static Future<LocationResult> verificarUbicacion() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult(status: LocationStatus.servicioDesactivado);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationResult(status: LocationStatus.permisoDenegado);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationResult(status: LocationStatus.permisoDenegadoPermanente);
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );

    final distancia = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _lat,
      _lng,
    );
    // Morelia está fuera del radio de Maravatío/Acámbaro — se revisa aparte
    // contra su propio centro. Si el usuario está dentro de cualquiera de
    // los dos, cuenta como "en zona de servicio".
    final distanciaMorelia = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _latMorelia,
      _lngMorelia,
    );
    final dentroDeZona = distancia <= _radioMetros || distanciaMorelia <= _radioMetros;

    return LocationResult(
      status: dentroDeZona
          ? LocationStatus.enMaravatio
          : LocationStatus.fueraDeMaravatio,
      position: position,
      distanciaKm: (distancia < distanciaMorelia ? distancia : distanciaMorelia) / 1000,
    );
  }

  // ── Zona del restaurante (Maravatío / Acámbaro) ─────────────────────────
  // Detecta automáticamente a qué municipio pertenece un restaurante según
  // sus coordenadas o su dirección, para no pedirle al dueño que lo elija
  // a mano. Usa su propio geocoding (sin forzar "Maravatío" en la búsqueda,
  // a diferencia de geocodeAddress) para que funcione igual de bien con
  // direcciones de Acámbaro.
  static String zonaFromCoords(double lat, double lng) {
    final dMaravatio = Geolocator.distanceBetween(lat, lng, _lat, _lng);
    final dAcambaro  = Geolocator.distanceBetween(lat, lng, _latAcambaro, _lngAcambaro);
    final dMorelia   = Geolocator.distanceBetween(lat, lng, _latMorelia, _lngMorelia);
    if (dMorelia < dMaravatio && dMorelia < dAcambaro) return 'morelia';
    return dAcambaro < dMaravatio ? 'acambaro' : 'maravatio';
  }

  static Future<String> detectZona(String address) async {
    if (address.trim().isEmpty) return 'maravatio';
    try {
      final coords = await _geocodeSinMunicipioForzado(address);
      if (coords == null) return 'maravatio';
      return zonaFromCoords(coords.lat, coords.lng);
    } catch (_) {
      return 'maravatio';
    }
  }

  static Future<({double lat, double lng})?> _geocodeSinMunicipioForzado(String address) async {
    if (!kIsWeb) {
      try {
        var locations = await geo.locationFromAddress('$address, México');
        if (locations.isEmpty) locations = await geo.locationFromAddress(address);
        if (locations.isNotEmpty) {
          return (lat: locations.first.latitude, lng: locations.first.longitude);
        }
      } catch (_) {}
    }
    try {
      final query = Uri.encodeComponent('$address, México');
      final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=$query&key=${AppConstants.googleMapsApiKey}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] == 'OK') {
        final results = data['results'] as List;
        if (results.isNotEmpty) {
          final loc = (results[0]['geometry'] as Map)['location'] as Map;
          return (lat: (loc['lat'] as num).toDouble(), lng: (loc['lng'] as num).toDouble());
        }
      }
    } catch (_) {}
    // Nominatim como último respaldo — antes esta función se quedaba sin
    // opciones aquí y detectZona() caía silenciosamente a 'maravatio' (bug
    // real encontrado septiembre 2026: la Google Geocoding API está
    // rechazando todo con REQUEST_DENIED porque el proyecto de Google Cloud
    // de esa API key no tiene facturación habilitada — confirmado con curl
    // directo a la API, no es un problema de la app). Esto dejaba
    // restaurantes de Morelia mal detectados como Maravatío si el geocoder
    // nativo del dispositivo tampoco resolvía esa dirección en particular.
    return await _nominatim('$address, México', bounded: true);
  }

  // Bounding box de Maravatío: minLon,maxLat,maxLon,minLat
  // Cubre Maravatío + Acámbaro + Morelia con margen — antes solo cubría
  // Maravatío, lo que hacía que Nominatim (bounded=1) descartara de raíz
  // cualquier resultado en Morelia.
  static const _viewbox = '-101.35,20.15,-100.30,19.55';

  // Convierte coordenadas GPS (lat, lng) a una dirección de texto legible.
  // Intenta Google Geocoding primero (más preciso para México), luego Nominatim.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    return await _googleReverseGeocode(lat, lng) ??
           await _nominatimReverseGeocode(lat, lng);
  }

  static Future<String?> _googleReverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng&key=${AppConstants.googleMapsApiKey}&language=es&result_type=street_address|route');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final components = (results[0]['address_components'] as List)
          .cast<Map<String, dynamic>>();
      String? streetNumber, route, sublocality;
      for (final c in components) {
        final types = (c['types'] as List).cast<String>();
        if (types.contains('street_number')) streetNumber = c['long_name'] as String?;
        if (types.contains('route'))         route        = c['long_name'] as String?;
        if (types.contains('sublocality_level_1') || types.contains('neighborhood')) {
          sublocality = c['long_name'] as String?;
        }
      }
      if (route == null) return null;
      final street = streetNumber != null ? '$route #$streetNumber' : route;
      final parts = <String>[
        street,
        if (sublocality != null) sublocality,
      ];
      return parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _nominatimReverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json');
      final res = await http.get(uri,
          headers: {'User-Agent': 'FercadiDeliveryApp/1.0 (contact@fercadi.com)'});
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return data['display_name'] as String?;
      final parts = <String>[];
      final road = addr['road'] ?? addr['pedestrian'] ?? addr['street'];
      final house = addr['house_number'];
      if (road != null) parts.add(house != null ? '$road $house' : road as String);
      final suburb = addr['suburb'] ?? addr['neighbourhood'] ?? addr['quarter'];
      if (suburb != null) parts.add(suburb as String);
      return parts.isNotEmpty ? parts.join(', ') : data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Convierte una dirección de texto a coordenadas GPS.
  // En móvil usa el geocoder nativo del dispositivo (Android = datos de Google,
  // sin API key ni billing). En web usa Google API → Nominatim como respaldo.
  static Future<({double lat, double lng})?> geocodeAddress(String address) async {
    // 1. Geocoder nativo del dispositivo (solo móvil)
    if (!kIsWeb) {
      final result = await _deviceGeocode(address);
      if (result != null) return result;
    }

    // 2. Google Geocoding API HTTP (web, o respaldo si el geocoder nativo falla)
    final googleResult = await _googleGeocode(address);
    if (googleResult != null) return googleResult;

    // 3. Nominatim con validación de palabras clave (último recurso)
    final queries = _buildQueries(address);
    final words   = _significantWords(address);
    for (final q in queries) {
      final result = await _nominatim(q, bounded: true, validate: words);
      if (result != null) return result;
    }
    return null;
  }

  static Future<({double lat, double lng})?> _deviceGeocode(String address) async {
    try {
      final fullAddress = '$address, Michoacán, México';
      var locations = await geo.locationFromAddress(fullAddress);
      if (locations.isEmpty) {
        locations = await geo.locationFromAddress(address);
      }
      if (locations.isEmpty) return null;
      return (lat: locations.first.latitude, lng: locations.first.longitude);
    } catch (_) {
      return null;
    }
  }

  static Future<({double lat, double lng})?> _googleGeocode(String address) async {
    try {
      final query = Uri.encodeComponent('$address, Michoacán, México');
      final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=$query&key=${AppConstants.googleMapsApiKey}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final results = data['results'] as List;
      if (results.isEmpty) return null;
      final loc = (results[0]['geometry'] as Map)['location'] as Map;
      return (lat: (loc['lat'] as num).toDouble(), lng: (loc['lng'] as num).toDouble());
    } catch (_) {
      return null;
    }
  }

  // Palabras muy genéricas que aparecen en cualquier calle y no sirven para validar
  static const _stopWords = {
    'calle', 'avenida', 'colonia', 'entre', 'casa', 'numero', 'bloc', 'lote',
  };

  // Devuelve las palabras significativas de la dirección (4+ letras, no stop words)
  static List<String> _significantWords(String address) =>
      address
          .toLowerCase()
          .replaceAll(RegExp(r'[#,\.\d]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3 && !_stopWords.contains(w))
          .toList();

  static List<String> _buildQueries(String address) {
    final base = '$address, Michoacán, México';
    final withCol = address.toLowerCase().contains('colonia')
        ? base
        : '${address.replaceAll(RegExp(r'\s+(\w+)$'), '')}, Colonia ${address.split(' ').last}, Michoacán, México';
    final sinNum = address.replaceAll(RegExp(r'#?\d+'), '').trim();
    final sinNumQuery = '$sinNum, Michoacán, México';
    return [base, withCol, sinNumQuery];
  }

  static Future<({double lat, double lng})?> _nominatim(
      String query, {required bool bounded, List<String> validate = const []}) async {
    try {
      final q = Uri.encodeComponent(query);
      final viewboxParam = bounded ? '&viewbox=$_viewbox&bounded=1' : '';
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=3&countrycodes=mx$viewboxParam');
      final res = await http.get(uri,
          headers: {'User-Agent': 'FercadiDeliveryApp/1.0 (contact@fercadi.com)'});
      final results = jsonDecode(res.body) as List;
      for (final r in results) {
        // Si tenemos palabras clave de la dirección, verificar que al menos una
        // aparezca en el resultado de Nominatim. Evita aceptar calles incorrectas.
        if (validate.isNotEmpty) {
          final display = (r['display_name'] as String? ?? '').toLowerCase();
          final matches = validate.any((w) => display.contains(w));
          if (!matches) continue;
        }
        return (
          lat: double.parse(r['lat'] as String),
          lng: double.parse(r['lon'] as String),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

enum LocationStatus {
  enMaravatio,
  fueraDeMaravatio,
  permisoDenegado,
  permisoDenegadoPermanente,
  servicioDesactivado,
}

class LocationResult {
  final LocationStatus status;
  final Position? position;
  final double? distanciaKm;

  LocationResult({required this.status, this.position, this.distanciaKm});
}
