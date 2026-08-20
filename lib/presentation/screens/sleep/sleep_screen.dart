import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/background_service.dart';
import '../../../data/services/sleep_detection_engine.dart';
import '../../../data/services/sleep_health_service.dart';
import '../../../providers/app_providers.dart';

// ─── Sleep controls channel (DND / mute / screen) ────────────────────────────
const _sleepChannel = MethodChannel('com.hydroiq.app/sleep_controls');

// ─── Providers ────────────────────────────────────────────────────────────────
final _engineProvider    = Provider((_) => SleepDetectionEngine());
final _healthSvcProvider = Provider((_) => SleepHealthService());

// ─── Screen ───────────────────────────────────────────────────────────────────

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});
  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // Engine signal
  SleepSignal _signal = const SleepSignal();
  StreamSubscription<SleepSignal>? _signalSub;

  // Sessions
  List<ScoredSleepSession> _hcSessions     = [];
  List<ScoredSleepSession> _manualSessions = [];
  static const String _sessionsKey = 'sleep_manual_sessions_v2';
  Map<String, dynamic>     _trend          = {};
  bool _hcLoading = true;

  // Voice
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening     = false;
  String _voiceHint     = '';

  // Elapsed
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  // ── Sleep-signal detection state ──────────────────────────────────────────
  DateTime? _lastActiveTime;
  bool _dndEnabled      = false;
  bool _mutedEnabled    = false;
  bool _inactivityStop  = false;   // stop when inactive 15 min

  // Inactivity tracking via screen/time
  Timer? _inactivityTimer;

  // DND polling (polls every 30s to detect user turning off DND/mute as wake signal)
  Timer? _dndPollTimer;

  // Animations
  late AnimationController _pulseCtrl;
  late AnimationController _glowCtrl;

  @override
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (_signal.isTracking && _signal.sleepStart != null) {
        if (mounted) setState(() => _elapsed = DateTime.now().difference(_signal.sleepStart!));
        _startElapsedTimer();
        _startDNDPollTimer();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      _elapsedTimer?.cancel();
      _dndPollTimer?.cancel();
    }
  }

  Future<void> _init() async {
    final engine = ref.read(_engineProvider);
    final svc    = ref.read(_healthSvcProvider);

    await engine.initialize();

    // ── Restore persisted DND & inactivity preferences ──────────────
    {
      final prefs = await SharedPreferences.getInstance();
      final savedDnd        = prefs.getBool('sleep_pref_dnd')        ?? false;
      final savedInactivity = prefs.getBool('sleep_pref_inactivity') ?? false;
      if (mounted) {
        setState(() {
          _dndEnabled      = savedDnd;
          _inactivityStop  = savedInactivity;
        });
      }
    }

    _signalSub = engine.signals.listen((sig) {
      if (!mounted) return;
      setState(() => _signal = sig);
      if (sig.autoStopped) _onAutoStop(sig);
    });

    setState(() => _signal = SleepSignal(
      isTracking:    engine.isTracking,
      sleepStart:    engine.sleepStart,
      confidence:    engine.confidence,
      interruptions: engine.interruptions,
    ));

    if (engine.isTracking) {
      _startElapsedTimer();
      _startDNDPollTimer();
      _resetInactivityTimer();
    }

    await svc.initialize();
    if (!svc.isPermitted) await svc.checkPermissions();
    if (!svc.isPermitted) await svc.requestPermissions();
    _loadHCSessions(svc);

    _speechAvailable = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadHCSessions(SleepHealthService svc) async {
    setState(() => _hcLoading = true);
    final cached = await svc.loadCachedAsync();
    if (mounted && cached.isNotEmpty) {
      setState(() { _hcSessions = cached; _hcLoading = false; });
    }
    final fresh = await svc.fetchHCSessions(days: 14);
    if (mounted) {
      final trend = await svc.computeTrend(fresh.isNotEmpty ? fresh : cached);
      setState(() {
        _hcSessions = fresh.isNotEmpty ? fresh : cached;
        _trend      = trend;
        _hcLoading  = false;
      });
    }
  }

  // ── Session persistence ──────────────────────────────────────────────────────

  Future<void> _persistManualSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _manualSessions.map((s) => {
        'start':    s.start.toIso8601String(),
        'end':      s.end.toIso8601String(),
        'duration': s.durationHours,
        'score':    s.score,
        'interruptions': s.interruptions,
      }).toList();
      await prefs.setString(_sessionsKey, jsonEncode(encoded));
    } catch (_) {}
  }

  Future<void> _restoreManualSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_sessionsKey);
      if (raw == null || raw.isEmpty) return;
      final list  = jsonDecode(raw) as List<dynamic>;
      final restored = list.map((e) {
        final m = e as Map<String, dynamic>;
        final rawScore = (m['score'] as num).toDouble();
        final scoreInt = rawScore.toInt();
        String quality;
        if (scoreInt >= 85)      quality = 'Excellent';
        else if (scoreInt >= 70) quality = 'Good';
        else if (scoreInt >= 50) quality = 'Fair';
        else                     quality = 'Poor';
        return ScoredSleepSession(
          start:         DateTime.parse(m['start'] as String),
          end:           DateTime.parse(m['end']   as String),
          durationHours: (m['duration'] as num).toDouble(),
          score:         scoreInt,
          interruptions: (m['interruptions'] as num).toInt(),
          source:        'Manual',
          quality:       quality,
        );
      }).toList();
      if (mounted) setState(() => _manualSessions = restored);
    } catch (_) {}
  }

  Future<void> _deleteManualSession(ScoredSleepSession session) async {
    setState(() => _manualSessions.removeWhere(
        (s) => s.start.isAtSameMomentAs(session.start)));
    await _persistManualSessions();

    // ── Recalculate sleep addon from remaining sessions ─────────────────────
    // Sum water bonus only for sessions that started today
    final todayStart = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, microsecond: 0, millisecond: 0);
    int totalMl = 0;
    for (final s in _manualSessions) {
      if (s.start.isAfter(todayStart) || s.start.isAtSameMomentAs(todayStart)) {
        totalMl += SleepDetectionEngine.autoWaterForSession(s);
      }
    }
    // Write recalculated value (0 if no sessions remain today)
    await UserProfileNotifier.setAddon(UserProfileNotifier.kAddonSleep, totalMl);
    // Invalidate so water dashboard rebuilds immediately
    ref.invalidate(todayAddonProvider);

    // Also remove from Supabase if possible
    try {
      final user = ref.read(supabaseServiceProvider).currentUser;
      if (user != null) {
        await ref.read(supabaseServiceProvider)
            .deleteSleepLog(session.start.millisecondsSinceEpoch.toString());
      }
    } catch (_) {}
  }

  // ── Elapsed timer ─────────────────────────────────────────────────────────

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_signal.isTracking || _signal.sleepStart == null) return;
      setState(() => _elapsed = DateTime.now().difference(_signal.sleepStart!));
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsed = Duration.zero;
  }

  // ── DND / Mute / Inactivity ────────────────────────────────────────────────

  Future<bool> _hasDNDPermission() async {
    try {
      return await _sleepChannel.invokeMethod<bool>('hasDNDPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> _enableDND() async {
    try {
      final hasPerm = await _hasDNDPermission();
      if (!hasPerm) {
        await _sleepChannel.invokeMethod('openDNDSettings');
        return;
      }
      final ok = await _sleepChannel.invokeMethod<bool>('enableDND') ?? false;
      if (mounted) setState(() => _dndEnabled = ok);
    } catch (_) {}
  }

  Future<void> _disableDND() async {
    try {
      await _sleepChannel.invokeMethod<bool>('disableDND');
      if (mounted) setState(() => _dndEnabled = false);
    } catch (_) {}
  }

  Future<void> _enableMute() async {
    try {
      final ok = await _sleepChannel.invokeMethod<bool>('muteAudio') ?? false;
      if (mounted) setState(() => _mutedEnabled = ok);
    } catch (_) {}
  }

  Future<void> _disableMute() async {
    try {
      await _sleepChannel.invokeMethod<bool>('unmuteAudio');
      if (mounted) setState(() => _mutedEnabled = false);
    } catch (_) {}
  }

  // Poll DND/mute status every 1s — auto-stop sleep when user disables externally
  void _startDNDPollTimer() {
    _dndPollTimer?.cancel();
    _dndPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_signal.isTracking) { _dndPollTimer?.cancel(); return; }
      try {
        final isDND = await _sleepChannel.invokeMethod<bool>('isDNDEnabled') ?? false;

        // User disabled DND externally after we enabled it → stop sleep tracking immediately
        if (_dndEnabled && !isDND && _signal.isTracking) {
          if (mounted) {
            _dndPollTimer?.cancel();
            await _stopSleep();
            _showSnack('☀️ DND turned off — sleep tracking stopped automatically.');
          }
          return;
        }

        // User unmuted phone externally after we muted it → stop sleep tracking immediately
        if (_mutedEnabled && _signal.isTracking) {
          try {
            final isMuted = await const MethodChannel('com.hydroiq.app/volume')
                .invokeMethod<bool>('isMuted') ?? false;
            if (!isMuted) {
              if (mounted) {
                _dndPollTimer?.cancel();
                await _stopSleep();
                _showSnack('☀️ Mute disabled — sleep tracking stopped automatically.');
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  // Activity tracking timer — if phone is actively used for 15+ consecutive minutes while
  // sleep tracking is on, stop tracking (user is clearly awake)
  DateTime? _activeSessionStart; // when continuous phone activity started

  void _resetInactivityTimer() {
    if (!_inactivityStop || _lastActiveTime == null) return;
    _lastActiveTime = DateTime.now();
    _activeSessionStart = null; // reset active session
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!_signal.isTracking || _signal.sleepStart == null) {
        _inactivityTimer?.cancel(); return;
      }
      // Grace period: don't trigger within first 5 min of sleep start
      final elapsed = DateTime.now().difference(_signal.sleepStart!);
      if (elapsed.inMinutes < 5) return;

      // Check if phone has been continuously active for >= 15 minutes
      if (_activeSessionStart != null) {
        final activeFor = DateTime.now().difference(_activeSessionStart!);
        if (activeFor.inMinutes >= 15) {
          if (mounted) {
            _inactivityTimer?.cancel();
            await _stopSleep();
            _showSnack('📱 Phone active 15+ min — sleep tracking stopped.');
          }
        }
      }
    });
  }

  void _onUserActivity() {
    final now = DateTime.now();
    // If this is the first activity since last reset, start the active session timer
    if (_activeSessionStart == null && _inactivityStop && _signal.isTracking) {
      _activeSessionStart = now;
    }
    _lastActiveTime = now;
  }


  // ── Start / Stop ──────────────────────────────────────────────────────────

  Future<void> _startSleep() async {
    final engine = ref.read(_engineProvider);
    await engine.startTracking();
    await BackgroundService.startSleepMonitoring();
    _startElapsedTimer();
    _startDNDPollTimer();

    if (_dndEnabled)   await _enableDND();
    if (_mutedEnabled) await _enableMute();

    // Persist DND-active flag so background BroadcastReceiver / WorkManager
    // can detect external DND-off even when app is closed.
    if (_dndEnabled) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kSleepDndActive, true);
    }

    if (_inactivityStop) {
      _lastActiveTime = DateTime.now();
      _resetInactivityTimer();
    }

    if (mounted) {
      setState(() => _elapsed = Duration.zero);
      _showSnack('😴 Sleep tracking started — good night!');
    }
  }

  Future<void> _stopSleep() async {
    final engine  = ref.read(_engineProvider);
    final session = await engine.stopTracking(reason: 'manual');
    await BackgroundService.stopSleepMonitoring();

    _stopElapsedTimer();
    _dndPollTimer?.cancel();
    _inactivityTimer?.cancel();

    // Restore DND / mute and clear background flag
    if (_dndEnabled)   await _disableDND();
    if (_mutedEnabled) await _disableMute();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kSleepDndActive);

    if (session != null) await _finishSession(session);
  }

  Future<void> _onAutoStop(SleepSignal sig) async {
    _stopElapsedTimer();
    _dndPollTimer?.cancel();
    _inactivityTimer?.cancel();
    if (_dndEnabled)   await _disableDND();
    if (_mutedEnabled) await _disableMute();
    final svc = ref.read(_healthSvcProvider);
    _loadHCSessions(svc);
    _showSnack(
        '📱 Sleep ended: ${sig.autoStopReason.replaceAll('_', ' ')}');
  }

  /// Fix: adds recovery water to the GOAL instead of the drink log
  Future<void> _finishSession(ScoredSleepSession session) async {
    if (mounted) {
      setState(() {
        _manualSessions.insert(0, session);
        if (_manualSessions.length > 30) _manualSessions.removeLast();
      });
      await _persistManualSessions();
    }

    final ml = SleepDetectionEngine.autoWaterForSession(session);

    // ── Store sleep water addon for today (auto-resets next day) ─────────────
    await UserProfileNotifier.setAddon(
        UserProfileNotifier.kAddonSleep, ml);
    // Invalidate smartGoalProvider so water dashboard rebuilds immediately
    ref.invalidate(todayAddonProvider);

    // Save sleep log to Supabase
    final user = ref.read(supabaseServiceProvider).currentUser;
    if (user != null) {
      try {
        await ref.read(supabaseServiceProvider).addSleepLog(SleepLog(
          id:            DateTime.now().millisecondsSinceEpoch.toString(),
          userId:        user.id,
          sleepStart:    session.start,
          sleepEnd:      session.end,
          durationHours: session.durationHours,
          sleepScore:    session.score,
        ));
      } catch (_) {}
    }

    final svc = ref.read(_healthSvcProvider);
    _loadHCSessions(svc);

    if (mounted) {
      await Future.delayed(200.ms);
      _showGoalSnack(ml, session);
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

  Future<void> _toggleVoice() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() { _isListening = false; _voiceHint = ''; });
      return;
    }
    setState(() { _isListening = true; _voiceHint = 'Listening…'; });
    await _speech.listen(
      onResult: (r) {
        final words = r.recognizedWords.toLowerCase().trim();
        if (words.isEmpty) return;
        setState(() => _voiceHint = '"$words"');
        if (!r.finalResult) return;
        setState(() => _isListening = false);
        if (_isSleepIntent(words) && !_signal.isTracking) {
          setState(() => _voiceHint = '😴 Sleep command detected');
          Future.delayed(400.ms, _startSleep);
        } else if (_isWakeIntent(words) && _signal.isTracking) {
          setState(() => _voiceHint = '☀️ Wake command detected');
          Future.delayed(400.ms, _stopSleep);
        } else {
          setState(() => _voiceHint = _signal.isTracking
              ? 'Say "good morning" or "wake up" to stop'
              : 'Say "good night" or "going to sleep" to start');
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor:  const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: false),
    );
  }

  bool _isSleepIntent(String t) => const [
    'going to sleep','going to bed','i am sleeping','time to sleep',
    'good night','sleep now','bedtime','i am going to sleep',
    'start sleep','night night',
  ].any((p) => t.contains(p));

  bool _isWakeIntent(String t) => const [
    'good morning','wake up','i am awake','stop sleep','morning',
    'i woke up','woke up','end sleep','stop tracking',
  ].any((p) => t.contains(p));

  // ── Snacks ────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showGoalSnack(int ml, ScoredSleepSession s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Text('🎯', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Goal increased by ${ml}ml!',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.white)),
            Text(
                '${s.durationHours.toStringAsFixed(1)}h ${s.quality} sleep · '
                'Score ${s.score}/100',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        )),
      ]),
      duration: const Duration(seconds: 5),
      backgroundColor: const Color(0xFF1565C0),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  String _fmtTime(DateTime dt) => DateFormat.jm().format(dt);

  @override
  void dispose() {
    _signalSub?.cancel();
    _elapsedTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _dndPollTimer?.cancel();
    _inactivityTimer?.cancel();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final svc    = ref.read(_healthSvcProvider);
    final merged = svc.mergeAndDeduplicate(_hcSessions, _manualSessions);

    return GestureDetector(
      onTap: _onUserActivity,
      onPanUpdate: (_) => _onUserActivity(),
      child: Scaffold(
        body: CustomScrollView(slivers: [
          SliverAppBar(
            title: const Text('Sleep Tracker'),
            floating: true,
            backgroundColor: Colors.transparent,
            actions: [
              if (_hcLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))),
                ),
            ],
          ),

          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [

              // ── Main tracking card ─────────────────────────────────────
              _TrackingCard(
                signal: _signal, elapsed: _elapsed,
                pulseCtrl: _pulseCtrl, glowCtrl: _glowCtrl, isDark: isDark),

              const SizedBox(height: 16),

              // ── Confidence bar ─────────────────────────────────────────
              if (_signal.isTracking) _ConfidenceBar(confidence: _signal.confidence),
              if (_signal.isTracking) const SizedBox(height: 16),

              // ── Sleep controls (DND / Mute / Inactivity) ──────────────
              _SleepControlsCard(
                dndEnabled:     _dndEnabled,
                mutedEnabled:   _mutedEnabled,
                inactivityStop: _inactivityStop,
                isTracking:     _signal.isTracking,
                isDark:         isDark,
                onDNDChanged: (v) async {
                  setState(() => _dndEnabled = v);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('sleep_pref_dnd', v);
                },
                onMuteChanged:  (v) => setState(() => _mutedEnabled = v),
                onInactivityChanged: (v) async {
                  setState(() => _inactivityStop = v);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('sleep_pref_inactivity', v);
                },
              ),

              const SizedBox(height: 16),

              // ── Voice control ──────────────────────────────────────────
              if (_speechAvailable)
                _VoiceCard(
                  isListening: _isListening,
                  isTracking:  _signal.isTracking,
                  voiceHint:   _voiceHint,
                  onTap:       _toggleVoice,
                  isDark:      isDark),

              const SizedBox(height: 16),

              // ── Goal recovery card ─────────────────────────────────────
              _GoalRecoveryCard(),

              const SizedBox(height: 16),

              // ── Trend card ─────────────────────────────────────────────
              if (_trend.isNotEmpty) _TrendCard(trend: _trend),
              if (_trend.isNotEmpty) const SizedBox(height: 16),

              // ── Start / Stop button ────────────────────────────────────
              _ActionButton(
                isTracking: _signal.isTracking,
                onStart:    _startSleep,
                onStop:     _stopSleep),

              const SizedBox(height: 16),

              // HC status chip removed per requirements

              // ── Session history ────────────────────────────────────────
              if (merged.isNotEmpty) ...[
                Row(children: [
                  const Text('Recent Sleep Sessions',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  Text('${merged.length} sessions',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38)),
                ]),
                const SizedBox(height: 12),
                ...merged.take(30).map((s) => _SessionTile(
                  s: s,
                  fmtTime: _fmtTime,
                  onDelete: _manualSessions.any(
                      (m) => m.start.isAtSameMomentAs(s.start))
                      ? () => _deleteManualSession(s)
                      : null,
                )),
              ],
            ]),
          )),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      ),
    );
  }
}

