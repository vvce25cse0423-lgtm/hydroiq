import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import '../../../data/services/health_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class _PermItem {
  final String key, emoji, title, description;
  final Permission permission;
  const _PermItem({required this.key, required this.emoji, required this.title,
      required this.description, required this.permission});
}

class PermissionSetupScreen extends ConsumerStatefulWidget {
  const PermissionSetupScreen({super.key});
  @override
  ConsumerState<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends ConsumerState<PermissionSetupScreen> {
  final Map<String, bool> _granted = {};
  bool _saving = false;

  bool _hcGranted = false;

  final List<_PermItem> _items = const [
    _PermItem(key: AppConstants.keyLocationPermission, emoji: '📍',
      title: 'Location',
      description: 'Fetch real weather for your area and give temperature-based hydration advice.',
      permission: Permission.locationWhenInUse),
    _PermItem(key: AppConstants.keyActivityPermission, emoji: '🏃',
      title: 'Activity & Steps',
      description: 'Automatically count your steps all day long. No manual entry needed — just walk!',
      permission: Permission.activityRecognition),
    _PermItem(key: AppConstants.keyMicPermission, emoji: '🎙️',
      title: 'Microphone',
      description: 'Log water with your voice hands-free.',
      permission: Permission.microphone),
    _PermItem(key: AppConstants.keyNotifPermission, emoji: '🔔',
      title: 'Notifications',
      description: 'Receive smart hydration reminders and daily progress updates.',
      permission: Permission.notification),
  ];

  Future<void> _requestHealthConnect() async {
    try {
      await Health().configure();
      final types = [
        HealthDataType.STEPS,
        HealthDataType.SLEEP_SESSION,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
      ];
      // Request authorization - this opens Health Connect system dialog
      final ok = await Health().requestAuthorization(
        types,
        permissions: types.map((_) => HealthDataAccess.READ).toList(),
      );
      if (mounted) setState(() => _hcGranted = ok);
      if (!ok) {
        // If system dialog didn't open, redirect to Health Connect app
        await HealthService.openHealthConnect();
        // Re-check after returning from HC app
        await Future.delayed(const Duration(seconds: 2));
        final recheckOk = await Health().hasPermissions(types,
            permissions: types.map((_) => HealthDataAccess.READ).toList()) ?? false;
        if (mounted) setState(() => _hcGranted = recheckOk);
      }
    } catch (e) {
      // Fallback: open Health Connect store page
      await HealthService.openHealthConnect();
      if (mounted) setState(() => _hcGranted = false);
    }
  }

  Future<void> _requestPermission(_PermItem item) async {
    final status = await item.permission.request();
    setState(() => _granted[item.key] = status.isGranted);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    for (final item in _items) {
      await prefs.setBool(item.key, _granted[item.key] ?? false);
    }
    await prefs.setBool(AppConstants.keyPermissionsSetup, true);
    if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: isDark ? [const Color(0xFF0D1117), const Color(0xFF161B22)]
                : [const Color(0xFFF0F8FF), Colors.white])),
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 32, 24, 0), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(16)),
                child: const Text('⚙️', style: TextStyle(fontSize: 28))),
              const SizedBox(height: 16),
              const Text('Setup Your\nSmart Experience',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 8),
              Text('Choose what HydroIQ can access. You can change these anytime in Settings.',
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54, height: 1.5)),
            ])),
          const SizedBox(height: 20),
          Expanded(child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              ..._items.map((item) {
                final isGranted = _granted[item.key];
                return _PermCard(item: item, isGranted: isGranted,
                  onAllow: () => _requestPermission(item),
                  onSkip: () => setState(() => _granted[item.key] = false));
              }),
              _HCPermCard(
                isGranted: _hcGranted,
                onAllow: _requestHealthConnect,
                onSkip: () => setState(() => _hcGranted = false),
              ),
            ],
          )),
          Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), child: Column(children: [
            SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
              onPressed: _saving ? null : _finish,
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text('Continue to Dashboard →'))),
            const SizedBox(height: 10),
            Text('App works even if all permissions are denied',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
          ])),
        ])),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  final _PermItem item; final bool? isGranted;
  final VoidCallback onAllow, onSkip;
  const _PermCard({required this.item, required this.isGranted,
      required this.onAllow, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final granted = isGranted == true;
    return AnimatedContainer(duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted ? AppTheme.successGreen.withOpacity(0.08)
            : isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: granted ? AppTheme.successGreen.withOpacity(0.4)
            : isDark ? Colors.white12 : Colors.black.withOpacity(0.06), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: granted
                ? [AppTheme.successGreen, AppTheme.accentTeal]
                : [const Color(0xFF0D47A1), const Color(0xFF29B6F6)]),
            borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(item.emoji, style: const TextStyle(fontSize: 24)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text(item.description, style: TextStyle(fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54, height: 1.4)),
          const SizedBox(height: 10),
          if (!granted) Row(children: [
            GestureDetector(onTap: onAllow,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
                  borderRadius: BorderRadius.circular(20)),
                child: const Text('Allow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)))),
            const SizedBox(width: 10),
            GestureDetector(onTap: onSkip,
              child: Text('Skip', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13))),
          ]) else Row(children: [
            const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 18),
            const SizedBox(width: 6),
            const Text('Granted', style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ])),
      ]));
  }
}

class _HCPermCard extends StatelessWidget {
  final bool isGranted;
  final VoidCallback onAllow, onSkip;
  const _HCPermCard({required this.isGranted, required this.onAllow, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGranted ? AppTheme.successGreen.withOpacity(0.08)
            : isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted ? AppTheme.successGreen.withOpacity(0.4)
              : isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
          width: 1.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 10,
            offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: isGranted
                ? [AppTheme.successGreen, AppTheme.accentTeal]
                : [const Color(0xFFE53935), const Color(0xFFFF7043)]),
            borderRadius: BorderRadius.circular(14)),
          child: const Center(child: Text('❤️', style: TextStyle(fontSize: 24)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Health Connect', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text('Read steps and sleep from Health Connect for 100% accurate tracking.',
              style: TextStyle(fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54, height: 1.4)),
          const SizedBox(height: 10),
          if (!isGranted) Row(children: [
            GestureDetector(
              onTap: onAllow,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFE53935), Color(0xFFFF7043)]),
                  borderRadius: BorderRadius.circular(20)),
                child: const Text('Connect', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSkip,
              child: Text('Skip', style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38, fontSize: 13))),
          ]) else const Row(children: [
            Icon(Icons.check_circle, color: AppTheme.successGreen, size: 18),
            SizedBox(width: 6),
            Text('Connected', style: TextStyle(
                color: AppTheme.successGreen, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ])),
      ]),
    );
  }
}
