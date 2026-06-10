import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../models/app_models.dart';

/// Service for fetching real weather data from OpenWeatherMap
class WeatherService {
  /// Fetch weather by lat/lon (GPS)
  Future<WeatherData> fetchByCoordinates(double lat, double lon) async {
    final url =
        '${AppConstants.weatherBaseUrl}/weather?lat=$lat&lon=$lon&appid=${AppConstants.weatherApiKey}';
    return _fetch(url);
  }

  /// Fetch weather by city name (manual selection fallback)
  Future<WeatherData> fetchByCity(String city) async {
    final url =
        '${AppConstants.weatherBaseUrl}/weather?q=${Uri.encodeComponent(city)}&appid=${AppConstants.weatherApiKey}';
    return _fetch(url);
  }

  Future<WeatherData> _fetch(String url) async {
    try {
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return WeatherData.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Weather API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch weather: $e');
    }
  }
}
