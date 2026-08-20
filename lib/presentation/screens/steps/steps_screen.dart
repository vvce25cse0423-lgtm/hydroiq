import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/health_service.dart';
import '../../../data/models/app_models.dart';
import '../../../providers/app_providers.dart';

class StepsScreen extends ConsumerStatefulWidget {
  const StepsScreen({super.key});
  @override
  ConsumerState<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends ConsumerState<StepsScreen>
    with SingleTickerProviderStateMixin {

  static const _hcChannel  = MethodChannel('com.hydroiq.app/healthconnect');
  static const _defaultGoal = 10000;
  static const _syncActive  = Duration(seconds: 1);   // when actively walking
  static const _syncIdle    = Duration(seconds: 15);  // when idle (save battery)
  static const double _threshold = 0.75;
  static const int _ringSize = 30;
  static const _minGap  = Duration(milliseconds: 320);
  static const _maxGap  = Duration(milliseconds: 2100);

  // User
  String _uid = 'local';
  String get _keyBaseline    => 'pedometer_baseline_$_uid';
  String get _keyBaselineDay => 'pedometer_baseline_day_$_uid';
  String get _keyStepsToday  => 'steps_today_$_uid';
  String get _keyGoal        => 'step_goal_$_uid';
  String get _keyActiveMin   => 'active_min_today_$_uid';

  // Source
  String _dataSource    = 'initializing';
  bool   _healthAvail   = false;
  bool   _healthOk      = false;

  // Steps & goal
  int  _steps    = 0;
  int  _stepGoal = _defaultGoal;
  String _status = 'initializing';

  // Active minutes
  int      _activeMinutes   = 0;
  DateTime? _walkingStart;
  bool      _wasWalking     = false;

  // Cadence (steps/min)
  int  _cadence  = 0;
  final List<DateTime> _cadenceWindow = [];

  // Streak
  int _streak = 0;

  // Sync
  DateTime? _lastSyncTime;
  bool      _syncing      = false;
  bool      _hourlyLoaded = false;
  Timer?    _syncTimer;
  bool      _isActive = false; // true when walking

  // Sleep-aware
  bool   _isSleeping = false;
  Timer? _sleepCheckTimer;

  // Weekly — key: "YYYY_M_D"
  final Map<String, int> _weekHistory = {};
  bool _weekLoaded = false;

  // Hourly steps today (index 0–23)
  final List<int> _hourlySteps = List.filled(24, 0);

  // Milestones celebrated this session
  final Set<int> _celebrated = {};

  // Pedometer
  StreamSubscription<StepCount>?      _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;
  int _pedometerBaseline = -1;
  int _sessionRaw = -1;

  // Accelerometer fallback — gravity-compensated
  StreamSubscription<AccelerometerEvent>? _accelSub;
  int _accelSteps = 0;
  final List<double> _ring = List.filled(_ringSize, 0.0);
  int    _ringIdx     = 0;
  double _gravX = 0, _gravY = 0, _gravZ = 9.8;
  double _dynThreshold = 0.75;
  bool   _wasAbove    = false;
  DateTime? _lastPeak;
  final List<DateTime> _recentPeaks = [];
  int  _pendingSteps = 0;
  Timer? _debounceTimer;

  late AnimationController _walkAnim;
  bool _showGraph     = false;
  bool _showGoalEdit  = false;
  final _goalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _walkAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    _uid = Supabase.instance.client.auth.currentUser?.id ?? 'local';
    await _loadPersisted();
    await _loadCelebrated();
    await _loadWeekHistory();
    await _loadHourlySteps();
    await _loadStreak();
    _startSleepCheck();
    await _initHealthConnect();
    _goalController.text = _stepGoal.toString();
  }

  // ── Sleep check ──────────────────────────────────────────────────────────

