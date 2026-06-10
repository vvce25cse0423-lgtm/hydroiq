import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../providers/app_providers.dart';

class WaterScreen extends ConsumerStatefulWidget {
  const WaterScreen({super.key});
  @override
  ConsumerState<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends ConsumerState<WaterScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveCtrl;
  late AnimationController _addAnimCtrl;
  late Animation<double> _addScaleAnim;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const int _dailyLimitMl = 5000;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _voiceStatus = '';
  int? _pendingMl; // ml recognized from voice, waiting for confirmation

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _addAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _addScaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: _addAnimCtrl, curve: Curves.elasticOut));
    _initSpeech();
    _fetchWeather();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (e) {
        if (mounted) setState(() { _isListening = false; _voiceStatus = 'Error: ${e.errorMsg}'; });
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _fetchWeather() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        ref.read(weatherProvider.notifier).fetchByCoords(pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _startVoiceInput() async {
    if (!_speechAvailable) {
      setState(() => _voiceStatus = 'Speech not available');
      return;
    }
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    setState(() {
      _isListening = true;
      _voiceStatus = 'Listening…';
      _pendingMl = null;
    });

    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        setState(() => _voiceStatus = '"$text"');
        if (result.finalResult) {
          final ml = _parseVoiceToMl(text);
          if (ml != null && ml > 0) {
            setState(() { _pendingMl = ml; _voiceStatus = 'Recognized: ${ml}ml'; });
          } else {
            setState(() => _voiceStatus = 'Could not parse amount. Try again.');
          }
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
    );
  }

  /// Parses phrases like "I drank 2 glasses of water", "500 ml", "1 bottle", "3 cups"
  // Converts spoken word numbers to digits
  double? _wordToNumber(String text) {
    const Map<String, double> words = {
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
      'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
      'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
      'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
      'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
      'forty': 40, 'fifty': 50, 'hundred': 100, 'half': 0.5,
    };
    double total = 0;
    double current = 0;
    bool found = false;
    for (final word in text.split(RegExp(r'\s+'))) {
      final w = word.replaceAll(RegExp(r'[^a-z]'), '');
      if (words.containsKey(w)) {
        final v = words[w]!;
        if (v == 100) { current = (current == 0 ? 1 : current) * 100; }
        else { current += v; }
        found = true;
      }
    }
    total += current;
    return found ? total : null;
  }

  double? _extractNumber(String text) {
    // Try digit first
    final digitMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (digitMatch != null) return double.tryParse(digitMatch.group(1)!);
    // Try word number
    return _wordToNumber(text);
  }

  int? _parseVoiceToMl(String text) {
    final num = _extractNumber(text);
    if (num == null || num == 0) return null;

    if (text.contains('glass') || text.contains('glasses')) return (num * 240).round();
    if (text.contains('cup') || text.contains('cups')) return (num * 240).round();
    if (text.contains('bottle') || text.contains('bottles')) return (num * 500).round();
    if (text.contains('liter') || text.contains('litre') || text.contains('liters')) return (num * 1000).round();
    if (text.contains('ml') || text.contains('milliliter') || text.contains('milli')) return num.round();
    if (text.contains('sip') || text.contains('sips')) return (num * 50).round();
    if (text.contains('water') && num <= 10) return (num * 240).round();

    // Default: if number >= 50 treat as ml, else treat as glasses
    if (num >= 50) return num.round();
    return (num * 240).round();
  }

  void _confirmVoiceAdd() {
    if (_pendingMl != null && _pendingMl! > 0) {
      ref.read(todayLogsProvider.notifier).addLog(_pendingMl!);
      _addAnimCtrl.forward(from: 0);
      setState(() { _pendingMl = null; _voiceStatus = ''; });
      Navigator.pop(context);
    }
  }

  Future<void> _addWithSound(int ml) async {
    final total = ref.read(todayTotalProvider);
    if (total >= _dailyLimitMl) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('⚠️ Daily limit reached (5L). Stay safe!'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final remaining = _dailyLimitMl - total;
    final actual = ml > remaining ? remaining : ml;
    await ref.read(todayLogsProvider.notifier).addLog(actual);
    _addAnimCtrl.forward(from: 0);
    // Play water drop sound
    try {
      await _audioPlayer.setVolume(0.8);
      await _audioPlayer.play(AssetSource('sounds/water_drop.wav'));
    } catch (_) {
      // Sound optional
    }
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AddWaterSheet(
        controller: ctrl,
        speech: _speech,
        speechAvailable: _speechAvailable,
        isListening: _isListening,
        voiceStatus: _voiceStatus,
        pendingMl: _pendingMl,
        onStartVoice: _startVoiceInput,
        onConfirmVoice: _confirmVoiceAdd,
        onAdd: (ml) {
          ref.read(todayLogsProvider.notifier).addLog(ml);
          _addAnimCtrl.forward(from: 0);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _clearAllLogs(List<HydrationLog> logs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Logs'),
        content: const Text('Are you sure you want to delete all logs for today?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final log in logs) {
        await ref.read(todayLogsProvider.notifier).deleteLog(log.id);
      }
    }
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _addAnimCtrl.dispose();
    _speech.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile  = ref.watch(userProfileProvider).valueOrNull;
    final logs     = ref.watch(todayLogsProvider);
    final totalMl  = ref.watch(todayTotalProvider);
    final goalMl   = ref.watch(smartGoalProvider);
    final weather  = ref.watch(weatherProvider).valueOrNull;
    final progress = (totalMl / goalMl).clamp(0.0, 1.0);
    final isDark   = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 0, floating: true, snap: true,
          backgroundColor: Colors.transparent, elevation: 0,
          title: const Row(children: [
            Text('💧', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('HydroIQ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          ]),
          actions: [
            if (weather != null)
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/weather'),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🌡️', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text('${weather.temperatureC.toStringAsFixed(0)}°C',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ),

            IconButton(icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.pushNamed(context, '/profile')),
          ],
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hey ${profile?.name.split(' ').first ?? 'there'} 👋',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_progressMessage(progress),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(height: 24),
            Center(child: ScaleTransition(
              scale: _addScaleAnim,
              child: _AnimatedWaterCircle(
                  progress: progress,
                  totalMl: totalMl,
                  goalMl: goalMl,
                  waveCtrl: _waveCtrl),
            )),
            const SizedBox(height: 28),
            const Text('Quick Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(children: AppConstants.quickAddAmounts.map((ml) =>
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _QuickAddBtn(ml: ml, onTap: () => _addWithSound(ml))))).toList()),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: SizedBox(
                child: OutlinedButton.icon(
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Custom / Voice'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              )),
            ]),
            const SizedBox(height: 16),
            if (weather != null && weather.recommendedExtraMl > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withOpacity(0.3))),
                child: Row(children: [
                  const Text('🌡️', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Hot Weather Alert',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('${weather.temperatureC.toStringAsFixed(0)}°C · Drink +${weather.recommendedExtraMl}ml more today.'),
                  ])),
                ]),
              ),
            // Today's Log header with Clear All
            logs.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (logList) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Today's Log",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Row(children: [
                    Text('${logList.length} entries',
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13)),
                    if (logList.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _clearAllLogs(logList),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.withOpacity(0.3))),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 15),
                            SizedBox(width: 4),
                            Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ]),
        )),
        logs.when(
          loading: () => const SliverToBoxAdapter(child: Center(
              child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
          error: (e, _) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
          data: (logList) => logList.isEmpty
              ? const SliverToBoxAdapter(child: _EmptyLogs())
              : SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _LogTile(
                    log: logList[i],
                    onDelete: () => ref.read(todayLogsProvider.notifier).deleteLog(logList[i].id)),
                  childCount: logList.length)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]),
    );
  }

  String _progressMessage(double p) {
    if (p == 0)  return 'Start hydrating — your body needs water! 💪';
    if (p < 0.3) return 'Good start! Keep drinking. 👍';
    if (p < 0.6) return 'Nice progress! On the right track. 🎯';
    if (p < 1.0) return 'Almost there! Just a bit more. 🚀';
    return 'Goal achieved! Amazing work today! 🏆';
  }
}

