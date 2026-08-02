// location_service.dart
// Maneja todo lo relacionado con la ubicación GPS del usuario.
// Verifica si el usuario está dentro del radio de servicio de Maravatío
// y convierte coordenadas a direcciones de texto (geocoding inverso).

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

class LocationService {
  // Centro y radio de cobertura — valores por defecto (Maravatío, Michoacán).
  // Se pueden sobreescribir desde Supabase > platform_config (claves
  // "centro_lat", "centro_lng", "radio_metros") SIN necesitar una nueva
  // version de la app — util para ampliar la zona de servicio al momento.
  static double _lat = 19.8969;
  static double _lng = -100.4447;

  // Radio de cobertura en metros (~30 km cubre todo el municipio)
  static double _radioMetros = 30000;

  // Tarifa de envío: cuota base + costo por kilómetro recorrido
  // Valores por defecto usados si Supabase no está disponible
  static double tarifaBase = 15.0;   // MXN, se cobra siempre
  static double tarifaPorKm = 5.0;   // MXN por cada km entre restaurante y cliente

  // Carga las tarifas y la zona de cobertura desde Supabase (platform_config).
  // Se llama en main.dart al iniciar.
  static Future<void> loadTarifas() async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_config')
          .select('key, value');
      for (final row in rows as List) {
        final v = double.tryParse(row['value'] as String? ?? '');
        if (v == null) continue;
        switch (row['key']) {
          case 'tarifa_base':    tarifaBase   = v;
          case 'tarifa_por_km':  tarifaPorKm  = v;
          case 'radio_metros':   _radioMetros = v;
          case 'centro_lat':     _lat         = v;
          case 'centro_lng':     _lng         = v;
        }
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

    return LocationResult(
      status: distancia <= _radioMetros
          ? LocationStatus.enMaravatio
          : LocationStatus.fueraDeMaravatio,
      position: position,
      distanciaKm: distancia / 1000,
    );
  }

  // Bounding box de Maravatío: minLon,maxLat,maxLon,minLat
  static const _viewbox = '-100.50,19.95,-100.40,19.85';

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
      final fullAddress = '$address, Maravatío, Michoacán, México';
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
      final query = Uri.encodeComponent('$address, Maravatío, Michoacán, México');
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
    final base = '$address, Maravatío, Michoacán, México';
    final withCol = address.toLowerCase().contains('colonia')
        ? base
        : '${address.replaceAll(RegExp(r'\s+(\w+)$'), '')}, Colonia ${address.split(' ').last}, Maravatío, Michoacán, México';
    final sinNum = address.replaceAll(RegExp(r'#?\d+'), '').trim();
    final sinNumQuery = '$sinNum, Maravatío, Michoacán, México';
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