// ─── Sleep Controls Card ──────────────────────────────────────────────────────

class _SleepControlsCard extends StatelessWidget {
  final bool dndEnabled, mutedEnabled, inactivityStop, isTracking, isDark;
  final ValueChanged<bool> onDNDChanged, onMuteChanged, onInactivityChanged;

  const _SleepControlsCard({
    required this.dndEnabled, required this.mutedEnabled,
    required this.inactivityStop, required this.isTracking,
    required this.isDark,
    required this.onDNDChanged, required this.onMuteChanged,
    required this.onInactivityChanged,
  }); // mutedEnabled kept in state for external-mute detection, just not shown in UI

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('🌙', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Sleep Mode Controls',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 4),
        Text('Applied when tracking starts · Restored on wake',
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38)),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),

        _ControlRow(
          icon: '🔕',
          title: 'Do Not Disturb',
          subtitle: dndEnabled
              ? 'Will enable on sleep start'
              : 'Off — tap to enable on sleep',
          value: dndEnabled,
          onChanged: isTracking ? null : onDNDChanged,
          activeColor: Colors.indigo,
        ),

        _ControlRow(
          icon: '📵',
          title: 'Detect Inactivity (15 min)',
          subtitle: inactivityStop
              ? 'Monitors phone inactivity as deep sleep signal'
              : 'Off — detect when phone is idle 15+ min',
          value: inactivityStop,
          onChanged: isTracking ? null : onInactivityChanged,
          activeColor: Colors.teal,
        ),

        if (isTracking) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.lock_outline, size: 14, color: Colors.orange),
              SizedBox(width: 6),
              Expanded(child: Text(
                  'Controls locked during tracking. '
                  'Wake up to change settings.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String icon, title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  const _ControlRow({
    required this.icon, required this.title, required this.subtitle,
    required this.value, required this.onChanged, required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13)),
          Text(subtitle, style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38)),
        ])),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
        ),
      ]),
    );
  }
}