  void _startSleepCheck() {
    _checkSleepState();
    _sleepCheckTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _checkSleepState());
  }

  Future<void> _checkSleepState() async {
    final prefs    = await SharedPreferences.getInstance();
    final sleeping = prefs.getBool('sleep_is_tracking') ?? false;
    if (sleeping != _isSleeping && mounted) setState(() => _isSleeping = sleeping);
  }

  // ── Active minutes tracking ───────────────────────────────────────────────

  void _onWalkingChanged(bool walking) {
    if (walking && !_wasWalking) {
      _walkingStart = DateTime.now();
    } else if (!walking && _wasWalking && _walkingStart != null) {
      final mins = DateTime.now().difference(_walkingStart!).inMinutes;
      if (mins >= 1) {
        _activeMinutes += mins;
        _persistActiveMinutes();
      }
      _walkingStart = null;
    }
    _wasWalking = walking;
  }

  Future<void> _persistActiveMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyActiveMin, _activeMinutes);
  }

  // ── Cadence ──────────────────────────────────────────────────────────────

  void _recordStep() {
    final now = DateTime.now();
    _cadenceWindow.add(now);
    // Keep only last 8 seconds for a responsive but stable cadence reading
    _cadenceWindow.removeWhere(
        (t) => now.difference(t).inMilliseconds > 8000);
    if (_cadenceWindow.length >= 4) {
      // Use median inter-step interval for noise robustness
      final intervals = <int>[];
      for (int i = 1; i < _cadenceWindow.length; i++) {
        intervals.add(_cadenceWindow[i]
            .difference(_cadenceWindow[i - 1])
            .inMilliseconds);
      }
      intervals.sort();
      final medianMs = intervals[intervals.length ~/ 2];
      if (medianMs > 0) {
        final newCadence = (60000 / medianMs).round();
        if ((newCadence - _cadence).abs() >= 2 && mounted) {
          setState(() => _cadence = newCadence.clamp(0, 250));
        }
      }
    }
  }

  // ── Streak ───────────────────────────────────────────────────────────────

  Future<void> _loadStreak() async {
    final prefs = await SharedPreferences.getInstance();
    int streak  = 0;
    final today = DateTime.now();

    // Count today if goal already met
    final todayKey = 'steps_${_uid}_${today.year}_${today.month}_${today.day}';
    final todaySteps = prefs.getInt(todayKey) ?? _steps;
    if (todaySteps >= _stepGoal) streak = 1;

    // Count backward from yesterday
    for (int i = 1; i <= 365; i++) {
      final d   = today.subtract(Duration(days: i));
      final key = 'steps_${_uid}_${d.year}_${d.month}_${d.day}';
      final s   = prefs.getInt(key) ?? 0;
      if (s >= _stepGoal) {
        streak++;
      } else {
        break;
      }
    }
    if (mounted) setState(() => _streak = streak);
  }

  // ── Goal management ───────────────────────────────────────────────────────

  Future<void> _saveGoal(int goal) async {
    final g = goal.clamp(1000, 50000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyGoal, g);
    if (mounted) setState(() => _stepGoal = g);
    _goalController.text = g.toString();
  }

  // ── Milestone celebrations ────────────────────────────────────────────────

  Future<void> _loadCelebrated() async {
    final prefs   = await SharedPreferences.getInstance();
    final dateKey = 'milestone_date_${_uid}';
    final today   = _todayKey();
    // If stored date is today, restore which milestones were already shown
    if ((prefs.getString(dateKey) ?? '') == today) {
      final stored = prefs.getStringList('milestones_shown_${_uid}_$today') ?? [];
      _celebrated.addAll(stored.map((s) => int.tryParse(s) ?? -1).where((v) => v > 0));
    } else {
      // New day — clear celebrated set and reset stored list
      _celebrated.clear();
      await prefs.setString(dateKey, today);
      await prefs.remove('milestones_shown_${_uid}_$today');
    }
  }

  void _checkMilestones() {
    final pct = (_steps / _stepGoal * 100).round();
    for (final m in [25, 50, 75, 100]) {
      if (pct >= m && !_celebrated.contains(m)) {
        _celebrated.add(m);
        _showMilestone(m);
        // Persist so it doesn't fire again after app restart
        _persistCelebrated();
      }
    }
  }

  Future<void> _persistCelebrated() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    await prefs.setStringList(
      'milestones_shown_${_uid}_$today',
      _celebrated.map((v) => v.toString()).toList());
  }

  void _showMilestone(int pct) {
    if (!mounted) return;
    final msgs = {
      25:  '🔥 25% done! Keep it up!',
      50:  '⚡ Halfway there! You\'re crushing it!',
      75:  '🌟 75%! Almost at your goal!',
      100: '🏆 Goal achieved! Amazing work today!',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msgs[pct] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: pct == 100 ? Colors.green.shade700 : AppTheme.primaryBlue,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Adaptive sync ─────────────────────────────────────────────────────────

  void _scheduleSync() {
    _syncTimer?.cancel();
    final interval = _isActive ? _syncActive : _syncIdle;
    _syncTimer = Timer.periodic(interval, (_) => _refreshHC());
  }

  void _updateActivity(bool active) {
    if (active != _isActive) {
      _isActive = active;
      _scheduleSync();
      _onWalkingChanged(active);
    }
  }

  // ── Health Connect ────────────────────────────────────────────────────────

  Future<void> _initHealthConnect() async {
    final svc = HealthService();
    _healthAvail = await svc.initialize();
    if (!_healthAvail) {
      if (mounted) setState(() => _dataSource = 'pedometer');
      await _initPedometer();
      return;
    }
    _healthOk = await svc.hasPermissions();
    if (!_healthOk) _healthOk = await svc.requestPermissions();

    if (_healthOk) {
      _initPedometer();
      await _refreshHC();
      _scheduleSync();
    } else {
      if (mounted) setState(() => _dataSource = 'pedometer');
      await _initPedometer();
    }
  }

  Future<void> _refreshHC({bool manual = false}) async {
    if (!manual && _isSleeping) return;
    if (!mounted) return;
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      if (manual) {
        try { await _hcChannel.invokeMethod('syncNow'); } catch (_) {}
      }

      int? steps;
      try {
        final r = await _hcChannel
            .invokeMethod<dynamic>('getSteps')
            .timeout(const Duration(seconds: 4));
        if (r != null) steps = (r as num).toInt();
      } catch (_) {}

      steps ??= await HealthService().getTodaySteps();

      if (steps == null) {
        final prefs = await SharedPreferences.getInstance();
        steps = prefs.getInt(_keyStepsToday);
      }

      if (steps != null && mounted) {
        final sv = steps;
        // Monotonic guard: HC can sometimes return stale values mid-session
        final applied = sv > _steps ? sv : _steps;
        setState(() {
          _steps        = applied;
          _dataSource   = 'health_connect';
          _status       = applied > 0 ? 'walking' : 'stopped';
          _lastSyncTime = DateTime.now();
          _syncing      = false;
        });
        ref.read(todayStepsProvider.notifier).update(applied);
        await _persistSteps(applied);
        _updateTodayInWeekHistory(applied);
        _updateHourlySteps(applied);
        _checkMilestones();
      } else {
        if (mounted) setState(() => _syncing = false);
      }

      // Weekly refresh (at most once per 90s)
      final prefs  = await SharedPreferences.getInstance();
      final lastWk = prefs.getInt('steps_week_refresh_$_uid') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - lastWk > 90000 || !_weekLoaded) {
        _refreshWeeklySteps();
      }
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Hourly steps ─────────────────────────────────────────────────────────

  Future<void> _loadHourlySteps() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    for (int h = 0; h < 24; h++) {
      _hourlySteps[h] = prefs.getInt('steps_hourly_${_uid}_${today}_$h') ?? 0;
    }
    if (mounted) setState(() => _hourlyLoaded = true);
  }

  void _updateHourlySteps(int totalSteps) async {
    final h     = DateTime.now().hour;
    final prefs = await SharedPreferences.getInstance();
    // Hourly is derived from difference since last hour snapshot
    final prevTotal = prefs.getInt('steps_hourly_baseline_${_uid}') ?? 0;
    final prevHour  = prefs.getInt('steps_hourly_last_hour_${_uid}') ?? h;
    if (prevHour != h) {
      // Hour changed — save what we had
      await prefs.setInt('steps_hourly_${_uid}_${_todayKey()}_$prevHour',
          totalSteps - prevTotal);
      await prefs.setInt('steps_hourly_baseline_${_uid}', totalSteps);
      await prefs.setInt('steps_hourly_last_hour_${_uid}', h);
    } else {
      final sinceHourStart = (totalSteps - prevTotal).clamp(0, totalSteps);
      if (sinceHourStart > (_hourlySteps[h])) {
        if (mounted) setState(() => _hourlySteps[h] = sinceHourStart);
        await prefs.setInt('steps_hourly_${_uid}_${_todayKey()}_$h', sinceHourStart);
      }
    }
  }

  void _updateTodayInWeekHistory(int steps) {
    final d   = DateTime.now();
    final key = '${d.year}_${d.month}_${d.day}';
    if ((_weekHistory[key] ?? 0) != steps) {
      setState(() => _weekHistory[key] = steps);
    }
  }

  Future<void> _refreshWeeklySteps() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = await _hcChannel
          .invokeMethod<Map<dynamic, dynamic>>('getWeeklySteps')
          .timeout(const Duration(seconds: 8));
      if (raw != null && raw.isNotEmpty && mounted) {
        final map = raw.map((k, v) =>
            MapEntry(k.toString(), (v as num).toInt()));
        setState(() {
          for (final e in map.entries) {
            if ((_weekHistory[e.key] ?? 0) < e.value) {
              _weekHistory[e.key] = e.value;
            }
          }
          _weekLoaded = true;
        });
        _saveWeekHistory();
        await prefs.setInt('steps_week_refresh_$_uid',
            DateTime.now().millisecondsSinceEpoch);
        return;
      }
    } catch (_) {}

    final svc   = HealthService();
    final today = DateTime.now();
    bool changed = false;
    for (int i = 6; i >= 0; i--) {
      final d     = today.subtract(Duration(days: i));
      final key   = '${d.year}_${d.month}_${d.day}';
      final count = await svc.getStepsForDate(d);
      if (count > (_weekHistory[key] ?? 0)) {
        _weekHistory[key] = count;
        changed = true;
      }
    }
    if (changed && mounted) setState(() { _weekLoaded = true; });
    _saveWeekHistory();
    await prefs.setInt('steps_week_refresh_$_uid',
        DateTime.now().millisecondsSinceEpoch);
  }

  void _saveWeekHistory() async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in _weekHistory.entries) {
      await prefs.setInt('steps_${_uid}_${e.key}', e.value);
    }
  }

  // ── Pedometer ────────────────────────────────────────────────────────────

  Future<void> _initPedometer() async {
    _stepSub?.cancel();
    _stepSub = Pedometer.stepCountStream.listen(
      (event) async {
        if (_isSleeping) return;
        final raw = event.steps;
        if (_sessionRaw < 0) {
          _sessionRaw = raw;
          if (_pedometerBaseline < 0) {
            _pedometerBaseline = raw;
            await _persistSteps(0, rawBaseline: raw);
          } else if (raw < _pedometerBaseline) {
            _pedometerBaseline = (raw - _steps).clamp(0, raw);
            await _persistSteps(_steps, rawBaseline: _pedometerBaseline);
          }
        }
        final today = (raw - _pedometerBaseline).clamp(0, 999999).toInt();
        _recordStep();
        if (mounted && _dataSource != 'health_connect') {
          final isWalking = today > _steps;
          _updateActivity(isWalking);
          final pApplied = today > _steps ? today : _steps; // monotonic
          setState(() {
            _steps        = pApplied;
            _dataSource   = 'pedometer';
            _lastSyncTime = DateTime.now();
            if (_status == 'initializing') _status = 'stopped';
          });
          ref.read(todayStepsProvider.notifier).update(today);
          await _persistSteps(today);
          _updateTodayInWeekHistory(today);
          _updateHourlySteps(today);
          _checkMilestones();
        } else if (today > _steps) {
          _updateActivity(true);
          if (mounted) setState(() { _steps = today; _lastSyncTime = DateTime.now(); }); // monotonic: only enters when today > _steps
          ref.read(todayStepsProvider.notifier).update(today);
          await _persistSteps(today);
          _updateTodayInWeekHistory(today);
          _updateHourlySteps(today);
          _checkMilestones();
        }
      },
      onError: (_) {
        if (mounted) { setState(() => _dataSource = 'accelerometer'); _initAccel(); }
      },
      cancelOnError: false,
    );
    _statusSub?.cancel();
    _statusSub = Pedometer.pedestrianStatusStream.listen(
      (e) {
        if (mounted && _dataSource != 'health_connect') {
          setState(() => _status = e.status);
          _updateActivity(e.status == 'walking');
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  // ── Accelerometer fallback (gravity-compensated) ─────────────────────────

  void _initAccel() {
    _accelSteps = _steps;
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 20))
        .listen(_onAccel, onError: (_) {
          if (mounted) setState(() => _status = 'error');
        });
  }

  // Accelerometer: track consecutive valid peaks for rhythm validation
  int _rhythmCount = 0;
  static const int _minRhythmPeaks = 3; // require 3 consistent peaks before counting

  void _onAccel(AccelerometerEvent e) {
    if (_isSleeping) return;

    // Low-pass filter to isolate gravity (alpha=0.9 — tuned for 50Hz)
    const alpha = 0.90;
    _gravX = alpha * _gravX + (1 - alpha) * e.x;
    _gravY = alpha * _gravY + (1 - alpha) * e.y;
    _gravZ = alpha * _gravZ + (1 - alpha) * e.z;

    // High-pass: linear acceleration (removes gravity)
    final lx = e.x - _gravX;
    final ly = e.y - _gravY;
    final lz = e.z - _gravZ;
    final mag = math.sqrt(lx * lx + ly * ly + lz * lz);

    // Noise gate: ignore tiny tremors & violent non-step events
    // Walking typically produces 1.5–12 m/s² peaks
    if (mag < 0.5 || mag > 20.0) {
      _wasAbove = false;
      return;
    }

    _ring[_ringIdx] = mag;
    _ringIdx = (_ringIdx + 1) % _ringSize;

    // Adaptive window: use 80th-percentile of ring to set threshold 
    // (more robust than mean for non-stationary signals)
    final sorted = List<double>.from(_ring)..sort();
    final p80 = sorted[((_ringSize * 0.80).round()).clamp(0, _ringSize - 1)];
    _dynThreshold = (p80 * 0.55).clamp(0.45, 2.2);

    final windowMean = _ring.reduce((a, b) => a + b) / _ringSize;
    final isAbove = mag > windowMean + _dynThreshold;

    if (isAbove && !_wasAbove) {
      final now = DateTime.now();
      if (_lastPeak == null || now.difference(_lastPeak!) >= _minGap) {
        _lastPeak = now;

        // Rhythm validation: check inter-peak consistency
        bool valid = true;
        if (_recentPeaks.isNotEmpty) {
          final gap = now.difference(_recentPeaks.last);
          if (gap < _minGap || gap > _maxGap) {
            valid = false;
            _rhythmCount = 0; // reset rhythm on irregular gap
          } else {
            // Check if this gap is consistent with recent rhythm (±30%)
            if (_recentPeaks.length >= 2) {
              final prevGap = _recentPeaks.last
                  .difference(_recentPeaks[_recentPeaks.length - 2])
                  .inMilliseconds;
              final ratio = gap.inMilliseconds / prevGap.clamp(1, 99999);
              if (ratio < 0.6 || ratio > 1.6) {
                _rhythmCount = (_rhythmCount - 1).clamp(0, 99);
                valid = _rhythmCount >= _minRhythmPeaks;
              } else {
                _rhythmCount++;
              }
            } else {
              _rhythmCount++;
            }
          }
        } else {
          _rhythmCount = 1;
        }

        if (valid && _rhythmCount >= _minRhythmPeaks) {
          _recentPeaks.add(now);
          if (_recentPeaks.length > 16) _recentPeaks.removeAt(0);
          _accelSteps++;
          _pendingSteps++;
          _recordStep();
          _updateActivity(true);
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 150), () {
            if (mounted && _pendingSteps > 0) {
              setState(() {
                _steps        = _accelSteps;
                _status       = 'walking';
                _dataSource   = 'accelerometer';
                _lastSyncTime = DateTime.now();
                _pendingSteps = 0;
              });
              ref.read(todayStepsProvider.notifier).update(_accelSteps);
              _updateTodayInWeekHistory(_accelSteps);
              _updateHourlySteps(_accelSteps);
              _checkMilestones();
            }
          });
          if (_accelSteps % 10 == 0) _persistSteps(_accelSteps);
        } else if (valid) {
          // Collecting rhythm — track peak but don't count yet
          _recentPeaks.add(now);
          if (_recentPeaks.length > 16) _recentPeaks.removeAt(0);
        }
      }
    } else if (!isAbove && _wasAbove) {
      // Detect stop: no peak for 4 seconds
      if (_lastPeak != null &&
          DateTime.now().difference(_lastPeak!).inMilliseconds > 4000) {
        if (mounted && _status == 'walking') {
          setState(() => _status = 'stopped');
          _updateActivity(false);
          _persistSteps(_accelSteps);
        }
        _rhythmCount = 0;
      }
    }
    _wasAbove = isAbove;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  String _todayWeekKey() {
    final n = DateTime.now();
    return '${n.year}_${n.month}_${n.day}';
  }

  Future<void> _loadPersisted() async {
    final prefs    = await SharedPreferences.getInstance();
    final savedDay = prefs.getString(_keyBaselineDay) ?? '';
    final today    = _todayKey();

    _stepGoal      = prefs.getInt(_keyGoal) ?? _defaultGoal;
    _activeMinutes = prefs.getInt(_keyActiveMin) ?? 0;

    if (savedDay == today) {
      final s = prefs.getInt(_keyStepsToday) ?? 0;
      if (mounted) setState(() => _steps = s);
      ref.read(todayStepsProvider.notifier).update(s);
      _pedometerBaseline = prefs.getInt(_keyBaseline) ?? -1;
    } else {
      // Archive previous day
      if (savedDay.isNotEmpty) {
        final parts = savedDay.split('-');
        if (parts.length == 3) {
          final hk = 'steps_${_uid}_${parts[0]}_${int.tryParse(parts[1]) ?? 1}_${int.tryParse(parts[2]) ?? 1}';
          await prefs.setInt(hk, prefs.getInt(_keyStepsToday) ?? 0);
        }
      }
      await prefs.setString(_keyBaselineDay, today);
      await prefs.setInt(_keyStepsToday, 0);
      await prefs.setInt(_keyBaseline, -1);
      await prefs.setInt(_keyActiveMin, 0);
      _pedometerBaseline = -1;
      _activeMinutes     = 0;
    }
  }

  Future<void> _persistSteps(int steps, {int? rawBaseline}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaselineDay, _todayKey());
    await prefs.setInt(_keyStepsToday, steps);
    if (rawBaseline != null) await prefs.setInt(_keyBaseline, rawBaseline);
    await prefs.setInt('steps_${_uid}_${_todayWeekKey()}', steps);
    // Update steps water addon (0.04ml per step, capped 1200ml) — auto-resets next day
    final stepsWaterMl = (steps * 0.04).round().clamp(0, 1200);
    await UserProfileNotifier.setAddon(
        UserProfileNotifier.kAddonSteps, stepsWaterMl);
    if (mounted) ref.invalidate(todayAddonProvider);
    // ── Sync to Supabase so health reports can fetch real step data ──────
    try {
      final user = ref.read(supabaseServiceProvider).currentUser;
      if (user != null && steps > 0) {
        final today = DateTime.now();
        final weightKg = ref.read(userProfileProvider).valueOrNull?.weightKg ?? 70.0;
        final distance = steps * 0.000762; // avg stride ~76.2cm
        final calories = steps * 0.045 * (weightKg / 70.0);
        await ref.read(supabaseServiceProvider).upsertStepLog(StepLog(
          id:             '${user.id}_${today.year}${today.month.toString().padLeft(2,'0')}${today.day.toString().padLeft(2,'0')}',
          userId:         user.id,
          steps:          steps,
          distanceKm:     double.parse(distance.toStringAsFixed(2)),
          caloriesBurned: double.parse(calories.toStringAsFixed(1)),
          date:           DateTime(today.year, today.month, today.day),
        ));
      }
    } catch (_) {}
  }

  Future<void> _loadWeekHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d   = today.subtract(Duration(days: i));
      final key = '${d.year}_${d.month}_${d.day}';
      _weekHistory[key] = prefs.getInt('steps_${_uid}_$key') ?? 0;
    }
    _weekHistory[_todayWeekKey()] = _steps;
    if (mounted) setState(() { _weekLoaded = true; });
  }

  // ── Computed metrics ──────────────────────────────────────────────────────

  double get _distanceKm {
    final profile = ref.read(userProfileProvider).valueOrNull;
    final heightM = (profile?.heightCm ?? 170) / 100.0;
    // Stride length varies with pace: cadence-aware stride
    final baseStride = heightM * 0.413;
    final cadenceBoost = _cadence > 120 ? 1.15 : _cadence > 100 ? 1.07 : 1.0;
    return _steps * baseStride * cadenceBoost / 1000.0;
  }

  double get _calories {
    final profile = ref.read(userProfileProvider).valueOrNull;
    final weightKg = profile?.weightKg ?? 70.0;
    // MET-based: walking=3.5, brisk=4.5, power=5.5, running=8.0
    final met = _cadence <= 0 ? 3.5
        : _cadence < 100 ? 3.5
        : _cadence < 120 ? 4.5
        : _cadence < 140 ? 5.5 : 8.0;
    final durationHours = _activeMinutes / 60.0;
    final activeCalories = met * weightKg * durationHours;
    // Add resting calories for steps outside active periods
    final stepCalories = _steps * 0.045 * (weightKg / 70.0);
    return (activeCalories + stepCalories).clamp(0, 9999);
  }

  // Estimated speed km/h based on cadence and stride
  double get _speedKmh {
    if (_cadence <= 0) return 0.0;
    final profile = ref.read(userProfileProvider).valueOrNull;
    final heightM = (profile?.heightCm ?? 170) / 100.0;
    final stride = heightM * 0.413 * (_cadence > 120 ? 1.15 : _cadence > 100 ? 1.07 : 1.0);
    // speed = cadence (steps/min) × stride (m/step) × 60 / 1000
    return (_cadence * stride * 60 / 1000).clamp(0, 30);
  }

  String get _paceLabel {
    if (_cadence <= 0)   return '—';
    if (_cadence < 70)   return 'Strolling';
    if (_cadence < 90)   return 'Slow walk';
    if (_cadence < 110)  return 'Easy walk';
    if (_cadence < 125)  return 'Brisk walk';
    if (_cadence < 145)  return 'Power walk';
    if (_cadence < 165)  return 'Jogging';
    return 'Running';
  }

  // Steps remaining to goal
  int get _stepsRemaining => (_stepGoal - _steps).clamp(0, _stepGoal);

  // Estimated time to reach goal (minutes) based on current cadence
  int get _estMinutesRemaining {
    if (_cadence <= 0 || _stepsRemaining <= 0) return 0;
    return (_stepsRemaining / _cadence).ceil();
  }

  // Weekly stats
  int get _weekTotal   => _weekHistory.values.fold(0, (s, v) => s + v);
  int get _weekAvg     => _weekHistory.values.isEmpty ? 0
      : (_weekTotal / _weekHistory.values.where((v) => v > 0).length.clamp(1, 7)).round();
  int get _weekBest    => _weekHistory.values.isEmpty ? 0 : _weekHistory.values.reduce(math.max);
  int get _weekGoalDays => _weekHistory.values.where((v) => v >= _stepGoal).length;

  // ── Dispose ───────────────────────────────────────────────────────────────

  // ── Monotonic step application (prevents backwards-jump fluctuation) ────────
  // Steps can only go up during a session. A drop only happens on a new day
  // (detected by _loadPersisted / _initHealthConnect resetting _steps to 0).
  void _applySteps(int candidate) {
    if (candidate > _steps) {
      _steps = candidate;
    }
  }

  @override
  void dispose() {
    _walkAnim.dispose();
    _syncTimer?.cancel();
    _sleepCheckTimer?.cancel();
    _stepSub?.cancel();
    _statusSub?.cancel();
    _accelSub?.cancel();
    _debounceTimer?.cancel();
    _goalController.dispose();
    // Flush active minutes on dispose
    if (_wasWalking && _walkingStart != null) {
      _activeMinutes += DateTime.now().difference(_walkingStart!).inMinutes;
      _persistActiveMinutes();
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress  = (_steps / _stepGoal).clamp(0.0, 1.0);
    final isWalking = _status == 'walking';
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final today     = DateTime.now();

    final barData = List.generate(7, (i) {
      final d   = today.subtract(Duration(days: 6 - i));
      final key = '${d.year}_${d.month}_${d.day}';
      return (i == 6 ? _steps : (_weekHistory[key] ?? 0)).toDouble();
    });
    final maxY = barData.fold<double>((_stepGoal * 1.1), math.max) * 1.15;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF5F7FF),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          floating: true,
          title: const Text('Step Tracker',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            // Streak badge
            if (_streak > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.4))),
                child: Text('🔥 $_streak day streak',
                    style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            _SyncButton(
              syncing: _syncing,
              lastSyncTime: _lastSyncTime,
              onTap: () async {
                if (_syncing) return;
                await _refreshHC(manual: true);
                await _loadStreak();
              },
            ),
          ],
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [

            // ── Main hero card ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: _isSleeping
                      ? [const Color(0xFF4A148C), const Color(0xFF7B1FA2)]
                      : progress >= 1.0
                          ? [const Color(0xFF1B5E20), const Color(0xFF43A047)]
                          : [const Color(0xFF0D47A1), const Color(0xFF1976D2)]),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(
                    color: (progress >= 1.0
                        ? Colors.green : AppTheme.primaryBlue).withOpacity(0.4),
                    blurRadius: 24, offset: const Offset(0, 8))]),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  // Animated figure
                  AnimatedBuilder(
                    animation: _walkAnim,
                    builder: (_, __) => Transform.translate(
                      offset: isWalking
                          ? Offset(0, -5 * _walkAnim.value)
                          : Offset.zero,
                      child: Text(
                          _isSleeping ? '😴' : isWalking ? '🚶' : '🧍',
                          style: const TextStyle(fontSize: 44)),
                    ),
                  ),
                  // Source + cadence
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    _SourceBadge(
                        source: _dataSource, status: _status,
                        isSleeping: _isSleeping),
                    if (_cadence > 0 && !_isSleeping) ...[ 
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text('$_cadence spm · $_paceLabel',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          '${_speedKmh.toStringAsFixed(1)} km/h'
                          '${_stepsRemaining > 0 && _estMinutesRemaining > 0 ? ' · ~${_estMinutesRemaining}m to goal' : ''}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10,
                              fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ]),
                ]),

                const SizedBox(height: 12),

                // Steps number
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Text('$_steps',
                      key: ValueKey(_steps),
                      style: const TextStyle(
                          fontSize: 68, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: -2)),
                ),
                Text('STEPS TODAY', style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w500)),

                if (_isSleeping) ...[ 
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('😴 Steps paused during sleep',
                        style: TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w600))),
                ] else ...[ 
                  const SizedBox(height: 18),

                  // Progress bar
                  Stack(children: [
                    Container(
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(5))),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      height: 10,
                      width: (MediaQuery.of(context).size.width - 92) *
                          progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: progress >= 1.0
                            ? [Colors.amber, Colors.orange]
                            : [Colors.white, Colors.white70]),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [BoxShadow(
                            color: Colors.white.withOpacity(0.35),
                            blurRadius: 6)]),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('$_steps / $_stepGoal steps',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 12)),
                    // Goal edit button
                    GestureDetector(
                      onTap: () => setState(() => _showGoalEdit = !_showGoalEdit),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${(progress * 100).round()}%  ✏️',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),

                  if (progress >= 1.0)
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('🏆 Daily goal achieved! Excellent!',
                            style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.w700,
                                fontSize: 13))),
                ],
              ]),
            ),

            // ── Goal editor ───────────────────────────────────────────────
            if (_showGoalEdit) ...[ 
              const SizedBox(height: 14),
              _GoalEditorCard(
                goal: _stepGoal,
                onSave: (g) {
                  _saveGoal(g);
                  setState(() => _showGoalEdit = false);
                },
                isDark: isDark,
              ),
            ],

            const SizedBox(height: 16),

            // ── Stats row ─────────────────────────────────────────────────
            Row(children: [
              Expanded(child: _StatCard(
                  emoji: '🔥',
                  value: '${_calories.toStringAsFixed(0)}',
                  unit: 'kcal',
                  label: 'Calories',
                  gradient: [const Color(0xFFFF6B35), const Color(0xFFFF8E53)])),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                  emoji: '📍',
                  value: _distanceKm.toStringAsFixed(2),
                  unit: 'km',
                  label: 'Distance',
                  gradient: [const Color(0xFF1565C0), const Color(0xFF29B6F6)])),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                  emoji: '⏱️',
                  value: '${_activeMinutes + (_wasWalking && _walkingStart != null ? DateTime.now().difference(_walkingStart!).inMinutes : 0)}',
                  unit: 'min',
                  label: 'Active',
                  gradient: [const Color(0xFF2E7D32), const Color(0xFF66BB6A)])),
            ]),

            const SizedBox(height: 16),

            // ── Weekly summary card ────────────────────────────────────────
            _WeeklySummaryCard(
              weekTotal:    _weekTotal,
              weekAvg:      _weekAvg,
              weekBest:     _weekBest,
              weekGoalDays: _weekGoalDays,
              stepGoal:     _stepGoal,
              isDark:       isDark,
            ),

            const SizedBox(height: 14),

            // ── 7-Day bar chart ───────────────────────────────────────────
            _ExpandableSection(
              title: '7-Day Steps',
              emoji: '📊',
              subtitle: _weekLoaded
                  ? '${barData.where((v) => v > 0).length} active days'
                  : 'Loading…',
              expanded: _showGraph,
              isDark: isDark,
              onToggle: () => setState(() => _showGraph = !_showGraph),
              child: Container(
                height: 220,
                padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
                child: _weekLoaded
                    ? BarChart(BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) =>
                                AppTheme.primaryBlue.withOpacity(0.9),
                            getTooltipItem: (group, _, rod, __) =>
                                BarTooltipItem(
                              '${rod.toY.toInt()} steps',
                              const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, reservedSize: 44,
                              getTitlesWidget: (v, _) => Text(
                                  v >= 1000
                                      ? '${(v / 1000).toStringAsFixed(0)}k'
                                      : v.toInt().toString(),
                                  style: TextStyle(fontSize: 10,
                                      color: isDark
                                          ? Colors.white60 : Colors.black45)))),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, reservedSize: 28,
                              getTitlesWidget: (v, _) {
                                final d = today.subtract(
                                    Duration(days: 6 - v.toInt()));
                                const days = ['M','T','W','T','F','S','S'];
                                final isT = v.toInt() == 6;
                                return Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: isT
                                          ? AppTheme.primaryBlue
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(days[(d.weekday - 1) % 7],
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isT
                                              ? Colors.white
                                              : isDark
                                                  ? Colors.white60
                                                  : Colors.black45)),
                                );
                              })),
                          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                            show: true, drawVerticalLine: false,
                            horizontalInterval: _stepGoal / 2,
                            getDrawingHorizontalLine: (v) {
                              final isGoalLine = (v - _stepGoal).abs() < 50;
                              return FlLine(
                                  color: isGoalLine
                                      ? Colors.orange.withOpacity(0.5)
                                      : Colors.grey.withOpacity(0.1),
                                  strokeWidth: isGoalLine ? 1.5 : 1,
                                  dashArray: isGoalLine ? [6, 4] : null);
                            }),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(7, (i) {
                          final isT     = i == 6;
                          final val     = barData[i];
                          final hitGoal = val >= _stepGoal;

                          // Each day gets a distinct color; today is vivid blue
                          // Goal-hit days turn green regardless of position
                          const dayColors = <List<Color>>[
                            [Color(0xFF880E4F), Color(0xFFF06292)], // Mon – pink
                            [Color(0xFF4A148C), Color(0xFFCE93D8)], // Tue – purple
                            [Color(0xFF1A237E), Color(0xFF7986CB)], // Wed – indigo
                            [Color(0xFF006064), Color(0xFF4DD0E1)], // Thu – cyan
                            [Color(0xFFE65100), Color(0xFFFFB74D)], // Fri – orange
                            [Color(0xFF1B5E20), Color(0xFF81C784)], // Sat – green
                            [Color(0xFF0D47A1), Color(0xFF29B6F6)], // Sun/Today – blue
                          ];

                          final colors = hitGoal
                              ? [const Color(0xFF1B5E20), const Color(0xFF66BB6A)]
                              : dayColors[i];

                          return BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: val > 0 ? val : 0.01,
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: isT
                                    ? [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]
                                    : colors),
                              width: isT ? 28 : 18,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8)),
                              backDrawRodData: BackgroundBarChartRodData(
                                  show: true, toY: maxY,
                                  color: Colors.grey.withOpacity(0.05)),
                            ),
                          ]);
                        }),
                      ))
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),

            const SizedBox(height: 14),

            // ── Data source card ──────────────────────────────────────────
            _DataSourceCard(
                dataSource: _dataSource, isDark: isDark),

            // ── Hydration tip ─────────────────────────────────────────────
            if (_steps > 0) ...[ 
              const SizedBox(height: 14),
              _HydrationTip(steps: _steps, isDark: isDark),
            ],

          ]),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]),
    );
  }
}

