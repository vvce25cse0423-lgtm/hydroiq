import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/background_service.dart';
import '../../../data/services/health_service.dart';
import '../../../providers/app_providers.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});
  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen>
    with TickerProviderStateMixin {

  // Health Connect
  bool _hcAvailable  = false;
  bool _hcPermitted  = false;
  List<SleepSession> _hcSessions = [];

  // Manual tracking (fallback / complement)
  bool _isTracking  = false;
  DateTime? _sleepStart;

  // Voice
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening     = false;
  String _voiceHint     = '';

  // Phone-usage detection
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _pollTimer;
  final List<double> _motionBuffer = [];
  DateTime? _lastActiveTime;
  bool _phonePickedUp = false;
  static const int _motionBufLen = 30;
  static const double _pickupVar = 0.4;

  // Persist keys
  static const _keyTracking   = 'sleep_is_tracking';
  static const _keySleepStart = 'sleep_start_ms';

  late AnimationController _moonPulse;
  late AnimationController _starTwinkle;

  // Local manual sessions
  final List<_SleepEntry> _manualSessions = [];

  @override
  void initState() {
    super.initState();
    _moonPulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _starTwinkle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _initSpeech();
    _initHealthConnect();
    _loadPersistedSleepState();
  }

  // ── Health Connect ────────────────────────────────────────────────────────

  Future<void> _initHealthConnect() async {
    final svc = HealthService();
    _hcAvailable = await svc.initialize();
    if (!_hcAvailable) { if (mounted) setState(() {}); return; }

    _hcPermitted = await svc.hasPermissions();
    if (!_hcPermitted) _hcPermitted = await svc.requestPermissions();

    if (_hcPermitted) _loadHCSleep(); // non-blocking
    if (mounted) setState(() {});
  }

  Future<void> _loadHCSleep() async {
    try {
      final sessions = await HealthService().getRecentSleep(days: 7);
      if (mounted) setState(() => _hcSessions = sessions);
    } catch (_) {}
  }

  // ── Speech ────────────────────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) { if (mounted) setState(() => _isListening = false); },
    );
    if (mounted) setState(() {});
  }

  Future<void> _startVoiceListenForSleep() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() { _isListening = false; _voiceHint = ''; });
      return;
    }
    setState(() { _isListening = true; _voiceHint = 'Listening…'; });
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase().trim();
        if (words.isEmpty) return;
        setState(() => _voiceHint = '"$words"');
        if (result.finalResult) {
          setState(() => _isListening = false);
          if (_detectSleepIntent(words)) {
            _voiceHint = '😴 Sleep command!';
            setState(() {});
            Future.delayed(const Duration(milliseconds: 500), _startSleepTracking);
          } else if (_detectWakeIntent(words) && _isTracking) {
            _voiceHint = '☀️ Wake command!';
            setState(() {});
            Future.delayed(const Duration(milliseconds: 500), _stopAndSave);
          } else {
            setState(() => _voiceHint = 'Say: "I am going to sleep" or "Good morning"');
          }
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
    );
  }

  bool _detectSleepIntent(String t) => [
    'going to sleep','going to bed','i am sleeping','time to sleep',
    'good night','sleep now','bedtime','i am going to sleep','start sleep',
  ].any((p) => t.contains(p));

  bool _detectWakeIntent(String t) => [
    'good morning','wake up','i am awake','stop sleep','morning',
    'i woke up','woke up','end sleep',
  ].any((p) => t.contains(p));

  // ── Manual Sleep Tracking ─────────────────────────────────────────────────

  Future<void> _startSleepTracking() async {
    if (_isTracking) return;
    final now = DateTime.now();
    setState(() { _isTracking = true; _sleepStart = now; _voiceHint = ''; });
    await _persistSleepState(true, start: now);
    await BackgroundService.startSleepMonitoring();
    _startPhoneUsageDetection();
    _showSnack('😴 Sleep tracking started. Sweet dreams!');
    try { await WakelockPlus.disable(); } catch (_) {}
  }

  Future<void> _stopAndSave() async {
    if (!_isTracking || _sleepStart == null) return;
    final end   = DateTime.now();
    final hours = end.difference(_sleepStart!).inMinutes / 60.0;
    _stopPhoneUsageDetection();
    setState(() { _isTracking = false; });
    await _persistSleepState(false);
    await BackgroundService.stopSleepMonitoring();

    int score = 40;
    if (hours >= 7 && hours <= 9) score = 95;
    else if (hours >= 6) score = 75;
    else if (hours >= 5) score = 55;

    setState(() {
      _manualSessions.insert(0, _SleepEntry(
          start: _sleepStart!, end: end, hours: hours, score: score));
      if (_manualSessions.length > 5) _manualSessions.removeLast();
    });

    // Auto-add water to today's log based on sleep quality
    int autoWater = 200;
    String sleepLabel = 'good';
    if (hours < 5)       { autoWater = 500; sleepLabel = 'poor (<5h)'; }
    else if (hours < 7)  { autoWater = 300; sleepLabel = 'light (<7h)'; }
    else if (hours > 9)  { autoWater = 250; sleepLabel = 'long (>9h)'; }

    // Immediately add to hydration log
    ref.read(todayLogsProvider.notifier).addLog(
      autoWater, note: 'Sleep recovery: ${hours.toStringAsFixed(1)}h $sleepLabel sleep');

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('💧', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${autoWater}ml added to your log!',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('Sleep recovery for $sleepLabel sleep (${hours.toStringAsFixed(1)}h)',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            )),
          ]),
          duration: const Duration(seconds: 5),
          backgroundColor: const Color(0xFF1565C0),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ));
      });
    }

    // Save to Supabase
    final user = ref.read(supabaseServiceProvider).currentUser;
    if (user != null && hours > 0.1) {
      try {
        await ref.read(supabaseServiceProvider).addSleepLog(SleepLog(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: user.id,
          sleepStart: _sleepStart!,
          sleepEnd: end,
          durationHours: hours,
          sleepScore: score,
        ));
      } catch (_) {}
    }

    setState(() => _sleepStart = null);
    _showSnack('☀️ Sleep logged: ${hours.toStringAsFixed(1)}h · Score $score/100');

    // Refresh Health Connect data
    if (_hcPermitted) await _loadHCSleep();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadPersistedSleepState() async {
    final prefs   = await SharedPreferences.getInstance();
    final tracking = prefs.getBool(_keyTracking) ?? false;
    final startMs  = prefs.getInt(_keySleepStart);
    if (tracking && startMs != null) {
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      if (DateTime.now().difference(start).inHours < 16) {
        if (mounted) {
          setState(() { _isTracking = true; _sleepStart = start; });
          _startPhoneUsageDetection();
        }
      } else {
        await prefs.remove(_keyTracking);
        await prefs.remove(_keySleepStart);
      }
    }
  }

  Future<void> _persistSleepState(bool tracking, {DateTime? start}) async {
    final prefs = await SharedPreferences.getInstance();
    if (tracking && start != null) {
      await prefs.setBool(_keyTracking, true);
      await prefs.setInt(_keySleepStart, start.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_keyTracking);
      await prefs.remove(_keySleepStart);
    }
  }

  // ── Phone Usage Detection ─────────────────────────────────────────────────

  void _startPhoneUsageDetection() {
    _motionBuffer.clear();
    _phonePickedUp = false;
    _accelSub = accelerometerEventStream(
            samplingPeriod: SensorInterval.normalInterval)
        .listen(_onAccelEvent);
    _pollTimer = Timer.periodic(const Duration(minutes: 3), (_) => _checkPhoneUsage());
  }

  void _stopPhoneUsageDetection() {
    _accelSub?.cancel(); _accelSub = null;
    _pollTimer?.cancel(); _pollTimer = null;
    _motionBuffer.clear();
  }

  void _onAccelEvent(AccelerometerEvent e) {
    final mag = math.sqrt(e.x*e.x + e.y*e.y + e.z*e.z);
    _motionBuffer.add(mag);
    if (_motionBuffer.length > _motionBufLen) _motionBuffer.removeAt(0);
  }

  void _checkPhoneUsage() {
    if (_motionBuffer.length < 10) return;
    final mean = _motionBuffer.reduce((a,b)=>a+b) / _motionBuffer.length;
    final variance = _motionBuffer
        .map((v) => (v-mean)*(v-mean))
        .reduce((a,b)=>a+b) / _motionBuffer.length;
    final picked = variance > _pickupVar;
    if (picked && !_phonePickedUp) {
      _phonePickedUp = true; _lastActiveTime = DateTime.now();
    } else if (!picked) { _phonePickedUp = false; }
    if (picked && _lastActiveTime != null &&
        DateTime.now().difference(_lastActiveTime!).inMinutes >= 5) {
      if (mounted && _isTracking) {
        _stopAndSave();
        _showSnack('📱 Phone activity detected — sleep ended.');
      }
    }
    _motionBuffer.clear();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _formatDuration(DateTime? start) {
    if (start == null) return '0h 0m';
    final d = DateTime.now().difference(start);
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  @override
  void dispose() {
    _moonPulse.dispose(); _starTwinkle.dispose();
    _speech.stop(); _stopPhoneUsageDetection();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allSessions = <_SleepEntry>[];

    // Merge Health Connect sessions with manual
    for (final s in _hcSessions) {
      allSessions.add(_SleepEntry(
          start: s.start, end: s.end,
          hours: s.durationHours, score: s.score,
          source: s.source));
    }
    for (final s in _manualSessions) {
      // Avoid duplicates: don't add manual if HC already has a session within 30 min
      final overlap = allSessions.any((a) =>
          a.start.difference(s.start).abs().inMinutes < 30);
      if (!overlap) allSessions.add(s);
    }
    allSessions.sort((a, b) => b.start.compareTo(a.start));

    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverAppBar(
            title: Text('Sleep Tracker'),
            floating: true, backgroundColor: Colors.transparent),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [

            const SizedBox(height: 4),

            // Main tracking card
            AnimatedBuilder(
              animation: _moonPulse,
              builder: (_, __) => Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: _isTracking
                        ? [Color.lerp(const Color(0xFF1A237E), const Color(0xFF283593), _moonPulse.value)!,
                           Color.lerp(const Color(0xFF311B92), const Color(0xFF4A148C), _moonPulse.value)!]
                        : [const Color(0xFF37474F), const Color(0xFF546E7A)]),
                  borderRadius: BorderRadius.circular(28)),
                child: Column(children: [
                  _buildStarField(),
                  const SizedBox(height: 8),
                  Text(_isTracking ? '😴' : '🌙',
                      style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  Text(_isTracking ? _formatDuration(_sleepStart) : '0h 0m',
                      style: const TextStyle(fontSize: 56,
                          fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(_isTracking ? 'SLEEP IN PROGRESS' : 'READY TO TRACK',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, letterSpacing: 2)),
                  if (_isTracking) ...[
                    const SizedBox(height: 12),
                    _buildPulsingDot(),
                    const SizedBox(height: 8),
                    const Text('📱 Auto-stops when phone is used',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // Voice control
            if (_speechAvailable)
              GestureDetector(
                onTap: _startVoiceListenForSleep,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _isListening
                        ? Colors.redAccent.withOpacity(0.12)
                        : const Color(0xFF1A237E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent.withOpacity(0.6)
                          : const Color(0xFF1A237E).withOpacity(0.3),
                      width: _isListening ? 2 : 1)),
                  child: Row(children: [
                    Icon(_isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.redAccent : const Color(0xFF3949AB),
                        size: 28),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_isListening ? 'Listening…' : 'Voice Sleep Command',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                              color: _isListening ? Colors.redAccent : const Color(0xFF3949AB))),
                      const SizedBox(height: 3),
                      Text(_isTracking
                          ? 'Say "Good morning" to stop'
                          : 'Say "I am going to sleep" to start',
                          style: TextStyle(fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black45)),
                    ])),
                  ]),
                ),
              ),

            if (_voiceHint.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_voiceHint,
                      style: const TextStyle(fontSize: 13, color: Colors.purple))),
                ]),
              ),
            ],

            const SizedBox(height: 16),

            // Auto-hydration info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Text('💧', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text('Auto Water on Wake', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                const SizedBox(height: 10),
                _WaterRow(icon:'😴', label:'< 5h sleep', water:'+500ml', color: Colors.red),
                _WaterRow(icon:'🌙', label:'5–7h sleep', water:'+300ml', color: Colors.orange),
                _WaterRow(icon:'✅', label:'7–9h sleep', water:'+200ml', color: Colors.green),
                _WaterRow(icon:'😪', label:'> 9h sleep', water:'+250ml', color: Colors.blue),
              ]),
            ),

            const SizedBox(height: 20),

            // Start / Stop button
            SizedBox(width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                onPressed: _isTracking ? _stopAndSave : _startSleepTracking,
                icon: Icon(_isTracking ? Icons.wb_sunny : Icons.bedtime),
                label: Text(_isTracking
                    ? 'Wake Up — Save Sleep'
                    : 'Start Sleep Tracking',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking
                      ? Colors.amber.shade700 : const Color(0xFF1A237E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))))),

            // Sleep history
            if (allSessions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Recent Sleep Sessions',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
  
              ]),
              const SizedBox(height: 12),
              ...allSessions.take(5).map((s) => _SleepEntryTile(entry: s)),
            ],
          ]),
        )),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]),
    );
  }

  Widget _buildStarField() => AnimatedBuilder(
    animation: _starTwinkle,
    builder: (_, __) => SizedBox(height: 20, child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (i) => Opacity(
        opacity: _isTracking
            ? (0.3 + 0.7 * ((i%3==0) ? _starTwinkle.value : (i%3==1) ? 1-_starTwinkle.value : 0.5))
            : 0,
        child: const Text('✦', style: TextStyle(color: Colors.white, fontSize: 10)),
      )),
    )),
  );

  Widget _buildPulsingDot() => AnimatedBuilder(
    animation: _moonPulse,
    builder: (_, __) => Container(
      width: 10 + 4 * _moonPulse.value,
      height: 10 + 4 * _moonPulse.value,
      decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle)),
  );
}

