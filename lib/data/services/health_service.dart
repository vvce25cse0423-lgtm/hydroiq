import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:url_launcher/url_launcher.dart';

class HealthService {
  static final HealthService _instance = HealthService._();
  factory HealthService() => _instance;
  HealthService._();

  final Health _health = Health();
  bool _initialized = false;
  bool _available   = false;

  static const _hcChannel = MethodChannel('com.hydroiq.app/healthconnect');

  static const _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
  ];

  Future<bool> initialize() async {
    if (_initialized) return _available;
    try {
      await _health.configure();
      _available = true;
    } catch (_) {
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  Future<bool> get isAvailable async {
    await initialize();
    return _available;
  }

  Future<bool> requestPermissions() async {
    try {
      return await _health.requestAuthorization(
        _readTypes,
        permissions: _readTypes.map((_) => HealthDataAccess.READ).toList(),
      );
    } catch (_) { return false; }
  }

  Future<bool> hasPermissions() async {
    try {
      return await _health.hasPermissions(_readTypes,
          permissions: _readTypes.map((_) => HealthDataAccess.READ).toList()) ?? false;
    } catch (_) { return false; }
  }

  /// Today's steps via native HC (AggregateRequest) → flutter health → null
  Future<int?> getTodaySteps() async {
    // Try native Kotlin channel first (most accurate)
    try {
      final result = await _hcChannel
          .invokeMethod<dynamic>('getSteps')
          .timeout(const Duration(seconds: 5));
      if (result != null) return (result as num).toInt();
    } catch (_) {}

    // Fallback: Flutter health package
    try {
      final now   = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      return await _health.getTotalStepsInInterval(start, now);
    } catch (_) { return null; }
  }

  Future<void> syncNow() async {
    try { await _hcChannel.invokeMethod('syncNow'); } catch (_) {}
  }

  Future<int> getStepsForDate(DateTime date) async {
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end   = start.add(const Duration(days: 1));
      return await _health.getTotalStepsInInterval(start, end) ?? 0;
    } catch (_) { return 0; }
  }

  /// Weekly steps — tries native Kotlin channel first for batch accuracy
  Future<Map<String, int>> getWeeklySteps() async {
    // Try native batch call first
    try {
      final result = await _hcChannel
          .invokeMethod<Map<dynamic, dynamic>>('getWeeklySteps')
          .timeout(const Duration(seconds: 8));
      if (result != null && result.isNotEmpty) {
        return result.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {}

    // Fallback: query day-by-day
    final out = <String, int>{};
    for (int i = 6; i >= 0; i--) {
      final d   = DateTime.now().subtract(Duration(days: i));
      final key = '${d.year}_${d.month}_${d.day}';
      out[key] = await getStepsForDate(d);
    }
    return out;
  }

  Future<List<SleepSession>> getRecentSleep({int days = 7}) async {
    try {
      final now   = DateTime.now();
      final start = now.subtract(Duration(days: days));
      final data  = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION, HealthDataType.SLEEP_ASLEEP],
        startTime: start,
        endTime: now,
      );
      final sessions = <SleepSession>[];
      final seen = <String>{};
      for (final p in data) {
        final key = '${p.dateFrom.day}-${p.dateFrom.hour}';
        if (seen.contains(key)) continue;
        seen.add(key);
        final durH = p.dateTo.difference(p.dateFrom).inMinutes / 60.0;
        if (durH < 0.5) continue;
        int score = 50;
        if (durH >= 7 && durH <= 9) score = 95;
        else if (durH >= 6) score = 75;
        else if (durH >= 5) score = 55;
        sessions.add(SleepSession(
            start: p.dateFrom, end: p.dateTo,
            durationHours: durH, score: score, source: 'Health Connect'));
      }
      sessions.sort((a, b) => b.start.compareTo(a.start));
      return sessions;
    } catch (_) { return []; }
  }

  static Future<void> openHealthConnect() async {
    const url = 'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class SleepSession {
  final DateTime start, end;
  final double durationHours;
  final int score;
  final String source;
  SleepSession({required this.start, required this.end,
    required this.durationHours, required this.score, required this.source});
}
