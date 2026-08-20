import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../water/water_screen.dart';
import '../steps/steps_screen.dart';
import '../sleep/sleep_screen.dart';
import '../ai_chat/ai_chat_screen.dart';
import '../analytics/analytics_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    WaterScreen(),
    StepsScreen(),
    SleepScreen(),
    AiChatScreen(),
    AnalyticsScreen(),
  ];

  static const _tabs = [
    _TabItem(icon: Icons.water_drop, label: 'Hydrate'),
    _TabItem(icon: Icons.directions_walk, label: 'Steps'),
    _TabItem(icon: Icons.bedtime, label: 'Sleep'),
    _TabItem(icon: Icons.auto_awesome, label: 'AI Chat'),
    _TabItem(icon: Icons.bar_chart, label: 'Stats'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
              blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (i) {
                final selected = i == _currentIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _currentIndex = i);
                    // Reload today logs when switching to any tab
                    if (i == 4) {
                      ref.invalidate(todayLogsProvider);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primaryBlue.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_tabs[i].icon, size: 24,
                        color: selected ? AppTheme.primaryBlue
                            : (isDark ? Colors.white38 : Colors.black38)),
                      const SizedBox(height: 3),
                      Text(_tabs[i].label, style: TextStyle(fontSize: 11,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? AppTheme.primaryBlue
                            : (isDark ? Colors.white38 : Colors.black38))),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}
