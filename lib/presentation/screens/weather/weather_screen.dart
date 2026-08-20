import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_theme.dart';
import '../../../data/services/weather_service.dart';
import '../../../providers/app_providers.dart';

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});
  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  final _cityCtrl       = TextEditingController();
  final _focusNode      = FocusNode();
  bool  _locLoading     = false;
  List<_CitySuggestion> _suggestions = [];
  bool  _showSuggestions = false;
  Timer? _debounce;
  bool  _selectingFromList = false;

  static const _geoApiKey = '624d64f50bcf3cf596ccf7693dce142f';

  @override
  void initState() {
    super.initState();
    final existing = ref.read(weatherProvider).valueOrNull;
    if (existing == null) _fetchGps();
    _cityCtrl.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  void _onTextChanged() {
    if (_selectingFromList) return;
    final query = _cityCtrl.text.trim();
    if (query.length < 2) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final url = 'http://api.openweathermap.org/geo/1.0/direct'
          '?q=${Uri.encodeComponent(query)}&limit=5&appid=$_geoApiKey';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        final sug = list.map((e) {
          final m = e as Map<String, dynamic>;
          final name    = m['name']    as String? ?? '';
          final state   = m['state']   as String? ?? '';
          final country = m['country'] as String? ?? '';
          final lat     = (m['lat'] as num).toDouble();
          final lon     = (m['lon'] as num).toDouble();
          final display = [name, if (state.isNotEmpty) state, country]
              .where((s) => s.isNotEmpty).join(', ');
          return _CitySuggestion(display: display, name: name, lat: lat, lon: lon);
        }).toList();
        if (mounted) setState(() { _suggestions = sug; _showSuggestions = sug.isNotEmpty; });
      }
    } catch (_) {}
  }

  void _selectSuggestion(_CitySuggestion sug) {
    _selectingFromList = true;
    _cityCtrl.text = sug.display;
    _selectingFromList = false;
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();
    ref.read(weatherProvider.notifier).fetchByCoords(sug.lat, sug.lon);
  }

  Future<void> _fetchGps() async {
    setState(() => _locLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        ref.read(weatherProvider.notifier).fetchByCoords(pos.latitude, pos.longitude);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location denied. Search a city manually.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('GPS error: $e')));
      }
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  void _fetchCity() {
    final city = _cityCtrl.text.trim();
    if (city.isNotEmpty) {
      setState(() => _showSuggestions = false);
      ref.read(weatherProvider.notifier).fetchByCity(city);
      _focusNode.unfocus();
    }
  }

  /// Temperature-aware emoji for the weather icon display
  static String weatherEmoji(String condition, double tempC) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) return '⛈️';
    if (c.contains('drizzle')) return '🌦️';
    if (c.contains('rain') && (c.contains('heavy') || c.contains('shower'))) return '🌧️';
    if (c.contains('rain')) return '🌦️';
    if (c.contains('snow') || c.contains('blizzard')) return '❄️';
    if (c.contains('sleet') || c.contains('hail')) return '🌨️';
    if (c.contains('mist') || c.contains('fog') || c.contains('haze')) return '🌫️';
    if (c.contains('cloud') && c.contains('partly')) return '⛅';
    if (c.contains('cloud') || c.contains('overcast')) return '☁️';
    if (c.contains('wind') || c.contains('breezy')) return '💨';
    // Clear/sunny — differentiate by temperature
    if (tempC >= 35) return '🔥';
    if (tempC >= 28) return '☀️';
    if (tempC >= 18) return '🌤️';
    if (tempC >= 8)  return '🌥️';
    return '🥶';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cityCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weatherAsync = ref.watch(weatherProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather'),
        actions: [
          IconButton(
            icon: _locLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            tooltip: 'Use GPS',
            onPressed: _locLoading ? null : _fetchGps),
        ]),
      body: GestureDetector(
        onTap: () {
          _focusNode.unfocus();
          setState(() => _showSuggestions = false);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Search row with autocomplete ──────────────────────────────
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: TextField(
                  controller: _cityCtrl,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search city…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12)),
                  onSubmitted: (_) => _fetchCity())),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _fetchCity,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: const Text('Search',
                      style: TextStyle(fontWeight: FontWeight.w700))),
              ]),

              // ── Suggestion dropdown ──────────────────────────────────────
              if (_showSuggestions && _suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2430) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.primaryBlue.withOpacity(0.25)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]),
                  child: Column(
                    children: _suggestions.asMap().entries.map((entry) {
                      final i   = entry.key;
                      final sug = entry.value;
                      return InkWell(
                        borderRadius: BorderRadius.only(
                          topLeft:     Radius.circular(i == 0 ? 14 : 0),
                          topRight:    Radius.circular(i == 0 ? 14 : 0),
                          bottomLeft:  Radius.circular(i == _suggestions.length - 1 ? 14 : 0),
                          bottomRight: Radius.circular(i == _suggestions.length - 1 ? 14 : 0)),
                        onTap: () => _selectSuggestion(sug),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          child: Row(children: [
                            Icon(Icons.location_on_outlined,
                                size: 17,
                                color: AppTheme.primaryBlue.withOpacity(0.7)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(sug.display,
                                style: const TextStyle(fontSize: 14))),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _fetchGps,
              icon: const Icon(Icons.gps_fixed, size: 16),
              label: const Text('Use my GPS location')),
            const SizedBox(height: 20),

            // ── Weather content ────────────────────────────────────────
            weatherAsync.when(
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator())),
              error: (e, _) => _ErrorCard(
                  error: e, isDark: isDark, onGps: _fetchGps),
              data: (weather) => weather == null
                  ? _EmptyCard(onGps: _fetchGps)
                  : _WeatherCard(weather: weather, isDark: isDark),
            ),
          ]),
      ),
    );
  }
}

