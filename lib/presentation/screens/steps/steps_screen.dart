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
import '../../../providers/app_providers.dart';

class StepsScreen extends ConsumerStatefulWidget {
  const StepsScreen({super.key});
  @override
  ConsumerState<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends ConsumerState<StepsScreen>
    with SingleTickerProviderStateMixin {

  static const _hcChannel = MethodChannel('com.hydroiq.app/healthconnect');
  static const int _dailyGoal = 10000;
  static const _minGap  = Duration(milliseconds: 350);
  static const double _threshold = 0.75;
  static const int _ringSize = 25;

  // User isolation
  String _uid = 'local';
  String get _keyBaseline    => 'pedometer_baseline_$_uid';
  String get _keyBaselineDay => 'pedometer_baseline_day_$_uid';
  String get _keyStepsToday  => 'steps_today_$_uid';

  // Source
  String _dataSource = 'initializing';
  bool _healthAvailable = false;
  bool _healthPermitted = false;

  // Steps
  int _steps = 0;
  String _status = 'initializing';

  // Sync
  DateTime? _lastSyncTime;
  bool _syncing = false;

  // Sleep-aware
  bool _isSleeping = false;
  Timer? _sleepCheckTimer;

  // Weekly
  Map<String, int> _weekHistory = {};

  // Pedometer fallback
  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;
  int _pedometerBaseline = -1;
  int _sessionRaw = -1;

  // Accelerometer fallback - zero-crossing
  StreamSubscription<AccelerometerEvent>? _accelSub;
  int _accelSteps = 0;
  final List<double> _ring = List.filled(_ringSize, 9.8);
  int _ringIdx = 0;
  double _runningMean = 9.8;
  bool _wasAbove = false;
  DateTime? _lastPeak;
  final List<DateTime> _recentPeaks = [];
  int _stepsCadence = 0;

  Timer? _hcRefreshTimer;
  bool _showGraph = false;
  late AnimationController _walkAnim;

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
    await _loadWeekHistory();
    _startSleepCheck();
    await _initHealthConnect();
  }