// ── Helper widgets ─────────────────────────────────────────────────────────────




class _WaterRow extends StatelessWidget {
  final String icon, label, water; final Color color;
  const _WaterRow({required this.icon, required this.label, required this.water, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(water, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 12))),
    ]),
  );
}

class _SleepEntry {
  final DateTime start, end;
  final double hours;
  final int score;
  final String source;
  _SleepEntry({required this.start, required this.end,
    required this.hours, required this.score, this.source = 'Manual'});
}

class _SleepEntryTile extends StatelessWidget {
  final _SleepEntry entry;
  const _SleepEntryTile({required this.entry});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color scoreColor = entry.score >= 80 ? Colors.green
        : entry.score >= 60 ? Colors.orange : Colors.red;
    final isHC = entry.source == 'Health Connect';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(children: [
        Text(isHC ? '❤️' : '😴', style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text('${entry.hours.toStringAsFixed(1)}h',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: (isHC ? Colors.green : AppTheme.primaryBlue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(entry.source,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: isHC ? Colors.green : AppTheme.primaryBlue))),
          ]),
          Text(
            '${TimeOfDay.fromDateTime(entry.start).format(context)} → ${TimeOfDay.fromDateTime(entry.end).format(context)}',
            style: TextStyle(fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text('${entry.score}/100',
              style: TextStyle(color: scoreColor,
                  fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
  }
}