// ─── Goal Recovery Card ───────────────────────────────────────────────────────

class _GoalRecoveryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('🎯', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Text('Auto Goal Boost on Wake',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 10),
        _WaterRow('😴', '< 5h (Poor)',    '+500ml to goal', Colors.red),
        _WaterRow('🌙', '5–7h (Fair)',    '+350ml to goal', Colors.orange),
        _WaterRow('✅', '7–9h (Optimal)', '+250ml to goal', Colors.green),
        _WaterRow('😪', '> 9h (Long)',    '+300ml to goal', Colors.blue),
      ]),
    );
  }
}

class _WaterRow extends StatelessWidget {
  final String icon, label, water;
  final Color color;
  const _WaterRow(this.icon, this.label, this.water, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(water, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    ]),
  );
}

// ─── Tracking Card ────────────────────────────────────────────────────────────

class _TrackingCard extends StatelessWidget {
  final SleepSignal signal;
  final Duration elapsed;
  final AnimationController pulseCtrl, glowCtrl;
  final bool isDark;

  const _TrackingCard({
    required this.signal, required this.elapsed,
    required this.pulseCtrl, required this.glowCtrl, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final tracking = signal.isTracking;
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: tracking
                ? [
                    Color.lerp(const Color(0xFF0D1B5E), const Color(0xFF1A2C8A),
                        pulseCtrl.value)!,
                    Color.lerp(const Color(0xFF1A0050), const Color(0xFF2D0070),
                        pulseCtrl.value)!,
                  ]
                : [const Color(0xFF263238), const Color(0xFF37474F)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: tracking
              ? [BoxShadow(
                  color: const Color(0xFF3949AB).withOpacity(
                      0.3 + 0.2 * pulseCtrl.value),
                  blurRadius: 24, offset: const Offset(0, 8))]
              : [],
        ),
        child: Column(children: [
          _StarRow(visible: tracking, ctrl: pulseCtrl),
          const SizedBox(height: 8),
          Text(tracking ? '😴' : '🌙',
              style: const TextStyle(fontSize: 56))
              .animate(target: tracking ? 1 : 0)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0))
              .fade(),
          const SizedBox(height: 12),
          Text(
            tracking
                ? '${elapsed.inHours.toString().padLeft(2, '0')}:'
                  '${elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
                  '${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}'
                : '00:00:00',
            style: const TextStyle(
                fontSize: 48, fontWeight: FontWeight.w900,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 4),
          Text(
              tracking
                  ? signal.statusLabel.toUpperCase()
                  : 'READY TO TRACK',
              style: const TextStyle(
                  color: Colors.white60, fontSize: 12, letterSpacing: 2)),
          if (tracking && signal.interruptions > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                '${signal.interruptions} interruption'
                '${signal.interruptions == 1 ? '' : 's'} detected',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final bool visible;
  final AnimationController ctrl;
  const _StarRow({required this.visible, required this.ctrl});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ctrl,
    builder: (_, __) => SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(9, (i) => Opacity(
          opacity: visible
              ? (0.2 + 0.8 * (i % 3 == 0 ? ctrl.value
                  : i % 3 == 1 ? 1 - ctrl.value : 0.5))
              : 0,
          child: const Text('✦',
              style: TextStyle(color: Colors.white, fontSize: 9)),
        )),
      ),
    ),
  );
}

// ─── Confidence Bar ───────────────────────────────────────────────────────────

class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});
  Color get _color {
    if (confidence > 0.75) return Colors.green;
    if (confidence > 0.5)  return Colors.blue;
    if (confidence > 0.25) return Colors.orange;
    return Colors.red;
  }
  String get _label {
    if (confidence > 0.75) return 'Deep sleep';
    if (confidence > 0.5)  return 'Light sleep';
    if (confidence > 0.25) return 'Restless';
    return 'Possible wake';
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Sleep Quality Signal',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54)),
          const Spacer(),
          Text(_label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: _color)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: confidence, minHeight: 10,
            backgroundColor: _color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(_color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
            'Adaptive threshold · Confidence ${(confidence * 100).round()}%',
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38)),
      ]),
    );
  }
}

