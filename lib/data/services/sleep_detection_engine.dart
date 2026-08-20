import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ────────────────────────────────────────────────────────────────────
const kSleepTracking    = 'sleep_is_tracking';
const kSleepStartMs     = 'sleep_start_ms';
const kSleepConfidence  = 'sleep_confidence';
const kLastMotionMs     = 'sleep_last_motion_ms';
const kSleepInterrupts  = 'sleep_interruptions';
const kSleepScheduleHour= 'sleep_schedule_hour';

// ─── Sleep Signal ─────────────────────────────────────────────────────────────
class SleepSignal {
  final bool isTracking;
  final DateTime? sleepStart;
  final double confidence;     // 0.0–1.0
  final int interruptions;
  final String statusLabel;
  final bool autoStopped;
  final String autoStopReason;

  const SleepSignal({
    this.isTracking = false,
    this.sleepStart,
    this.confidence = 0,
    this.interruptions = 0,
    this.statusLabel = 'Ready',
    this.autoStopped = false,
    this.autoStopReason = '',
  });
}

// ─── Scored Sleep Session ─────────────────────────────────────────────────────
class ScoredSleepSession {
  final DateTime start;
  final DateTime end;
  final double durationHours;
  final int score;
  final String source;
  final int interruptions;
  final String quality;       // 'Poor' | 'Fair' | 'Good' | 'Excellent'

  const ScoredSleepSession({
    required this.start,
    required this.end,
    required this.durationHours,
    required this.score,
    required this.source,
    this.interruptions = 0,
    required this.quality,
  });
}

// ─── Engine ───────────────────────────────────────────────────────────────────
class SleepDetectionEngine {
  static final SleepDetectionEngine _i = SleepDetectionEngine._();
  factory SleepDetectionEngine() => _i;
  SleepDetectionEngine._();

  // Signal stream
  final _controller = StreamController<SleepSignal>.broadcast();
  Stream<SleepSignal> get signals => _controller.stream;

  // Internal state
  bool _tracking = false;
  DateTime? _sleepStart;
  int _interruptions = 0;
  double _confidence = 0.0;

  // Motion
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _analysisTimer;
  final _motionWindow = <_MotionSample>[];
  static const _windowDuration = Duration(minutes: 5);
  static const _basePickupVariance = 0.35;

  // Adaptive threshold — decreases as sleep deepens
  double get _adaptiveThreshold {
    if (_sleepStart == null) return _basePickupVariance;
    final elapsed = DateTime.now().difference(_sleepStart!).inMinutes;
    // After 60min sleep, raise threshold (deep sleep moves less)
    if (elapsed > 120) return _basePickupVariance * 1.8;
    if (elapsed > 60)  return _basePickupVariance * 1.4;
    return _basePickupVariance;
  }

  // Confidence factors
  static const _factorMotionStill  = 0.40;
  static const _factorNightTime    = 0.20;
  static const _factorDuration     = 0.25;
  static const _factorConsistency  = 0.15;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final tracking = prefs.getBool(kSleepTracking) ?? false;
    final startMs  = prefs.getInt(kSleepStartMs);

    if (tracking && startMs != null) {
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final elapsed = DateTime.now().difference(start);
      // Discard stale sessions > 16h
      if (elapsed.inHours < 16) {
        _tracking     = true;
        _sleepStart   = start;
        _interruptions= prefs.getInt(kSleepInterrupts) ?? 0;
        _confidence   = prefs.getDouble(kSleepConfidence) ?? 0.5;
        _startMotionMonitoring();
        _emitSignal();
      } else {
        await _clearPersistedState(prefs);
      }
    }
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> startTracking() async {
    if (_tracking) return;
    final now = DateTime.now();
    _tracking      = true;
    _sleepStart    = now;
    _interruptions = 0;
    _confidence    = 0.5;
    _motionWindow.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSleepTracking, true);
    await prefs.setInt(kSleepStartMs, now.millisecondsSinceEpoch);
    await prefs.setInt(kSleepInterrupts, 0);
    await prefs.setDouble(kSleepConfidence, 0.5);

    // Record sleep schedule hour for trend analysis
    await prefs.setInt(kSleepScheduleHour, now.hour);

    _startMotionMonitoring();
    _emitSignal();
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  Future<ScoredSleepSession?> stopTracking({String reason = 'manual'}) async {
    if (!_tracking || _sleepStart == null) return null;
    final end   = DateTime.now();
    final start = _sleepStart!;

    _stopMotionMonitoring();
    _tracking   = false;
    final session = _buildSession(start, end, _interruptions, reason);

    final prefs = await SharedPreferences.getInstance();
    await _clearPersistedState(prefs);
    _sleepStart    = null;
    _interruptions = 0;
    _confidence    = 0.0;

    _emitSignal(autoStopped: reason != 'manual', reason: reason);
    return session;
  }

  // ── Motion Monitoring ─────────────────────────────────────────────────────

