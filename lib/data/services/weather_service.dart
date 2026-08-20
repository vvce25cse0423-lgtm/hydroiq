import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../models/app_models.dart';

/// Fetches real-time weather from OpenWeatherMap.
class WeatherService {
  static const String _apiKey = '624d64f50bcf3cf596ccf7693dce142f';

  /// Fetch weather by GPS coordinates
  Future<WeatherData> fetchByCoordinates(double lat, double lon) async {
    final url = '${AppConstants.weatherBaseUrl}/weather'
        '?lat=$lat&lon=$lon&appid=$_apiKey&units=metric';
    return _fetch(url);
  }

  /// Fetch weather by city name
  Future<WeatherData> fetchByCity(String city) async {
    final url = '${AppConstants.weatherBaseUrl}/weather'
        '?q=${Uri.encodeComponent(city)}&appid=$_apiKey&units=metric';
    return _fetch(url);
  }

  Future<WeatherData> _fetch(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return WeatherData.fromJsonMetric(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        throw const WeatherKeyInvalidException();
      } else if (response.statusCode == 404) {
        throw const WeatherCityNotFoundException();
      } else {
        throw Exception('Weather API error: ${response.statusCode}');
      }
    } on WeatherKeyInvalidException {
      rethrow;
    } on WeatherCityNotFoundException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to fetch weather: $e');
    }
  }
}

class WeatherKeyInvalidException implements Exception {
  const WeatherKeyInvalidException();
  @override
  String toString() => 'Invalid OpenWeatherMap API key.';
}

class WeatherCityNotFoundException implements Exception {
  const WeatherCityNotFoundException();
  @override
  String toString() => 'City not found. Check the spelling.';
}