class _CitySuggestion {
  final String display;
  final String name;
  final double lat;
  final double lon;
  const _CitySuggestion({
    required this.display, required this.name,
    required this.lat, required this.lon});
}

// ── Error Card ─────────────────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  final Object error;
  final bool isDark;
  final VoidCallback onGps;
  const _ErrorCard({required this.error, required this.isDark, required this.onGps});

  @override
  Widget build(BuildContext context) {
    final isCityIssue = error is WeatherCityNotFoundException;
    return Column(children: [
      const SizedBox(height: 20),
      Text(isCityIssue ? '🔍' : '⚠️', style: const TextStyle(fontSize: 56)),
      const SizedBox(height: 14),
      Text(
        isCityIssue
            ? 'City not found.\nCheck the spelling and try again.'
            : 'Could not load weather.\nPlease try again.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, height: 1.5)),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: onGps,
        icon: const Icon(Icons.my_location, size: 16),
        label: const Text('Try GPS'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)))),
    ]);
  }
}

// ── Empty State ────────────────────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  final VoidCallback onGps;
  const _EmptyCard({required this.onGps});
  @override
  Widget build(BuildContext context) => Column(children: [
    const SizedBox(height: 40),
    const Text('🌤️', style: TextStyle(fontSize: 64)),
    const SizedBox(height: 16),
    const Text('No weather data',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    const Text('Allow location or search a city above.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey)),
    const SizedBox(height: 20),
    ElevatedButton.icon(
      onPressed: onGps,
      icon: const Icon(Icons.my_location),
      label: const Text('Use GPS'),
      style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)))),
  ]);
}

// ── Weather Card ───────────────────────────────────────────────────────────
class _WeatherCard extends StatelessWidget {
  final dynamic weather;
  final bool isDark;
  const _WeatherCard({required this.weather, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final temp   = weather.temperatureC as double;
    final isHot  = temp > 30;
    final isCold = temp < 10;
    final emoji  = _WeatherScreenState.weatherEmoji(weather.condition as String, temp);
    return Column(children: [
      // Main temperature card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isHot
                ? [const Color(0xFFE65100), const Color(0xFFFF8F00)]
                : isCold
                    ? [const Color(0xFF37474F), const Color(0xFF546E7A)]
                    : [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]),
          borderRadius: BorderRadius.circular(28)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 10),
          Text('${temp.toStringAsFixed(1)}°C',
              style: const TextStyle(
                  fontSize: 56, fontWeight: FontWeight.w900,
                  color: Colors.white)),
          Text(weather.city as String,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            (weather.condition as String)[0].toUpperCase() +
                (weather.condition as String).substring(1),
            style: const TextStyle(color: Colors.white60, fontSize: 14)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _DetailCard(
            emoji: '💧',
            label: 'Humidity',
            value: '${(weather.humidity as double).toStringAsFixed(0)}%',
            color: AppTheme.accentCyan)),
        const SizedBox(width: 12),
        Expanded(child: _DetailCard(
            emoji: '💦',
            label: 'Extra Water',
            value: (weather.recommendedExtraMl as int) > 0
                ? '+${weather.recommendedExtraMl}ml'
                : 'Normal',
            color: isHot ? Colors.orange : AppTheme.primaryBlue)),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: (isHot ? Colors.orange : AppTheme.primaryBlue).withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ]),
        child: Row(children: [
          const Text('🧠', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            (weather.recommendedExtraMl as int) > 0
                ? 'It\'s ${isHot ? 'very hot' : 'warm'} '
                  '(${temp.toStringAsFixed(0)}°C). '
                  'We\'ve added +${weather.recommendedExtraMl}ml to your daily hydration goal.'
                : 'Weather is comfortable today. Your standard hydration goal applies.',
            style: const TextStyle(fontSize: 14, height: 1.5))),
        ]),
      ),
    ]);
  }
}

class _DetailCard extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  const _DetailCard(
      {required this.emoji, required this.label,
       required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45)),
      ]),
    );
  }
}