// ─── Voice Card ───────────────────────────────────────────────────────────────

class _VoiceCard extends StatelessWidget {
  final bool isListening, isTracking, isDark;
  final String voiceHint;
  final VoidCallback onTap;
  const _VoiceCard({
    required this.isListening, required this.isTracking,
    required this.voiceHint, required this.onTap, required this.isDark,
  });
  @override
  Widget build(BuildContext context) => Column(children: [
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isListening
              ? Colors.redAccent.withOpacity(0.10)
              : const Color(0xFF1A237E).withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isListening
                ? Colors.redAccent.withOpacity(0.5)
                : const Color(0xFF1A237E).withOpacity(0.25),
            width: isListening ? 2 : 1),
        ),
        child: Row(children: [
          Icon(isListening ? Icons.mic : Icons.mic_none,
              color: isListening
                  ? Colors.redAccent : const Color(0xFF3949AB),
              size: 26),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isListening ? 'Listening…' : 'Voice Command',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                    color: isListening
                        ? Colors.redAccent : const Color(0xFF3949AB))),
            const SizedBox(height: 2),
            Text(isTracking
                ? 'Say "good morning" or "wake up" to stop'
                : 'Say "good night" or "going to sleep" to start',
                style: TextStyle(fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45)),
          ])),
        ]),
      ),
    ),
    if (voiceHint.isNotEmpty) ...[
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.purple),
          const SizedBox(width: 8),
          Expanded(child: Text(voiceHint,
              style: const TextStyle(fontSize: 13, color: Colors.purple))),
        ]),
      ),
    ],
  ]);
}