// ── Goal editor card ──────────────────────────────────────────────────────────

class _GoalEditorCard extends StatefulWidget {
  final int goal;
  final ValueChanged<int> onSave;
  final bool isDark;
  const _GoalEditorCard({required this.goal, required this.onSave, required this.isDark});
  @override State<_GoalEditorCard> createState() => _GoalEditorCardState();
}
class _GoalEditorCardState extends State<_GoalEditorCard> {
  late int _val;
  @override void initState() { super.initState(); _val = widget.goal; }

  String get _motivationLabel {
    if (_val >= 15000) return '🏃 Elite athlete — incredible!';
    if (_val >= 10000) return '🏆 Active lifestyle — great choice!';
    if (_val >= 7500)  return "💪 Above average — you're doing well!";
    if (_val >= 5000)  return '🚶 Moderate activity — solid start!';
    if (_val >= 3000)  return '👣 Light activity — every step counts!';
    return '🌱 Gentle start — build up gradually!';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Set Daily Step Goal',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 14),
        // Quick preset chips
        Wrap(
          spacing: 7, runSpacing: 6,
          children: [3000, 5000, 6000, 7500, 8000, 10000, 12000, 15000, 20000].map((p) =>
            GestureDetector(
              onTap: () => setState(() => _val = p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _val == p ? AppTheme.primaryBlue : AppTheme.primaryBlue.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _val == p ? AppTheme.primaryBlue : AppTheme.primaryBlue.withOpacity(0.25))),
                child: Text(
                  p >= 1000 ? '${p ~/ 1000}k' : '$p',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12,
                      color: _val == p ? Colors.white : AppTheme.primaryBlue)),
              ),
            )
          ).toList()),
        const SizedBox(height: 14),
        // Fine-tune row
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _GoalBtn(label: '-1k', onTap: () => setState(() => _val = (_val - 1000).clamp(1000, 50000))),
          _GoalBtn(label: '-500', onTap: () => setState(() => _val = (_val - 500).clamp(1000, 50000))),
          Expanded(child: Center(
            child: Column(children: [
              Text(
                _val >= 1000 ? '${(_val / 1000).toStringAsFixed(_val % 1000 == 0 ? 0 : 1)}k' : '$_val',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
              Text('steps / day', style: TextStyle(fontSize: 11,
                  color: widget.isDark ? Colors.white54 : Colors.black45)),
            ]),
          )),
          _GoalBtn(label: '+500', onTap: () => setState(() => _val = (_val + 500).clamp(1000, 50000))),
          _GoalBtn(label: '+1k',  onTap: () => setState(() => _val = (_val + 1000).clamp(1000, 50000))),
        ]),
        const SizedBox(height: 8),
        // Motivational label
        Center(child: Text(_motivationLabel,
            style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w600))),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => widget.onSave(_val),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
            child: const Text('Save Goal',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

class _GoalBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GoalBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppTheme.primaryBlue)),
    ),
  );
}