  void _startMotionMonitoring() {
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccel);

    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(const Duration(minutes: 1), (_) => _analyzeMotion());
  }

  void _stopMotionMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _motionWindow.clear();
  }

  void _onAccel(AccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final now = DateTime.now();
    _motionWindow.add(_MotionSample(mag, now));

    // Trim window
    final cutoff = now.subtract(_windowDuration);
    _motionWindow.removeWhere((s) => s.time.isBefore(cutoff));
  }

  void _analyzeMotion() async {
    if (!_tracking || _motionWindow.length < 10) return;

    final values = _motionWindow.map((s) => s.magnitude).toList();
    final mean   = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / values.length;

    final isMoving = variance > _adaptiveThreshold;

    // Update confidence
    _updateConfidence(isMoving);

    if (isMoving) {
      _interruptions++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kSleepInterrupts, _interruptions);
      await prefs.setInt(kLastMotionMs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setDouble(kSleepConfidence, _confidence);

      // Only auto-stop if confidence drops very low (< 0.2) AND sustained
      if (_confidence < 0.2 && _interruptions > 3) {
        await stopTracking(reason: 'motion_sustained');
        return;
      }
    }

    _emitSignal();
  }

  void _updateConfidence(bool isMoving) {
    final now   = DateTime.now();
    final hour  = now.hour;
    final elapsed = _sleepStart != null
        ? now.difference(_sleepStart!).inMinutes
        : 0;

    // Night-time factor (10pm–8am)
    final nightFactor = (hour >= 22 || hour < 8) ? 1.0 : 0.5;

    // Duration factor (more time asleep → higher base)
    final durationFactor = math.min(1.0, elapsed / 360.0);

    // Motion factor
    final motionFactor = isMoving ? 0.0 : 1.0;

    // Consistency factor (fewer interruptions → better)
    final consistencyFactor = math.max(0.0, 1.0 - (_interruptions * 0.1));

    final raw = (_factorMotionStill * motionFactor) +
                (_factorNightTime * nightFactor) +
                (_factorDuration * durationFactor) +
                (_factorConsistency * consistencyFactor);

    // Smooth: blend toward new value
    _confidence = (_confidence * 0.7) + (raw * 0.3);
    _confidence = _confidence.clamp(0.0, 1.0);
  }

  // ── Session Scoring ───────────────────────────────────────────────────────

  ScoredSleepSession _buildSession(
    DateTime start, DateTime end, int interruptions, String reason,
  ) {
    final hours = end.difference(start).inMinutes / 60.0;

    // Duration score (0–50)
    double durationScore;
    if (hours >= 7 && hours <= 9)      durationScore = 50;
    else if (hours >= 6.5)             durationScore = 42;
    else if (hours >= 6)               durationScore = 35;
    else if (hours >= 5)               durationScore = 22;
    else                               durationScore = 10;

    // Consistency score (0–25) — based on start time vs schedule
    double consistencyScore = 20;
    // Night start bonus
    if (start.hour >= 21 || start.hour <= 1) consistencyScore = 25;
    else if (start.hour >= 2 && start.hour <= 5) consistencyScore = 15;
    else consistencyScore = 10;

    // Interruption score (0–25)
    final intScore = math.max(0, 25 - (interruptions * 5)).toDouble();

    final total = (durationScore + consistencyScore + intScore).clamp(0, 100).round();

    String quality;
    if (total >= 85)      quality = 'Excellent';
    else if (total >= 70) quality = 'Good';
    else if (total >= 50) quality = 'Fair';
    else                  quality = 'Poor';

    return ScoredSleepSession(
      start: start,
      end: end,
      durationHours: hours,
      score: total,
      source: 'Manual',
      interruptions: interruptions,
      quality: quality,
    );
  }

  // ── Auto-water calculation ────────────────────────────────────────────────

  static int autoWaterForSession(ScoredSleepSession s) {
    if (s.durationHours < 5) return 500;
    if (s.durationHours < 7) return 350;
    if (s.durationHours <= 9) return 250;
    return 300;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _emitSignal({bool autoStopped = false, String reason = ''}) {
    final label = _buildLabel();
    _controller.add(SleepSignal(
      isTracking:     _tracking,
      sleepStart:     _sleepStart,
      confidence:     _confidence,
      interruptions:  _interruptions,
      statusLabel:    label,
      autoStopped:    autoStopped,
      autoStopReason: reason,
    ));
  }

  String _buildLabel() {
    if (!_tracking) return 'Ready to track';
    if (_confidence > 0.75) return 'Sleeping soundly';
    if (_confidence > 0.5)  return 'Light sleep';
    if (_confidence > 0.25) return 'Restless';
    return 'Possible wake';
  }

  Future<void> _clearPersistedState(SharedPreferences prefs) async {
    await prefs.remove(kSleepTracking);
    await prefs.remove(kSleepStartMs);
    await prefs.remove(kSleepInterrupts);
    await prefs.remove(kSleepConfidence);
    await prefs.remove(kLastMotionMs);
  }

  bool get isTracking => _tracking;
  DateTime? get sleepStart => _sleepStart;
  double get confidence => _confidence;
  int get interruptions => _interruptions;

  void dispose() {
    _stopMotionMonitoring();
    _controller.close();
  }
}

class _MotionSample {
  final double magnitude;
  final DateTime time;
  _MotionSample(this.magnitude, this.time);
}
