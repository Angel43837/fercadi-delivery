import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static Future<({double lat, double lng})?> searchAddress(String query) async {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
        .replace(queryParameters: {
      'q': '$query, Maravatío, Michoacán, México',
      'format': 'json',
      'limit': '1',
      'countrycodes': 'mx',
    });
    final res = await http.get(uri, headers: {'User-Agent': 'GOGOFood/1.0'});
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) return null;
    return (
      lat: double.parse(list[0]['lat'] as String),
      lng: double.parse(list[0]['lon'] as String),
    );
  }
}