// ── Weekly summary card ───────────────────────────────────────────────────────

class _WeeklySummaryCard extends StatelessWidget {
  final int weekTotal, weekAvg, weekBest, weekGoalDays, stepGoal;
  final bool isDark;
  const _WeeklySummaryCard({
    required this.weekTotal, required this.weekAvg, required this.weekBest,
    required this.weekGoalDays, required this.stepGoal, required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    final weeklyGoal = stepGoal * 7;
    final weekProgress = weekTotal / weeklyGoal.clamp(1, 999999);
    final dayOfWeek = DateTime.now().weekday; // 1=Mon … 7=Sun
    // Project weekly total based on current avg * 7
    final projectedTotal = weekAvg > 0 ? (weekAvg * 7) : weekTotal;
    final onTrack = projectedTotal >= weeklyGoal;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('This Week', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (onTrack ? Colors.green : Colors.orange).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
            child: Text(
              onTrack ? '✅ On track' : '📊 Projected: ${(projectedTotal / 1000).toStringAsFixed(1)}k',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: onTrack ? Colors.green.shade700 : Colors.orange.shade800)),
          ),
        ]),
        const SizedBox(height: 12),
        // Weekly progress bar
        Stack(children: [
          Container(height: 8,
              decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            height: 8,
            width: (MediaQuery.of(context).size.width - 72) * weekProgress.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: onTrack
                  ? [const Color(0xFF2E7D32), const Color(0xFF66BB6A)]
                  : [const Color(0xFFE65100), const Color(0xFFFF9800)]),
              borderRadius: BorderRadius.circular(4)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Day $dayOfWeek of 7 · ${(weekProgress * 100).round()}% of weekly goal',
          style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _WeekStat('Total', '${(weekTotal / 1000).toStringAsFixed(1)}k', '🦵')),
          Expanded(child: _WeekStat('Daily Avg', '${(weekAvg / 1000).toStringAsFixed(1)}k', '📈')),
          Expanded(child: _WeekStat('Best Day', '${(weekBest / 1000).toStringAsFixed(1)}k', '🏅')),
          Expanded(child: _WeekStat('Goals Hit', '$weekGoalDays/7', '🎯')),
        ]),
      ]),
    );
  }
}