// ─── Trend Card ───────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  final Map<String, dynamic> trend;
  const _TrendCard({required this.trend});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avgH   = (trend['avgHours'] as double? ?? 0).toStringAsFixed(1);
    final avgS   = trend['avgScore'] as int? ?? 0;
    final bedH   = trend['avgBedHour'] as int? ?? 22;
    final bedStr = '${bedH > 12 ? bedH - 12 : bedH}:00 ${bedH >= 12 ? 'PM' : 'AM'}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('7-Day Trend',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: [
          _TrendStat('Avg Sleep', '$avgH h', Colors.indigo),
          _TrendStat('Avg Score', '$avgS',   Colors.green),
          _TrendStat('Bedtime',   bedStr,    Colors.purple),
        ]),
      ]),
    );
  }
}

class _TrendStat extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _TrendStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w800, color: color)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]));
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onStart, onStop;
  const _ActionButton({
    required this.isTracking, required this.onStart, required this.onStop});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 56,
    child: ElevatedButton.icon(
      onPressed: isTracking ? onStop : onStart,
      icon: Icon(isTracking
          ? Icons.wb_sunny_outlined : Icons.bedtime_outlined),
      label: Text(
        isTracking ? 'Wake Up — Save & Sync' : 'Start Sleep Tracking',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isTracking
            ? Colors.amber.shade700 : const Color(0xFF1A237E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16))),
    ),
  );
}

