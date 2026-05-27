import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';

class LocationService {
  // Centro del municipio de Maravatío, Michoacán
  static const double _lat = 19.8969;
  static const double _lng = -100.4447;

  // Radio del municipio en metros (~30 km cubre todo el municipio)
  static const double _radioMetros = 30000;

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

  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json');
      final client = HttpClient();
      final req = await client.getUrl(uri)
        ..headers.set('User-Agent', 'FercadiDeliveryApp/1.0 (contact@fercadi.com)');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
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

  static Future<({double lat, double lng})?> geocodeAddress(String address) async {
    // Intentar varias formas de la query, de más específica a más genérica
    final queries = _buildQueries(address);
    for (final q in queries) {
      final result = await _nominatim(q, bounded: true);
      if (result != null) return result;
    }
    // Último recurso: sin bounded (acepta cualquier ciudad de México)
    final result = await _nominatim(queries.first, bounded: false);
    return result;
  }

  static List<String> _buildQueries(String address) {
    // Normalizar: "Clara Cordova Moran #16 Victoria" → variantes
    final base = '$address, Maravatío, Michoacán, México';
    // Intentar también con "Colonia" explícito
    final withCol = address.contains('Colonia')
        ? base
        : '${address.replaceAll(RegExp(r'\s+(\w+)$'), '')}, Colonia ${address.split(' ').last}, Maravatío, Michoacán, México';
    // Sin número de casa
    final sinNum = address.replaceAll(RegExp(r'#?\d+'), '').trim();
    final sinNumQuery = '$sinNum, Maravatío, Michoacán, México';
    return [base, withCol, sinNumQuery];
  }

  static Future<({double lat, double lng})?> _nominatim(String query, {required bool bounded}) async {
    try {
      final q = Uri.encodeComponent(query);
      final viewboxParam = bounded ? '&viewbox=$_viewbox&bounded=1' : '';
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1&countrycodes=mx$viewboxParam');
      final client = HttpClient();
      final req = await client.getUrl(uri)
        ..headers.set('User-Agent', 'FercadiDeliveryApp/1.0 (contact@fercadi.com)');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final results = jsonDecode(body) as List;
      if (results.isEmpty) return null;
      return (
        lat: double.parse(results[0]['lat'] as String),
        lng: double.parse(results[0]['lon'] as String),
      );
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
