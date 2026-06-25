import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2:3000 to connect to localhost from Android Emulator,
  // or localhost:3000 for iOS simulator, web, or desktop.
  static const String baseUrl = 'https://proyectosig.onrender.com/api';

  // 1. Fetch all lines
  static Future<List<dynamic>> getLines() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/lines'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load lines from API: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getLines: $e');
      // If emulator fails, try fallback to standard localhost (for iOS/Desktop)
      return _fallbackGetLines(e);
    }
  }

  // 2. Fetch specific line detail (ida/retorno points)
  static Future<Map<String, dynamic>> getLineDetails(int lineId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/lines/$lineId'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load details for line $lineId: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getLineDetails: $e');
      return _fallbackGetLineDetails(lineId, e);
    }
  }

  // 3. Find lines near a coordinate
  static Future<List<dynamic>> getLinesNear(double lat, double lon, {double radius = 500.0}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/lines/near?lat=$lat&lon=$lon&radius=$radius'),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load nearby lines: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getLinesNear: $e');
      return _fallbackGetLinesNear(lat, lon, radius, e);
    }
  }

  // 4. Calculate optimal route (Dijkstra)
  static Future<Map<String, dynamic>?> getOptimalRoute(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon, {
    String mode = 'smart',
    String metric = 'time',
  }) async {
    try {
      final url = '$baseUrl/route?fromLat=$fromLat&fromLon=$fromLon&toLat=$toLat&toLon=$toLon&mode=$mode&metric=$metric';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null; // No route found
      } else {
        throw Exception('Failed to calculate route: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getOptimalRoute: $e');
      return _fallbackGetOptimalRoute(fromLat, fromLon, toLat, toLon, mode, metric, e);
    }
  }

  // FALLBACKS for localhost (iOS simulator / Desktop) if Android emulator loopback fails
  static const String altBaseUrl = 'http://localhost:3000/api';

  static Future<List<dynamic>> _fallbackGetLines(dynamic originalError) async {
    try {
      final response = await http.get(Uri.parse('$altBaseUrl/lines'));
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    throw Exception('API Connection Error. Please ensure backend is running at port 3000. original error: $originalError');
  }

  static Future<Map<String, dynamic>> _fallbackGetLineDetails(int lineId, dynamic originalError) async {
    try {
      final response = await http.get(Uri.parse('$altBaseUrl/lines/$lineId'));
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    throw Exception('API Connection Error. original error: $originalError');
  }

  static Future<List<dynamic>> _fallbackGetLinesNear(double lat, double lon, double radius, dynamic originalError) async {
    try {
      final response = await http.get(Uri.parse('$altBaseUrl/lines/near?lat=$lat&lon=$lon&radius=$radius'));
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    throw Exception('API Connection Error. original error: $originalError');
  }

  static Future<Map<String, dynamic>?> _fallbackGetOptimalRoute(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
    String mode,
    String metric,
    dynamic originalError,
  ) async {
    try {
      final url = '$altBaseUrl/route?fromLat=$fromLat&fromLon=$fromLon&toLat=$toLat&toLon=$toLon&mode=$mode&metric=$metric';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return json.decode(response.body);
      if (response.statusCode == 404) return null;
    } catch (_) {}
    throw Exception('API Connection Error. original error: $originalError');
  }
}
