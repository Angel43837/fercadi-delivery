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
