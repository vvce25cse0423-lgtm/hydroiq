import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});
  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  final _cityCtrl = TextEditingController();
  bool _locLoading = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(weatherProvider).valueOrNull;
    if (existing == null) _fetchGps();
  }

  Future<void> _fetchGps() async {
    setState(() => _locLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        ref.read(weatherProvider.notifier).fetchByCoords(pos.latitude, pos.longitude);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location denied. Search city manually.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS error: $e')));
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  void _fetchCity() {
    final city = _cityCtrl.text.trim();
    if (city.isNotEmpty) ref.read(weatherProvider.notifier).fetchByCity(city);
  }

  String _emoji(String c) {
    final l = c.toLowerCase();
    if (l.contains('rain'))    return '🌧️';
    if (l.contains('cloud'))   return '☁️';
    if (l.contains('snow'))    return '❄️';
    if (l.contains('thunder')) return '⛈️';
    if (l.contains('mist') || l.contains('fog')) return '🌫️';
    return '☀️';
  }

  @override
  void dispose() { _cityCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final weatherAsync = ref.watch(weatherProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Weather'), actions: [
        IconButton(
          icon: _locLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location),
          tooltip: 'Use GPS',
          onPressed: _locLoading ? null : _fetchGps),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: TextField(controller: _cityCtrl,
            decoration: const InputDecoration(hintText: 'Search city...', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _fetchCity())),
          const SizedBox(width: 10),
          ElevatedButton(onPressed: _fetchCity,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
              child: const Text('Search')),
        ]),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _fetchGps,
          icon: const Icon(Icons.gps_fixed, size: 16),
          label: const Text('Use my GPS location')),
        const SizedBox(height: 20),
        weatherAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
          error: (e, _) => Column(children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Could not load weather. Check city name or API key.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchGps, child: const Text('Try GPS')),
          ]),
          data: (weather) {
            if (weather == null) return Column(children: [
              const SizedBox(height: 40),
              const Text('🌤️', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text('No weather data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Allow location or search a city above.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(onPressed: _fetchGps, icon: const Icon(Icons.my_location), label: const Text('Use GPS')),
            ]);
            final isHot = weather.temperatureC > 30;
            return Column(children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: isHot ? [const Color(0xFFE65100), const Color(0xFFFF8F00)]
                        : [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(28)),
                child: Column(children: [
                  Text(_emoji(weather.condition), style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 10),
                  Text('${weather.temperatureC.toStringAsFixed(1)}°C',
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(weather.city, style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(weather.condition[0].toUpperCase() + weather.condition.substring(1),
                      style: const TextStyle(color: Colors.white60, fontSize: 14)),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _DetailCard(emoji: '💧', label: 'Humidity',
                    value: '${weather.humidity.toStringAsFixed(0)}%', color: AppTheme.accentCyan)),
                const SizedBox(width: 12),
                Expanded(child: _DetailCard(emoji: '💦', label: 'Extra Needed',
                    value: '+${weather.recommendedExtraMl}ml', color: isHot ? Colors.orange : AppTheme.primaryBlue)),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isHot ? Colors.orange.withOpacity(0.3) : AppTheme.primaryBlue.withOpacity(0.2))),
                child: Row(children: [
                  const Text('🧠', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(weather.recommendedExtraMl > 0
                      ? 'It\'s ${isHot ? 'very hot' : 'warm'} (${weather.temperatureC.toStringAsFixed(0)}°C). We\'ve added +${weather.recommendedExtraMl}ml to your daily goal.'
                      : 'Weather is comfortable. Your standard hydration goal applies.',
                      style: const TextStyle(fontSize: 14, height: 1.5))),
                ]),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String emoji, label, value; final Color color;
  const _DetailCard({required this.emoji, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45)),
      ]),
    );
  }
}