class _WeekStat extends StatelessWidget {
  final String label, value, emoji;
  const _WeekStat(this.label, this.value, this.emoji);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 20)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}

// ── Expandable section ────────────────────────────────────────────────────────

class _ExpandableSection extends StatelessWidget {
  final String title, emoji, subtitle;
  final bool expanded, isDark;
  final VoidCallback onToggle;
  final Widget child;
  const _ExpandableSection({
    required this.title, required this.emoji, required this.subtitle,
    required this.expanded, required this.isDark,
    required this.onToggle, required this.child,
  });
  @override
  Widget build(BuildContext context) => Column(children: [
    GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text(emoji, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppTheme.primaryBlue),
        ]),
      ),
    ),
    if (expanded) ...[ 
      const SizedBox(height: 10),
      child,
    ],
  ]);
}

// ── Hourly chart ──────────────────────────────────────────────────────────────

class _HourlyChart extends StatelessWidget {
  final List<int> hourlySteps;
  final int currentHour;
  final bool isDark;
  const _HourlyChart({required this.hourlySteps, required this.currentHour, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final maxVal = hourlySteps.isEmpty ? 1 : hourlySteps.reduce(math.max).clamp(1, 999999);
    return Container(
      height: 140,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Steps by Hour',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54)),
          Text('Total: ${hourlySteps.fold(0, (a, b) => a + b)} steps',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        const SizedBox(height: 8),
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(24, (h) {
            final val     = hourlySteps[h];
            final heightF = maxVal > 0 ? val / maxVal : 0.0;
            final isNow   = h == currentHour;
            final isPast  = h < currentHour;
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '${_fmtHour(h)}: $val steps',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: (heightF * 70).clamp(2, 70),
                    decoration: BoxDecoration(
                      color: isNow
                          ? AppTheme.primaryBlue
                          : isPast
                              ? AppTheme.primaryBlue.withOpacity(0.45)
                              : Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (h % 6 == 0)
                    Text(_fmtHour(h),
                        style: TextStyle(fontSize: 8,
                            color: isDark ? Colors.white38 : Colors.black26)),
                ]),
              ),
            ));
          }),
        )),
      ]),
    );
  }
  String _fmtHour(int h) => h == 0 ? '12a' : h < 12 ? '${h}a' : h == 12 ? '12p' : '${h - 12}p';
}

