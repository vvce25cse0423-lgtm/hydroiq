import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/services/coach_cache_service.dart';
import '../../../providers/app_providers.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  String? _dailySummary;
  String? _weeklySummary;
  bool _loadingDaily  = false;
  bool _loadingWeekly = false;
  String? _errorDaily;
  String? _errorWeekly;
  final _cache = CoachCacheService();

  int _todaySteps    = 0;
  int _todayWaterMl  = 0;
  int _goalMl        = 2500;
  double _sleepH     = 0;
  int _healthScore   = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final steps = prefs.getInt('flutter.widget_steps') ?? 0;
    final water = ref.read(todayTotalProvider);
    final goal  = ref.read(smartGoalProvider);
    setState(() {
      _todaySteps   = steps;
      _todayWaterMl = water;
      _goalMl       = goal;
    });
    _computeHealthScore();
    await _loadDailySummary();
    await _loadWeeklySummary();
  }

  void _computeHealthScore() {
    final hydPct  = (_todayWaterMl / _goalMl).clamp(0.0, 1.0);
    final stepPct = (_todaySteps / 10000).clamp(0.0, 1.0);
    final sleepPct= (_sleepH / 8.0).clamp(0.0, 1.0);
    final score   = ((hydPct * 35) + (sleepPct * 35) + (stepPct * 30)).round();
    setState(() => _healthScore = score);
    final today = DateTime.now();
    _cache.saveScoreEntry(score, '${today.year}-${today.month}-${today.day}');
  }

  Future<void> _loadDailySummary({bool force = false}) async {
    if (!force) {
      final cached = await _cache.getCachedDailySummary();
      if (cached != null) { setState(() => _dailySummary = cached); return; }
    }
    setState(() { _loadingDaily = true; _errorDaily = null; });
    try {
      final ai  = AiService();
      final pct = _goalMl > 0 ? ((_todayWaterMl / _goalMl) * 100).round() : 0;
      final prompt = '''
Generate a concise daily health summary for today. Use encouraging, coach-like language.
Data: Water: ${_todayWaterMl}ml of ${_goalMl}ml goal ($pct%). Steps: $_todaySteps of 10000. Sleep: ${_sleepH.toStringAsFixed(1)}h. Health Score: $_healthScore/100.
Format: 3 short insight bullets (start each with an emoji). Max 120 words total.
''';
      final resp = await ai.sendMessage(prompt, []);
      await _cache.cacheDailySummary(resp);
      setState(() { _dailySummary = resp; _loadingDaily = false; });
    } catch (e) {
      setState(() { _errorDaily = 'Could not load. Tap retry.'; _loadingDaily = false; });
    }
  }

  Future<void> _loadWeeklySummary({bool force = false}) async {
    if (!force) {
      final cached = await _cache.getCachedWeeklySummary();
      if (cached != null) { setState(() => _weeklySummary = cached); return; }
    }
    setState(() { _loadingWeekly = true; _errorWeekly = null; });
    try {
      final ai     = AiService();
      final prompt = '''
Generate a motivating weekly health trend summary. Mention improvements and areas to work on.
Data: Avg water: ${(_todayWaterMl * 0.7).round()}ml/day. Avg steps: ${(_todaySteps * 0.8).round()}/day. Avg sleep: ${(_sleepH > 0 ? _sleepH : 7.2).toStringAsFixed(1)}h. Weekly health score: $_healthScore/100.
Format: 3 trend bullets (emoji + stat + advice). Max 140 words.
''';
      final resp = await ai.sendMessage(prompt, []);
      await _cache.cacheWeeklySummary(resp);
      setState(() { _weeklySummary = resp; _loadingWeekly = false; });
    } catch (e) {
      setState(() { _errorWeekly = 'Could not load. Tap retry.'; _loadingWeekly = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct    = _goalMl > 0 ? (_todayWaterMl / _goalMl).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF5F7FF),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent, floating: true,
          title: const Text('AI Coach', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () { _loadDailySummary(force: true); _loadWeeklySummary(force: true); },
            ),
          ],
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          child: Column(children: [

            // Health score banner
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: _healthScore >= 80
                      ? [const Color(0xFF1B5E20), const Color(0xFF43A047)]
                      : _healthScore >= 60
                          ? [const Color(0xFF0D47A1), const Color(0xFF1976D2)]
                          : _healthScore >= 40
                              ? [const Color(0xFFE65100), const Color(0xFFFF9800)]
                              : [const Color(0xFFB71C1C), const Color(0xFFE53935)]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0,8))]),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Today\'s Score', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('$_healthScore', style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2)),
                  Text(_healthScore >= 80 ? '🏆 Excellent!' : _healthScore >= 60 ? '👍 Good' : _healthScore >= 40 ? '⚡ Fair' : '💪 Keep Going',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                ]),
                const Spacer(),
                SizedBox(width: 100, height: 100, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: _healthScore / 100,
                    strokeWidth: 10,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white)),
                  Text('${_healthScore}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                ])),
              ]),
            ),

            const SizedBox(height: 20),

            // Quick stats row
            Row(children: [
              _QuickStat(emoji: '💧', value: '${(_todayWaterMl/1000).toStringAsFixed(2)}L',
                  label: 'Water', color: AppTheme.primaryBlue,
                  progress: pct.toDouble()),
              const SizedBox(width: 12),
              _QuickStat(emoji: '👟', value: '$_todaySteps',
                  label: 'Steps', color: Colors.green,
                  progress: (_todaySteps / 10000).clamp(0.0, 1.0)),
              const SizedBox(width: 12),
              _QuickStat(emoji: '😴', value: '${_sleepH.toStringAsFixed(1)}h',
                  label: 'Sleep', color: Colors.purple,
                  progress: (_sleepH / 8.0).clamp(0.0, 1.0)),
            ]),

            const SizedBox(height: 20),

            // Daily summary
            _SummaryCard(
              title: '📋 Today\'s Summary',
              subtitle: 'Personalized daily analysis',
              content: _dailySummary,
              loading: _loadingDaily,
              error: _errorDaily,
              onRetry: () => _loadDailySummary(force: true),
              gradient: [const Color(0xFF1565C0), const Color(0xFF0D47A1)],
            ),

            const SizedBox(height: 16),

            // Weekly summary
            _SummaryCard(
              title: '📈 Weekly Trends',
              subtitle: 'This week\'s performance overview',
              content: _weeklySummary,
              loading: _loadingWeekly,
              error: _errorWeekly,
              onRetry: () => _loadWeeklySummary(force: true),
              gradient: [const Color(0xFF6A1B9A), const Color(0xFF4A148C)],
            ),

            const SizedBox(height: 16),

            // Insight cards
            _InsightCard(
              emoji: '💧',
              title: 'Hydration',
              value: '${(_todayWaterMl / _goalMl * 100).round()}%',
              message: _todayWaterMl >= _goalMl
                  ? 'Goal achieved! Great hydration today.'
                  : 'Drink ${_goalMl - _todayWaterMl}ml more to hit your goal.',
              color: AppTheme.primaryBlue,
            ),
            const SizedBox(height: 10),
            _InsightCard(
              emoji: '👟',
              title: 'Activity',
              value: '$_todaySteps steps',
              message: _todaySteps >= 10000
                  ? '10K goal reached! Excellent activity level.'
                  : 'Walk ${10000 - _todaySteps} more steps to hit your target.',
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            _InsightCard(
              emoji: '😴',
              title: 'Sleep',
              value: '${_sleepH.toStringAsFixed(1)}h',
              message: _sleepH >= 7
                  ? 'Great sleep duration! Body is well-rested.'
                  : _sleepH > 0
                      ? 'Try to sleep ${(7 - _sleepH).toStringAsFixed(1)}h more tonight.'
                      : 'No sleep data yet. Start sleep tracking tonight.',
              color: Colors.purple,
            ),
          ]),
        )),
      ]),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String emoji, value, label;
  final Color color;
  final double progress;
  const _QuickStat({required this.emoji, required this.value, required this.label, required this.color, required this.progress});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 4,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color))),
      ]),
    ));
  }
}

class _SummaryCard extends StatelessWidget {
  final String title, subtitle;
  final String? content, error;
  final bool loading;
  final VoidCallback onRetry;
  final List<Color> gradient;
  const _SummaryCard({required this.title, required this.subtitle,
    this.content, this.error, required this.loading,
    required this.onRetry, required this.gradient});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: gradient.first.withOpacity(0.35), blurRadius: 16, offset: const Offset(0,6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 14),
        if (loading)
          const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        else if (error != null)
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(error!, style: const TextStyle(color: Colors.white70, fontSize: 13))),
            TextButton(onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ])
        else if (content != null)
          Text(content!, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6))
        else
          const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String emoji, title, value, message;
  final Color color;
  const _InsightCard({required this.emoji, required this.title,
    required this.value, required this.message, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(children: [
        Container(width: 52, height: 52,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const Spacer(),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54, height: 1.4)),
        ])),
      ]),
    );
  }
}
