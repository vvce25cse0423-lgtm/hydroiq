import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';

class _OnboardPage {
  final String emoji, title, subtitle;
  final List<Color> colors;
  const _OnboardPage({required this.emoji, required this.title,
      required this.subtitle, required this.colors});
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardPage> _pages = const [
    _OnboardPage(emoji: '💧', title: 'Stay Perfectly Hydrated',
        subtitle: 'HydroIQ tracks your daily water intake and gives smart recommendations based on your weight, activity, and weather.',
        colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
    _OnboardPage(emoji: '🧠', title: 'AI-Powered Insights',
        subtitle: 'Your personal AI hydration coach analyzes your habits and gives personalized advice to keep you at your best.',
        colors: [Color(0xFF1B5E20), Color(0xFF00BCD4)]),
    _OnboardPage(emoji: '🏆', title: 'Track, Streak & Achieve',
        subtitle: 'Build healthy habits with streaks, badges, and smart reminders. Your health journey starts today.',
        colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)]),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyOnboardingDone, true);
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final p = _pages[i];
              return Container(
                decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: p.colors)),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(p.emoji, style: const TextStyle(fontSize: 100)),
                      const SizedBox(height: 40),
                      Text(p.title, textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                              color: Colors.white, height: 1.2)),
                      const SizedBox(height: 20),
                      Text(p.subtitle, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16,
                              color: Colors.white.withOpacity(0.85), height: 1.6)),
                    ]),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 28 : 8, height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentPage ? Colors.white : Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(4)),
                    ))),
                const SizedBox(height: 32),
                Row(children: [
                  if (_currentPage < _pages.length - 1)
                    TextButton(onPressed: _finish,
                        child: Text('Skip', style: TextStyle(
                            color: Colors.white.withOpacity(0.7), fontSize: 16))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut);
                      } else { _finish(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                              blurRadius: 16, offset: const Offset(0, 6))]),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
                            style: const TextStyle(color: Color(0xFF0D47A1),
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, color: Color(0xFF0D47A1), size: 18),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