// ── Data source card ──────────────────────────────────────────────────────────

class _DataSourceCard extends StatelessWidget {
  final String dataSource;
  final bool isDark;
  const _DataSourceCard({required this.dataSource, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
            color: dataSource == 'health_connect'
                ? Colors.green.withOpacity(0.1)
                : AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(
            dataSource == 'health_connect' ? '❤️'
                : dataSource == 'pedometer' ? '👟' : '📡',
            style: const TextStyle(fontSize: 20)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          dataSource == 'health_connect' ? 'Health Connect'
              : dataSource == 'pedometer' ? 'Hardware Pedometer'
              : dataSource == 'accelerometer' ? 'Motion Sensor'
              : 'Initializing…',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(
          dataSource == 'health_connect'
              ? 'Most accurate · Adaptive sync'
              : dataSource == 'pedometer'
                  ? 'Hardware chip · Real-time steps'
                  : 'Gravity-compensated · Keep phone in pocket',
          style: TextStyle(fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45)),
      ])),
    ]),
  );
}

// ── Hydration tip ─────────────────────────────────────────────────────────────

class _HydrationTip extends StatelessWidget {
  final int steps;
  final bool isDark;
  const _HydrationTip({required this.steps, required this.isDark});

  String get _tip {
    // 1ml per step is the general guideline; scale with intensity
    final extraMl = (steps * 0.04).round().clamp(0, 1200);
    if (steps >= 15000) return '🏃 Intense day! Drink +${extraMl}ml extra and replenish electrolytes.';
    if (steps >= 10000) return '🏆 Goal hit! Drink +${extraMl}ml to fully recover. Great work!';
    if (steps >= 7500)  return '💪 Almost there! +${extraMl}ml water boost recommended today.';
    if (steps >= 5000)  return '🚶 Good progress! Drink +${extraMl}ml extra to stay hydrated.';
    if (steps >= 2500)  return '👟 Keep moving! Every 2,500 steps → +100ml water needed.';
    return '💧 Every step counts! Stay hydrated — aim for 250ml per hour while active.';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        AppTheme.primaryBlue.withOpacity(0.08),
        const Color(0xFF29B6F6).withOpacity(0.04)]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2))),
    child: Row(children: [
      const Text('💧', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Expanded(child: Text(_tip,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]),
  );
}

// ── Sync button ───────────────────────────────────────────────────────────────

class _SyncButton extends StatefulWidget {
  final bool syncing;
  final DateTime? lastSyncTime;
  final VoidCallback onTap;
  const _SyncButton({required this.syncing, required this.lastSyncTime, required this.onTap});

  @override
  State<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<_SyncButton> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick every second so the "Xs ago" label increments live
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _label() {
    if (widget.syncing) return 'Syncing…';
    if (widget.lastSyncTime == null) return 'Sync';
    final diff = DateTime.now().difference(widget.lastSyncTime!);
    if (diff.inSeconds < 60)  return 'Synced · ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60)  return 'Synced · ${diff.inMinutes}m ago';
    return 'Sync';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: GestureDetector(
      onTap: widget.syncing ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.syncing
                ? [Colors.grey.shade500, Colors.grey.shade600]
                : [const Color(0xFF1565C0), const Color(0xFF1E88E5)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: widget.syncing ? [] : [BoxShadow(
              color: const Color(0xFF1565C0).withOpacity(0.3),
              blurRadius: 6, offset: const Offset(0, 3))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          widget.syncing
              ? const SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_rounded, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(_label(), style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}

// ── Source badge ──────────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final String source, status;
  final bool isSleeping;
  const _SourceBadge({required this.source, required this.status, required this.isSleeping});
  @override
  Widget build(BuildContext context) {
    String label; Color color;
    if (isSleeping) {
      label = '😴 Sleeping'; color = Colors.purpleAccent;
    } else if (source == 'health_connect') {
      label = '❤️ HC Live'; color = Colors.greenAccent;
    } else if (source == 'pedometer') {
      label = status == 'walking' ? '🚶 Walking' : '🧍 Idle';
      color = status == 'walking' ? Colors.greenAccent : Colors.white70;
    } else if (source == 'accelerometer') {
      label = status == 'walking' ? '📡 Walking' : '📡 Ready';
      color = Colors.amberAccent;
    } else {
      label = '⏳ Starting…'; color = Colors.white60;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(label, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

// ── Hourly Steps Card ─────────────────────────────────────────────────────────
class _HourlyStepsCard extends StatelessWidget {
  final Map<int, int> hourlySteps;
  final bool isDark;
  const _HourlyStepsCard({required this.hourlySteps, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (hourlySteps.isEmpty) return const SizedBox.shrink();

    final currentHour = DateTime.now().hour;
    final maxSteps = hourlySteps.values.fold(0, math.max).clamp(1, 999999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⏰', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Text('Today by Hour',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const Spacer(),
          Text('${hourlySteps.values.fold(0, (a, b) => a + b)} steps',
              style: TextStyle(fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(currentHour + 1, (h) {
              final steps = hourlySteps[h] ?? 0;
              final frac  = steps / maxSteps;
              final isNow = h == currentHour;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Tooltip(
                    message: '${_hourLabel(h)}: $steps steps',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          height: (frac * 55).clamp(2.0, 55.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end:   Alignment.topCenter,
                              colors: isNow
                                  ? [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]
                                  : [
                                      const Color(0xFF7B1FA2).withOpacity(0.5),
                                      const Color(0xFFCE93D8).withOpacity(0.8),
                                    ]),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                        if (h % 4 == 0 || isNow) ...[
                          const SizedBox(height: 3),
                          Text(_hourLabel(h),
                              style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: isNow ? FontWeight.w700 : FontWeight.w400,
                                  color: isNow
                                      ? AppTheme.primaryBlue
                                      : (isDark ? Colors.white38 : Colors.black38))),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }

  static String _hourLabel(int h) {
    if (h == 0)  return '12a';
    if (h < 12)  return '${h}a';
    if (h == 12) return '12p';
    return '${h - 12}p';
  }
}

class _StatCard extends StatelessWidget {
  final String emoji, value, unit, label;
  final List<Color> gradient;
  const _StatCard({required this.emoji, required this.value, required this.unit,
      required this.label, required this.gradient});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(10)),
          child: Text(emoji, style: const TextStyle(fontSize: 18))),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 20,
              color: gradient.first, letterSpacing: -0.5)),
          const SizedBox(width: 2),
          Padding(padding: const EdgeInsets.only(bottom: 2),
              child: Text(unit, style: TextStyle(
                  fontSize: 11, color: gradient.first.withOpacity(0.8),
                  fontWeight: FontWeight.w600))),
        ]),
        Text(label, style: TextStyle(fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45)),
      ]),
    );
  }
}
