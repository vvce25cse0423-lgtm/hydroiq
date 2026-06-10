import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../providers/app_providers.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  List<HydrationLog> _weekLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWeekData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data every time screen becomes active
    if (!_loading) _loadWeekData();
  }

  Future<void> _loadWeekData() async {
    final user = ref.read(supabaseServiceProvider).currentUser;
    if (user == null) { setState(() => _loading = false); return; }

    try {
      final end = DateTime.now().add(const Duration(days: 1));
      final start = end.subtract(const Duration(days: 7));
      final logs = await ref.read(supabaseServiceProvider)
          .getHydrationLogsForRange(user.id, start, end);
      setState(() { _weekLogs = logs; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  /// Group logs by day of week
  Map<int, int> get _dailyTotals {
    final map = <int, int>{};
    for (int i = 0; i < 7; i++) {
      final day = DateTime.now().subtract(Duration(days: 6 - i));
      final dayLogs = _weekLogs.where((l) =>
          l.loggedAt.year == day.year &&
          l.loggedAt.month == day.month &&
          l.loggedAt.day == day.day);
      map[i] = dayLogs.fold(0, (sum, l) => sum + l.amountMl);
    }
    return map;
  }

  int get _weeklyTotal =>
      _weekLogs.fold(0, (sum, l) => sum + l.amountMl);

  int get _weeklyGoal => (ref.read(smartGoalProvider) * 7);

  int get _currentStreak {
    // Count consecutive days meeting goal (look back 30 days)
    int streak = 0;
    final goal = ref.read(smartGoalProvider);
    final allLogs = _weekLogs; // already loaded for week; supplement with days count
    // Use days user has ANY logs as a proxy for days active
    final activeDays = <String>{};
    for (final log in allLogs) {
      final d = log.loggedAt;
      activeDays.add('${d.year}-${d.month}-${d.day}');
    }
    // Streak: consecutive days from today backward
    for (int i = 0; i < 30; i++) {
      final day = DateTime.now().subtract(Duration(days: i));
      final dayLogs = allLogs.where((l) =>
          l.loggedAt.year == day.year &&
          l.loggedAt.month == day.month &&
          l.loggedAt.day == day.day);
      final total = dayLogs.fold(0, (sum, l) => sum + l.amountMl);
      // Count day if met goal OR if it's within first 4 days and has any logs
      final counts = total >= goal || (i < 4 && total > 0);
      if (counts) streak++; else if (i > 0) break;
    }
    return streak;
  }

  int get _totalDaysUsed {
    final days = <String>{};
    for (final log in _weekLogs) {
      final d = log.loggedAt;
      days.add('${d.year}-${d.month}-${d.day}');
    }
    return days.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todayTotal = ref.watch(todayTotalProvider);
    final goal = ref.watch(smartGoalProvider);
    final dailyTotals = _dailyTotals;
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                const SliverAppBar(
                  title: Text('Analytics'),
                  floating: true,
                  backgroundColor: Colors.transparent,
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── Summary Cards ─────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                emoji: '💧',
                                title: 'Today',
                                value: '${(todayTotal / 1000).toStringAsFixed(2)}L',
                                subtitle: 'of ${(goal / 1000).toStringAsFixed(1)}L',
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                emoji: '🔥',
                                title: 'Streak',
                                value: '$_currentStreak',
                                subtitle: 'days',
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                emoji: '📊',
                                title: 'This Week',
                                value: '${(_weeklyTotal / 1000).toStringAsFixed(1)}L',
                                subtitle: 'total',
                                color: AppTheme.accentTeal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ─── Weekly Bar Chart ──────────────────────
                        const Text('7-Day Hydration',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 16),
                        Container(
                          height: 200,
                          padding: const EdgeInsets.fromLTRB(0, 16, 16, 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (goal * 1.2).toDouble(),
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) => AppTheme.primaryBlue,
                                  getTooltipItem: (group, groupIndex,
                                      rod, rodIndex) {
                                    return BarTooltipItem(
                                      '${(rod.toY / 1000).toStringAsFixed(1)}L',
                                      const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final dayIdx = now
                                          .subtract(Duration(
                                              days: 6 - value.toInt()))
                                          .weekday -
                                          1;
                                      return Text(
                                        days[dayIdx % 7],
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black45),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                horizontalInterval: goal / 2,
                                getDrawingHorizontalLine: (value) => FlLine(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                  strokeWidth: 1,
                                ),
                                drawVerticalLine: false,
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(7, (i) {
                                final ml = dailyTotals[i] ?? 0;
                                final metGoal = ml >= goal;
                                return BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: ml.toDouble(),
                                      width: 18,
                                      color: metGoal
                                          ? AppTheme.successGreen
                                          : AppTheme.primaryBlue,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      backDrawRodData:
                                          BackgroundBarChartRodData(
                                        show: true,
                                        toY: goal.toDouble(),
                                        color: AppTheme.primaryBlue
                                            .withOpacity(0.08),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ─── Weekly Goal Progress ──────────────────
                        const Text('Weekly Goal',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${(_weeklyTotal / 1000).toStringAsFixed(1)}L',
                                    style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    '/ ${(_weeklyGoal / 1000).toStringAsFixed(0)}L',
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: (_weeklyTotal / _weeklyGoal)
                                      .clamp(0.0, 1.0),
                                  minHeight: 12,
                                  backgroundColor:
                                      AppTheme.primaryBlue.withOpacity(0.1),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          AppTheme.primaryBlue),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${((_weeklyTotal / _weeklyGoal) * 100).round()}% of weekly goal',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ─── Achievements ──────────────────────────
                        const Text('Achievements',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 12),
                        _AchievementsRow(streak: _currentStreak, totalDays: _totalDaysUsed),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String emoji, title, value, subtitle;
  final Color color;

  const _SummaryCard({
    required this.emoji,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: color)),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45)),
          const SizedBox(height: 2),
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38)),
        ],
      ),
    );
  }
}

class _AchievementsRow extends StatelessWidget {
  final int streak;
  final int totalDays;
  const _AchievementsRow({required this.streak, required this.totalDays});

  @override
  Widget build(BuildContext context) {
    final badges = [
      {'emoji': '💧', 'label': 'First Drop',      'unlocked': totalDays >= 1},
      {'emoji': '🌱', 'label': '4-Day Explorer',  'unlocked': totalDays >= 4},
      {'emoji': '🔥', 'label': '7-Day Streak',    'unlocked': streak >= 7},
      {'emoji': '⭐', 'label': '14-Day Hero',     'unlocked': streak >= 14},
      {'emoji': '🏆', 'label': '30-Day Champ',    'unlocked': streak >= 30},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges.map((b) {
        final unlocked = b['unlocked'] as bool;
        return _AnimatedBadge(
          emoji: b['emoji'] as String,
          label: b['label'] as String,
          unlocked: unlocked,
        );
      }).toList(),
    );
  }
}

class _AnimatedBadge extends StatefulWidget {
  final String emoji, label;
  final bool unlocked;
  const _AnimatedBadge({required this.emoji, required this.label, required this.unlocked});
  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.95), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glow = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    if (widget.unlocked) {
      Future.delayed(
          Duration(milliseconds: 300 + (widget.label.length * 20)),
          () { if (mounted) _ctrl.forward(); });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.unlocked;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 56) / 3,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: unlocked ? _scale.value : 1.0,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: unlocked
                  ? Colors.amber.withOpacity(0.12 + _glow.value * 0.08)
                  : Colors.grey.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: unlocked
                    ? Colors.amber.withOpacity(0.3 + _glow.value * 0.4)
                    : Colors.grey.withOpacity(0.15),
                width: unlocked ? 1.5 : 1),
              boxShadow: unlocked ? [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.15 * _glow.value),
                  blurRadius: 12, spreadRadius: 2)
              ] : [],
            ),
            child: Column(children: [
              Text(unlocked ? widget.emoji : '🔒',
                  style: TextStyle(
                      fontSize: 26,
                      color: unlocked ? null : Colors.grey.withOpacity(0.5))),
              const SizedBox(height: 6),
              Text(widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: unlocked ? Colors.amber.shade700 : Colors.grey)),
              if (unlocked) ...[
                const SizedBox(height: 4),
                Container(
                  width: 24, height: 3,
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
