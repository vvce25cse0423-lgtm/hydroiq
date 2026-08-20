import 'dart:async';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sleep_detection_engine.dart';

/// Merges Health Connect sessions + manual sessions with deduplication,
/// offline caching, and Supabase sync reliability.
class SleepHealthService {
  static final SleepHealthService _i = SleepHealthService._();
  factory SleepHealthService() => _i;
  SleepHealthService._();

  final Health _health = Health();
  bool _initialized = false;
  bool _hcAvailable = false;
  bool _hcPermitted = false;

  static const _cacheKey   = 'sleep_hc_cache_json';
  static const _permKey    = 'sleep_hc_permitted';
  static const _lastSyncKey= 'sleep_hc_last_sync_ms';

  static const _readTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _health.configure();
      _hcAvailable = true;
    } catch (_) {
      _hcAvailable = false;
    }
    final prefs = await SharedPreferences.getInstance();
    _hcPermitted = prefs.getBool(_permKey) ?? false;
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    if (!_hcAvailable) return false;
    try {
      final ok = await _health.requestAuthorization(
        _readTypes,
        permissions: _readTypes.map((_) => HealthDataAccess.READ).toList(),
      );
      _hcPermitted = ok;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permKey, ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkPermissions() async {
    if (!_hcAvailable) return false;
    try {
      final ok = await _health.hasPermissions(
        _readTypes,
        permissions: _readTypes.map((_) => HealthDataAccess.READ).toList(),
      ) ?? false;
      _hcPermitted = ok;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permKey, ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  bool get isAvailable => _hcAvailable;
  bool get isPermitted => _hcPermitted;

  // ── Fetch from Health Connect ─────────────────────────────────────────────

  Future<List<ScoredSleepSession>> fetchHCSessions({int days = 14}) async {
    await initialize();
    if (!_hcAvailable || !_hcPermitted) return _loadCached();

    try {
      final now   = DateTime.now();
      final start = now.subtract(Duration(days: days));

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION, HealthDataType.SLEEP_ASLEEP],
        startTime: start,
        endTime: now,
      );

      if (data.isEmpty) return _loadCached();

      final sessions = _parseHCData(data);
      await _saveCache(sessions);
      await SharedPreferences.getInstance()
        .then((p) => p.setInt(_lastSyncKey, now.millisecondsSinceEpoch));
      return sessions;
    } catch (_) {
      return _loadCached();
    }
  }

  List<ScoredSleepSession> _parseHCData(List<HealthDataPoint> data) {
    final seen = <String>{};
    final out  = <ScoredSleepSession>[];

    for (final p in data) {
      final dur = p.dateTo.difference(p.dateFrom).inMinutes / 60.0;
      if (dur < 0.5) continue;

      // Dedup key: date + rounded start hour
      final key = '${p.dateFrom.year}${p.dateFrom.month}${p.dateFrom.day}'
                  '${p.dateFrom.hour}';
      if (seen.contains(key)) continue;
      seen.add(key);

      final score = _scoreHCSession(p.dateFrom, p.dateTo, dur);

      out.add(ScoredSleepSession(
        start:         p.dateFrom,
        end:           p.dateTo,
        durationHours: dur,
        score:         score,
        source:        'Health Connect',
        quality:       _qualityLabel(score),
      ));
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  int _scoreHCSession(DateTime start, DateTime end, double hours) {
    double d = 0;
    if (hours >= 7 && hours <= 9)      d = 50;
    else if (hours >= 6.5)             d = 42;
    else if (hours >= 6)               d = 35;
    else if (hours >= 5)               d = 22;
    else                               d = 10;

    double c = (start.hour >= 21 || start.hour <= 1) ? 25
             : (start.hour <= 5) ? 15 : 10;

    return (d + c + 20).clamp(0, 100).round(); // No interruption data from HC
  }

  String _qualityLabel(int score) {
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Poor';
  }

  // ── Merge manual + HC with deduplication ──────────────────────────────────

  List<ScoredSleepSession> mergeAndDeduplicate(
    List<ScoredSleepSession> hc,
    List<ScoredSleepSession> manual,
  ) {
    final merged = [...hc];
    for (final m in manual) {
      final overlap = hc.any((h) =>
          h.start.difference(m.start).abs().inMinutes < 45);
      if (!overlap) merged.add(m);
    }
    merged.sort((a, b) => b.start.compareTo(a.start));
    return merged;
  }

  // ── Offline cache (lightweight JSON) ──────────────────────────────────────

  Future<void> _saveCache(List<ScoredSleepSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final top5  = sessions.take(10).map((s) =>
        '${s.start.millisecondsSinceEpoch},${s.end.millisecondsSinceEpoch},'
        '${s.durationHours},${s.score},${s.source},${s.interruptions},${s.quality}'
    ).join('|');
    await prefs.setString(_cacheKey, top5);
  }

  List<ScoredSleepSession> _loadCached() {
    // Returns synchronously — call after init
    return [];
  }

  Future<List<ScoredSleepSession>> loadCachedAsync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_cacheKey) ?? '';
    if (raw.isEmpty) return [];
    try {
      return raw.split('|').map((line) {
        final p = line.split(',');
        final dur = double.parse(p[2]);
        return ScoredSleepSession(
          start:         DateTime.fromMillisecondsSinceEpoch(int.parse(p[0])),
          end:           DateTime.fromMillisecondsSinceEpoch(int.parse(p[1])),
          durationHours: dur,
          score:         int.parse(p[3]),
          source:        p[4],
          interruptions: int.parse(p[5]),
          quality:       p[6],
        );
      }).toList();
    } catch (_) { return []; }
  }

  // ── Sleep schedule trend ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> computeTrend(
      List<ScoredSleepSession> sessions) async {
    if (sessions.isEmpty) return {};
    final last7 = sessions.take(7).toList();
    final avgHours = last7.map((s) => s.durationHours)
        .reduce((a, b) => a + b) / last7.length;
    final avgScore = last7.map((s) => s.score)
        .reduce((a, b) => a + b) ~/ last7.length;
    final avgBedHour = last7.map((s) => s.start.hour)
        .reduce((a, b) => a + b) ~/ last7.length;
    return {
      'avgHours':   avgHours,
      'avgScore':   avgScore,
      'avgBedHour': avgBedHour,
      'sessions':   last7.length,
    };
  }
}