// ─── Animated Water Circle ────────────────────────────────────────────────────

class _AnimatedWaterCircle extends StatelessWidget {
  final double progress;
  final int totalMl, goalMl;
  final AnimationController waveCtrl;

  const _AnimatedWaterCircle({
    required this.progress,
    required this.totalMl,
    required this.goalMl,
    required this.waveCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270, height: 270,
      child: AnimatedBuilder(
        animation: waveCtrl,
        builder: (ctx, _) => CustomPaint(
          painter: _WaterFillPainter(
            progress: progress,
            wavePhase: waveCtrl.value * 2 * math.pi,
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('💧', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 4),
                Text(
                  '${(totalMl / 1000).toStringAsFixed(2)}L',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.1,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'of ${(goalMl / 1000).toStringAsFixed(1)}L goal',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE3F2FD),
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white70, width: 1)),
                  child: Text('${(progress * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 2)])),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WaterFillPainter extends CustomPainter {
  final double progress;
  final double wavePhase;

  _WaterFillPainter({required this.progress, required this.wavePhase});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 6;

    // Clip to circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Always draw a solid dark-blue circle background so text is always readable
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = const Color(0xFF1565C0),
    );

    if (progress > 0) {
      final fillHeight = size.height * (1 - progress.clamp(0.0, 1.0));
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: progress >= 1.0
              ? [const Color(0xFF00C853), const Color(0xFF1B5E20)]
              : [const Color(0xFF29B6F6), const Color(0xFF1565C0)],
        ).createShader(Rect.fromLTWH(0, fillHeight, size.width, size.height - fillHeight));

      final path = Path();
      path.moveTo(0, fillHeight);

      // Draw wave
      const waveAmp = 6.0;
      final waveLen = size.width / 1.5;
      for (double x = 0; x <= size.width; x++) {
        final y = fillHeight +
            waveAmp * math.sin((x / waveLen) * 2 * math.pi + wavePhase) +
            waveAmp * 0.5 * math.sin((x / waveLen) * 4 * math.pi + wavePhase * 1.3);
        if (x == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }

    canvas.restore();

    // Border circle
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = AppTheme.primaryBlue.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WaterFillPainter old) =>
      old.progress != progress || old.wavePhase != wavePhase;
}

// ─── Quick Add Button ─────────────────────────────────────────────────────────

class _QuickAddBtn extends StatelessWidget {
  final int ml; final VoidCallback onTap;
  const _QuickAddBtn({required this.ml, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF29B6F6)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('💧', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(ml >= 1000 ? '${ml ~/ 1000}L' : '${ml}ml',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }
}

// ─── Log Tile (with visible delete icon) ─────────────────────────────────────

class _LogTile extends StatelessWidget {
  final HydrationLog log; final VoidCallback onDelete;
  const _LogTile({required this.log, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = TimeOfDay.fromDateTime(log.loggedAt).format(context);
    return Dismissible(
      key: Key(log.id), direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.delete_outline, color: AppTheme.errorRed)),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('💧', style: TextStyle(fontSize: 20)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${log.amountMl} ml',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (log.note != null && log.note!.isNotEmpty)
              Text(log.note!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
          ])),
          Text(time, style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 8),
          // Visible delete icon button
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 18),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(40), child: Column(children: [
    const Text('🫗', style: TextStyle(fontSize: 60)),
    const SizedBox(height: 16),
    const Text('No logs yet today', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
    const SizedBox(height: 8),
    Text('Tap a quick-add button or use voice to log water.',
        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.withOpacity(0.7))),
  ]));
}

// ─── Add Water Bottom Sheet (with Voice) ─────────────────────────────────────

class _AddWaterSheet extends StatefulWidget {
  final TextEditingController controller;
  final stt.SpeechToText speech;
  final bool speechAvailable;
  final bool isListening;
  final String voiceStatus;
  final int? pendingMl;
  final VoidCallback onStartVoice;
  final VoidCallback onConfirmVoice;
  final void Function(int ml) onAdd;

  const _AddWaterSheet({
    required this.controller,
    required this.speech,
    required this.speechAvailable,
    required this.isListening,
    required this.voiceStatus,
    required this.pendingMl,
    required this.onStartVoice,
    required this.onConfirmVoice,
    required this.onAdd,
  });

  @override
  State<_AddWaterSheet> createState() => _AddWaterSheetState();
}

class _AddWaterSheetState extends State<_AddWaterSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _micPulse;
  bool _isListening = false;
  String _voiceStatus = '';
  int? _pendingMl;

  @override
  void initState() {
    super.initState();
    _micPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _isListening = widget.isListening;
    _voiceStatus = widget.voiceStatus;
    _pendingMl = widget.pendingMl;
  }

  @override
  void dispose() { _micPulse.dispose(); super.dispose(); }

  double? _wordToNum(String text) {
    const Map<String, double> words = {
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
      'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
      'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
      'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
      'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
      'forty': 40, 'fifty': 50, 'hundred': 100, 'half': 0.5,
    };
    double total = 0; double current = 0; bool found = false;
    for (final word in text.split(RegExp(r'\s+'))) {
      final w = word.replaceAll(RegExp(r'[^a-z]'), '');
      if (words.containsKey(w)) {
        final v = words[w]!;
        if (v == 100) { current = (current == 0 ? 1 : current) * 100; }
        else { current += v; }
        found = true;
      }
    }
    total += current;
    return found ? total : null;
  }

  int? _parseVoiceToMl(String text) {
    double? num;
    final digitMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (digitMatch != null) {
      num = double.tryParse(digitMatch.group(1)!);
    }
    num ??= _wordToNum(text);
    if (num == null || num == 0) return null;

    if (text.contains('glass') || text.contains('glasses') || text.contains('cup') || text.contains('cups')) return (num * 240).round();
    if (text.contains('bottle') || text.contains('bottles')) return (num * 500).round();
    if (text.contains('liter') || text.contains('litre') || text.contains('liters')) return (num * 1000).round();
    if (text.contains('ml') || text.contains('milliliter') || text.contains('milli')) return num.round();
    if (text.contains('sip') || text.contains('sips')) return (num * 50).round();
    // "i drank X of water" / "X water" with small number = glasses
    if (num <= 20 && (text.contains('water') || text.contains('drank') || text.contains('drunk'))) return (num * 240).round();
    if (num >= 50) return num.round();
    // Default: small number = glasses
    return (num * 240).round();
  }

  Future<void> _toggleListen() async {
    if (!widget.speechAvailable) return;
    if (_isListening) {
      await widget.speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() { _isListening = true; _voiceStatus = 'Listening…'; _pendingMl = null; });
    await widget.speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        setState(() => _voiceStatus = '"$text"');
        if (result.finalResult) {
          final ml = _parseVoiceToMl(text);
          setState(() {
            _isListening = false;
            if (ml != null && ml > 0) { _pendingMl = ml; _voiceStatus = 'Recognized: ${ml}ml — tap Add to confirm'; }
            else { _voiceStatus = 'Could not parse. Try: "2 glasses" or "500 ml"'; }
          });
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Handle
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Add Water', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        const SizedBox(height: 20),

        // Voice button
        if (widget.speechAvailable) ...[
          AnimatedBuilder(
            animation: _micPulse,
            builder: (ctx, _) => GestureDetector(
              onTap: _toggleListen,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Colors.redAccent.withOpacity(0.1 + _micPulse.value * 0.15)
                      : AppTheme.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isListening ? Colors.redAccent : AppTheme.primaryBlue.withOpacity(0.3),
                    width: _isListening ? 2.0 : 1.0),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? Colors.redAccent : AppTheme.primaryBlue,
                      size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_isListening ? 'Listening…' : 'Tap to speak',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                            color: _isListening ? Colors.redAccent : AppTheme.primaryBlue)),
                    const SizedBox(height: 2),
                    Text(_isListening ? 'Say: "I drank 2 glasses of water"' : 'e.g. "500 ml" · "3 cups" · "1 bottle"',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                  ])),
                ]),
              ),
            ),
          ),
          if (_voiceStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_pendingMl != null ? Colors.green : Colors.orange).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(_pendingMl != null ? Icons.check_circle_outline : Icons.info_outline,
                    color: _pendingMl != null ? Colors.green : Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_voiceStatus, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          if (_pendingMl != null) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => widget.onAdd(_pendingMl!),
              icon: const Icon(Icons.add),
              label: Text('Add ${_pendingMl}ml'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or type manually', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38))),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),
        ],

        // Manual input
        TextField(
          controller: widget.controller,
          autofocus: !widget.speechAvailable,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Amount (ml)',
            prefixIcon: const Icon(Icons.water_drop_outlined),
            suffixText: 'ml',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.3))),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            final ml = int.tryParse(widget.controller.text) ?? 0;
            if (ml > 0) widget.onAdd(ml);
          },
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('Add', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
