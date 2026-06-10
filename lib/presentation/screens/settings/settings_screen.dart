import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/notification_service.dart';
import '../../../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifEnabled = true;
  int _reminderInterval = 2;
  bool _locationEnabled = false;
  bool _activityEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifEnabled = prefs.getBool(AppConstants.keyNotifPermission) ?? false;
      _locationEnabled = prefs.getBool(AppConstants.keyLocationPermission) ?? false;
      _activityEnabled = prefs.getBool(AppConstants.keyActivityPermission) ?? false;
    });
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final status = await Permission.notification.request();
      if (status.isGranted) {
        await NotificationService().scheduleIntervalReminders(_reminderInterval);
        setState(() => _notifEnabled = true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConstants.keyNotifPermission, true);
      }
    } else {
      await NotificationService().cancelAll();
      setState(() => _notifEnabled = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyNotifPermission, false);
    }
  }

  Future<void> _sendTestNotification() async {
    await NotificationService().showNotification(
      id: 9999,
      title: '💧 HydroIQ Test',
      body: 'Notifications are working! Stay hydrated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── Notifications ──────────────────────────────────────────
          _SectionHeader(title: 'Notifications'),
          _ToggleTile(
            icon: Icons.notifications_outlined,
            title: 'Hydration Reminders',
            subtitle: 'Get reminded to drink water throughout the day',
            value: _notifEnabled,
            onChanged: _toggleNotifications,
          ),
          if (_notifEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reminder interval',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _reminderInterval.toDouble(),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    label: 'Every ${_reminderInterval}h',
                    activeColor: AppTheme.primaryBlue,
                    onChanged: (v) => setState(() => _reminderInterval = v.round()),
                    onChangeEnd: (v) async {
                      await NotificationService()
                          .scheduleIntervalReminders(v.round());
                    },
                  ),
                  Text('Every $_reminderInterval hour(s)',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            _ActionTile(
              icon: Icons.send_outlined,
              title: 'Send Test Notification',
              onTap: _sendTestNotification,
            ),
          ],

          // ─── Permissions ────────────────────────────────────────────
          _SectionHeader(title: 'Permissions'),
          _StatusTile(
            icon: Icons.location_on_outlined,
            title: 'Location',
            subtitle: 'For weather-based recommendations',
            enabled: _locationEnabled,
            onManage: _openAppSettings,
          ),
          _StatusTile(
            icon: Icons.directions_run_outlined,
            title: 'Activity Recognition',
            subtitle: 'For step counting and calorie tracking',
            enabled: _activityEnabled,
            onManage: _openAppSettings,
          ),

          // ─── Appearance ─────────────────────────────────────────────
          _SectionHeader(title: 'Appearance'),
          _ToggleTile(
            icon: isDark ? Icons.dark_mode : Icons.light_mode,
            title: 'Dark Mode',
            subtitle: 'Toggle between light and dark theme',
            value: isDark,
            onChanged: (_) =>
                ref.read(themeModeProvider.notifier).toggle(),
          ),

          // ─── Data ───────────────────────────────────────────────────
          _SectionHeader(title: 'Data & Privacy'),
          _ActionTile(
            icon: Icons.delete_outline,
            title: 'Clear AI Chat History',
            color: AppTheme.errorRed,
            onTap: () async {
              final user = ref.read(supabaseServiceProvider).currentUser;
              if (user == null) return;
              await ref.read(supabaseServiceProvider).clearChat(user.id);
              ref.read(chatMessagesProvider.notifier).clearHistory();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat history cleared')),
                );
              }
            },
          ),
          _ActionTile(
            icon: Icons.open_in_new_outlined,
            title: 'Manage App Permissions',
            onTap: _openAppSettings,
          ),

          const SizedBox(height: 40),

          // ─── Version ────────────────────────────────────────────────
          Center(
            child: Text(
              'HydroIQ v1.0.0\nMade with 💧 & Flutter',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white24 : Colors.black26),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppTheme.primaryBlue,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primaryBlue,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? AppTheme.primaryBlue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: color)),
        trailing: Icon(Icons.chevron_right,
            color: isDark ? Colors.white38 : Colors.black26),
        onTap: onTap,
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool enabled;
  final VoidCallback onManage;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: enabled
                    ? AppTheme.successGreen.withOpacity(0.15)
                    : AppTheme.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                enabled ? 'Granted' : 'Denied',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? AppTheme.successGreen
                      : AppTheme.errorRed,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onManage,
              child: const Text('Manage',
                  style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