// ─── HC Status Chip ───────────────────────────────────────────────────────────

class _HCStatusChip extends StatelessWidget {
  final bool isPermitted;
  const _HCStatusChip({required this.isPermitted});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: isPermitted
              ? Colors.green.withOpacity(0.10)
              : Colors.orange.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isPermitted ? Icons.favorite : Icons.favorite_border,
            size: 14,
            color: isPermitted ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Text(
          isPermitted
              ? 'Health Connect syncing'
              : 'Health Connect: grant permission',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isPermitted ? Colors.green : Colors.orange)),
      ]),
    ),
  );
}

// ─── Session Tile ─────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final ScoredSleepSession s;
  final String Function(DateTime) fmtTime;
  final VoidCallback? onDelete;
  const _SessionTile({required this.s, required this.fmtTime, this.onDelete});

  Color get _scoreColor {
    if (s.score >= 80) return Colors.green;
    if (s.score >= 60) return Colors.orange;
    return Colors.red;
  }
  Color get _qualityColor {
    switch (s.quality) {
      case 'Excellent': return Colors.green;
      case 'Good':      return Colors.teal;
      case 'Fair':      return Colors.orange;
      default:          return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHC   = s.source == 'Health Connect';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(children: [
        Text(isHC ? '❤️' : '😴', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${s.durationHours.toStringAsFixed(1)}h',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 6),
            _Chip(s.quality, _qualityColor),
            const SizedBox(width: 5),
            _Chip(s.source,
                isHC ? Colors.green : AppTheme.primaryBlue, small: true),
          ]),
          const SizedBox(height: 3),
          Text('${fmtTime(s.start)} → ${fmtTime(s.end)}',
              style: TextStyle(fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45)),
          if (s.interruptions > 0)
            Text(
                '${s.interruptions} interruption'
                '${s.interruptions == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11,
                    color: isDark
                        ? Colors.orange.shade200
                        : Colors.orange.shade700)),
        ])),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _scoreColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${s.score}/100', style: TextStyle(
                color: _scoreColor,
                fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (onDelete != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Log'),
                    content: const Text('Remove this sleep session?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.red))),
                    ]),
                );
                if (confirm == true) onDelete!();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  final bool   small;
  const _Chip(this.label, this.color, {this.small = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: small ? 5 : 6, vertical: 2),
    decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(
        fontSize: small ? 9 : 10,
        fontWeight: FontWeight.w600,
        color: color)),
  );
}