  // ── Sleep check ───────────────────────────────────────────────────────────
  void _startSleepCheck() {
    _checkSleepState();
    _sleepCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkSleepState());
  }

  Future<void> _checkSleepState() async {
    final prefs = await SharedPreferences.getInstance();
    final sleeping = prefs.getBool('sleep_is_tracking') ?? false;
    if (sleeping != _isSleeping && mounted) setState(() => _isSleeping = sleeping);
  }

  // ── Health Connect ────────────────────────────────────────────────────────
  Future<void> _initHealthConnect() async {
    final svc = HealthService();
    _healthAvailable = await svc.initialize();
    if (!_healthAvailable) {
      if (mounted) setState(() => _dataSource = 'pedometer');
      await _initPedometer();
      return;
    }
    _healthPermitted = await svc.hasPermissions();
    if (!_healthPermitted) _healthPermitted = await svc.requestPermissions();
    if (_healthPermitted) {
      _initPedometer(); // parallel pedometer as immediate display
      await _refreshHC();
      // 1-second refresh while screen is open
      _hcRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshHC());
    } else {
      if (mounted) setState(() => _dataSource = 'pedometer');
      await _initPedometer();
    }
  }

  Future<void> _refreshHC({bool manual = false}) async {
    // Manual sync always allowed; auto-sync skips during sleep
    if (!manual && _isSleeping) return;
    if (mounted) setState(() => _syncing = true);
    try {
      int? steps;

      // Try native Kotlin HC channel first
      try {
        final r = await _hcChannel.invokeMethod<dynamic>('getSteps')
            .timeout(const Duration(seconds: 5));
        if (r != null) steps = (r as num).toInt();
      } catch (_) {}

      // Fallback: Flutter health package
      if (steps == null) steps = await HealthService().getTodaySteps();

      // Fallback: use persisted pedometer count
      if (steps == null) {
        final prefs = await SharedPreferences.getInstance();
        steps = prefs.getInt(_keyStepsToday);
      }

      if (steps != null && mounted) {
        final sv = steps; // non-nullable alias
        setState(() {
          _steps        = sv;
          _dataSource   = _healthPermitted ? 'health_connect' : _dataSource;
          _status       = sv > 0 ? 'walking' : 'stopped';
          _lastSyncTime = DateTime.now();
          _syncing      = false;
        });
        ref.read(todayStepsProvider.notifier).update(sv);
        await _persistSteps(sv);

        // Update weekly history non-blocking
        HealthService().getWeeklySteps().then((week) {
          if (!mounted) return;
          final mapped = <String, int>{};
          week.forEach((dateKey, count) {
            final k = dateKey.startsWith('steps_')
                ? dateKey
                : 'steps_${_uid}_$dateKey';
            mapped[k] = count;
          });
          setState(() => _weekHistory = mapped);
          _saveWeekHistory(mapped);
        }).catchError((_) {});
      } else {
        if (mounted) setState(() => _syncing = false);
      }
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _saveWeekHistory(Map<String, int> data) async {
    final prefs = await SharedPreferences.getInstance();
    data.forEach((k, v) => prefs.setInt(k, v));
  }

  // ── Pedometer ─────────────────────────────────────────────────────────────
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
        // Only update UI from pedometer if HC is not active
        if (mounted && _dataSource != 'health_connect') {
          setState(() {
            _steps = today; _dataSource = 'pedometer';
            _lastSyncTime = DateTime.now();
            if (_status == 'initializing') _status = 'stopped';
          });
          ref.read(todayStepsProvider.notifier).update(today);
          await _persistSteps(today);
        } else if (today > _steps) {
          // HC active but pedometer has more steps — use higher value
          if (mounted) setState(() { _steps = today; _lastSyncTime = DateTime.now(); });
          ref.read(todayStepsProvider.notifier).update(today);
          await _persistSteps(today);
        }
      },
      onError: (_) {
        if (mounted) { setState(() => _dataSource = 'accelerometer'); _initAccel(); }
      },
      cancelOnError: false,
    );
    _statusSub?.cancel();
    _statusSub = Pedometer.pedestrianStatusStream.listen(
      (e) { if (mounted && _dataSource != 'health_connect') setState(() => _status = e.status); },
      onError: (_) {}, cancelOnError: false,
    );
  }

  // ── Accelerometer fallback ────────────────────────────────────────────────
  void _initAccel() {
    _accelSteps = _steps;
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(_onAccel, onError: (_) { if (mounted) setState(() => _status = 'error'); });
  }

  // Debounce: confirmed steps pending UI update
  int _pendingSteps = 0;
  Timer? _debounceTimer;

  // Debounce timer to batch UI updates

  void _onAccel(AccelerometerEvent e) {
    if (_isSleeping) return;
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag > 30.0 || mag < 4.5) return;

    _ring[_ringIdx] = mag;
    _ringIdx = (_ringIdx + 1) % _ringSize;
    // Stable EMA baseline
    _runningMean = _runningMean * 0.95 + mag * 0.05;

    // Dynamic threshold: use fixed 0.75 but lower to 0.5 if mean is near gravity (9.8)
    final dynamicT = (_runningMean > 9.0 && _runningMean < 10.6) ? 0.55 : _threshold;
    final isAbove = mag > _runningMean + dynamicT;

    if (isAbove && !_wasAbove) {
      final now = DateTime.now();
      if (_lastPeak == null || now.difference(_lastPeak!) >= _minGap) {
        _lastPeak = now;

        // Validate gap if we have history
        bool validStep = true;
        if (_recentPeaks.isNotEmpty) {
          final gap = now.difference(_recentPeaks.last);
          // Valid human step: 280ms–2200ms (catches slow/fast walkers)
          if (gap.inMilliseconds < 280 || gap.inMilliseconds > 2200) {
            validStep = false; // vibration or too slow
          }
        }
        // Always count first step — no history yet

        if (validStep) {
          _recentPeaks.add(now);
          if (_recentPeaks.length > 10) _recentPeaks.removeAt(0);

          _accelSteps++;
          _pendingSteps++;
          _stepsCadence++;

          // Debounce UI updates: batch every 250ms — prevents flicker/freeze
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 250), () {
            if (mounted && _pendingSteps > 0) {
              setState(() {
                _steps        = _accelSteps;
                _status       = 'walking';
                _dataSource   = 'accelerometer';
                _lastSyncTime = DateTime.now();
                _pendingSteps = 0;
              });
              ref.read(todayStepsProvider.notifier).update(_accelSteps);
            }
          });

          // Persist every 3 steps for accuracy with small counts
          if (_stepsCadence % 3 == 0) _persistSteps(_accelSteps);
        }
      }
    } else if (!isAbove && _wasAbove) {
      // Stopped: no peak for 3 seconds
      final now = DateTime.now();
      if (_lastPeak != null && now.difference(_lastPeak!).inMilliseconds > 3000) {
        if (mounted && _status == 'walking') {
          setState(() { _status = 'stopped'; _lastSyncTime = DateTime.now(); });
          _stepsCadence = 0;
          _persistSteps(_accelSteps);
        }
      }
    }
    _wasAbove = isAbove;
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDay = prefs.getString(_keyBaselineDay) ?? '';
    final today = _todayKey();
    if (savedDay == today) {
      final s = prefs.getInt(_keyStepsToday) ?? 0;
      if (mounted) setState(() => _steps = s);
      ref.read(todayStepsProvider.notifier).update(s);
      _pedometerBaseline = prefs.getInt(_keyBaseline) ?? -1;
    } else {
      if (savedDay.isNotEmpty) {
        final parts = savedDay.split('-');
        if (parts.length == 3) {
          final hk = 'steps_${_uid}_${parts[0]}_${int.tryParse(parts[1])??1}_${int.tryParse(parts[2])??1}';
          await prefs.setInt(hk, prefs.getInt(_keyStepsToday) ?? 0);
        }
      }
      await prefs.setString(_keyBaselineDay, today);
      await prefs.setInt(_keyStepsToday, 0);
      await prefs.setInt(_keyBaseline, -1);
      _pedometerBaseline = -1;
    }
  }

  Future<void> _persistSteps(int steps, {int? rawBaseline}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaselineDay, _todayKey());
    await prefs.setInt(_keyStepsToday, steps);
    if (rawBaseline != null) await prefs.setInt(_keyBaseline, rawBaseline);
    final n = DateTime.now();
    await prefs.setInt('steps_${_uid}_${n.year}_${n.month}_${n.day}', steps);
  }

  Future<void> _loadWeekHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final map   = <String, int>{};
    for (int i = 6; i >= 0; i--) {
      final d   = today.subtract(Duration(days: i));
      final key = 'steps_${_uid}_${d.year}_${d.month}_${d.day}';
      map[key]  = prefs.getInt(key) ?? 0;
    }
    // Also try HC for missing days
    HealthService().getWeeklySteps().then((week) {
      if (mounted) {
        week.forEach((dateKey, count) {
          final k = dateKey.startsWith('steps_') ? dateKey : 'steps_${_uid}_$dateKey';
          if ((map[k] ?? 0) < count) map[k] = count;
        });
        setState(() => _weekHistory = map);
        _saveWeekHistory(map);
      }
    }).catchError((_) {});
    if (mounted) setState(() => _weekHistory = map);
  }

  @override
  void dispose() {
    _walkAnim.dispose();
    _hcRefreshTimer?.cancel();
    _sleepCheckTimer?.cancel();
    _stepSub?.cancel();
    _statusSub?.cancel();
    _accelSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _syncLabel() {
    if (_lastSyncTime == null) return 'Never synced';
    final now  = DateTime.now();
    final diff = now.difference(_lastSyncTime!);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${_lastSyncTime!.hour.toString().padLeft(2,'0')}:${_lastSyncTime!.minute.toString().padLeft(2,'0')}';
  }

  double get _distanceKm => _steps * 0.000762;
  double get _calories   => _steps * 0.04;

  @override
  Widget build(BuildContext context) {
    final progress = (_steps / _dailyGoal).clamp(0.0, 1.0);
    final isWalking = _status == 'walking';
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final today     = DateTime.now();
    final barData   = List.generate(7, (i) {
      final d   = today.subtract(Duration(days: 6 - i));
      final key = 'steps_${_uid}_${d.year}_${d.month}_${d.day}';
      return (i == 6 ? _steps : (_weekHistory[key] ?? 0)).toDouble();
    });
    final maxY = barData.fold<double>(5000, math.max) * 1.25;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF5F7FF),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          floating: true,
          title: const Text('Step Counter',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            // Sync button
            GestureDetector(
              onTap: () => _refreshHC(manual: true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _syncing
                      ? [Colors.grey.shade400, Colors.grey.shade500]
                      : [const Color(0xFF1565C0), const Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      blurRadius: 8, offset: const Offset(0, 3))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _syncing
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(_syncing ? 'Syncing…' : _syncLabel(),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [

            // ── Main card ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(28),
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
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedBuilder(
                    animation: _walkAnim,
                    builder: (_, __) => Transform.translate(
                      offset: isWalking ? Offset(0, -6 * _walkAnim.value) : Offset.zero,
                      child: Text(
                        _isSleeping ? '😴' : isWalking ? '🚶' : '🧍',
                        style: const TextStyle(fontSize: 48)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SourceBadge(source: _dataSource, status: _status, isSleeping: _isSleeping),
                ]),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Text('$_steps',
                      key: ValueKey(_steps),
                      style: const TextStyle(
                          fontSize: 72, fontWeight: FontWeight.w900, color: Colors.white,
                          letterSpacing: -2)),
                ),
                Text('STEPS TODAY', style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13, letterSpacing: 3, fontWeight: FontWeight.w500)),
                if (_isSleeping) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                    child: const Text('😴 Steps paused during sleep',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                ] else ...[
                  const SizedBox(height: 24),
                  // Animated progress bar
                  Stack(children: [
                    Container(
                      height: 12, decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6))),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      height: 12,
                      width: (MediaQuery.of(context).size.width - 96) * progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: progress >= 1.0
                            ? [Colors.amber, Colors.orange]
                            : [Colors.white, Colors.white70]),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(
                            color: Colors.white.withOpacity(0.4),
                            blurRadius: 8)])),
                  ]),
                  const SizedBox(height: 8),
                  Text('$_steps / $_dailyGoal steps',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  if (progress >= 1.0)
                    const Padding(padding: EdgeInsets.only(top: 8),
                        child: Text('🏆 Goal achieved! Excellent!',
                            style: TextStyle(color: Colors.amber,
                                fontWeight: FontWeight.w700, fontSize: 14))),
                ],
              ]),
            ),

            const SizedBox(height: 20),

            // ── Stats row ────────────────────────────────────────────────────
            Row(children: [
              Expanded(child: _ModernStatCard(
                  emoji: '🔥', value: '${_calories.toStringAsFixed(0)}',
                  unit: 'kcal', label: 'Calories Burned',
                  gradient: [const Color(0xFFFF6B35), const Color(0xFFFF8E53)])),
              const SizedBox(width: 14),
              Expanded(child: _ModernStatCard(
                  emoji: '📍', value: _distanceKm.toStringAsFixed(2),
                  unit: 'km', label: 'Distance',
                  gradient: [const Color(0xFF1565C0), const Color(0xFF29B6F6)])),
            ]),

            const SizedBox(height: 20),

            // ── Weekly graph ─────────────────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showGraph = !_showGraph),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161B22) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                    child: const Text('📊', style: TextStyle(fontSize: 18))),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Weekly Steps',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Icon(_showGraph ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppTheme.primaryBlue),
                ]),
              ),
            ),

            if (_showGraph) ...[
              const SizedBox(height: 12),
              Container(
                height: 220,
                padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161B22) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
                child: BarChart(BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => AppTheme.primaryBlue.withOpacity(0.9),
                      getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                        '${rod.toY.toInt()} steps',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 44,
                        getTitlesWidget: (v, _) => Text(
                            v >= 1000 ? '${(v/1000).toStringAsFixed(0)}k' : v.toInt().toString(),
                            style: TextStyle(fontSize: 10,
                                color: isDark ? Colors.white60 : Colors.black45)))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final d = today.subtract(Duration(days: 6 - v.toInt()));
                          const lbl = ['M','T','W','T','F','S','S'];
                          final isToday = v.toInt() == 6;
                          return Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isToday ? AppTheme.primaryBlue : Colors.transparent,
                              borderRadius: BorderRadius.circular(8)),
                            child: Text(lbl[(d.weekday - 1) % 7],
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                    color: isToday ? Colors.white
                                        : isDark ? Colors.white60 : Colors.black45)));
                        })),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.grey.withOpacity(0.12), strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (i) {
                    final isToday = i == 6;
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: barData[i] > 0 ? barData[i] : 0.01,
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter, end: Alignment.topCenter,
                          colors: isToday
                              ? [const Color(0xFF1565C0), const Color(0xFF29B6F6)]
                              : [const Color(0xFF4CAF50).withOpacity(0.6),
                                 const Color(0xFF81C784).withOpacity(0.8)]),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true, toY: maxY,
                          color: Colors.grey.withOpacity(0.06)),
                      ),
                    ]);
                  }),
                )),
              ),
            ],

            const SizedBox(height: 16),

            // ── Data source card ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161B22) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _dataSource == 'health_connect'
                        ? Colors.green.withOpacity(0.1)
                        : AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(
                    _dataSource == 'health_connect' ? '❤️'
                        : _dataSource == 'pedometer' ? '👟' : '📡',
                    style: const TextStyle(fontSize: 22)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _dataSource == 'health_connect' ? 'Health Connect'
                        : _dataSource == 'pedometer' ? 'Hardware Pedometer'
                        : _dataSource == 'accelerometer' ? 'Motion Sensor'
                        : 'Initializing…',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    _dataSource == 'health_connect'
                        ? 'Accurate steps • Syncs every second • Works offline'
                        : _dataSource == 'pedometer'
                            ? 'Hardware chip • Very accurate • Works offline'
                            : 'Motion detection • Keep phone in pocket',
                    style: TextStyle(fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54)),
                ])),
              ]),
            ),

            // Hydration tip
            if (_steps > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryBlue.withOpacity(0.1),
                             const Color(0xFF29B6F6).withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2))),
                child: Row(children: [
                  const Text('💧', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    _steps > 5000
                        ? 'Active day! Drink +${((_steps/5000)*200).round()}ml extra water.'
                        : 'Every 5,000 steps = +200ml of water recommended.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ]),
              ),
            ],
          ]),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final String source, status;
  final bool isSleeping;
  const _SourceBadge({required this.source, required this.status, required this.isSleeping});
  @override
  Widget build(BuildContext context) {
    String label; Color color;
    if (isSleeping)                { label = '😴 Sleeping';       color = Colors.purpleAccent; }
    else if (source == 'health_connect') { label = '❤️ Health Connect'; color = Colors.greenAccent; }
    else if (source == 'pedometer') {
      label = status == 'walking' ? '🚶 Walking' : '🧍 Stopped';
      color = status == 'walking' ? Colors.greenAccent : Colors.white70;
    } else if (source == 'accelerometer') {
      label = status == 'walking' ? '📡 Walking' : '📡 Ready';
      color = Colors.amberAccent;
    } else { label = '⏳ Starting…'; color = Colors.white60; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5))),
      child: Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _ModernStatCard extends StatelessWidget {
  final String emoji, value, unit, label;
  final List<Color> gradient;
  const _ModernStatCard({required this.emoji, required this.value,
    required this.unit, required this.label, required this.gradient});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 14)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(12)),
          child: Text(emoji, style: const TextStyle(fontSize: 22))),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 26,
              color: gradient.first, letterSpacing: -0.5)),
          const SizedBox(width: 3),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(unit, style: TextStyle(fontSize: 13,
                color: gradient.first.withOpacity(0.8), fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45)),
      ]),
    );
  }
}
