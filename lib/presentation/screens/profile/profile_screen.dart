import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  Future<void> _logout() async {
    await ref.read(supabaseServiceProvider).signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final isDark = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ─── Avatar + Name ──────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 40,
                              color: Colors.white,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(profile.name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(profile.email,
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ─── Stats ─────────────────────────────────────────────
              Row(
                children: [
                  _InfoTile(emoji: '🎂', label: 'Age', value: '${profile.age} years'),
                  const SizedBox(width: 12),
                  _InfoTile(
                      emoji: '⚖️',
                      label: 'Weight',
                      value: '${profile.weightKg.toStringAsFixed(0)} kg'),
                  const SizedBox(width: 12),
                  _InfoTile(
                      emoji: profile.gender == 'male'
                          ? '♂️'
                          : profile.gender == 'female'
                              ? '♀️'
                              : '⚧️',
                      label: 'Gender',
                      value: profile.gender[0].toUpperCase() +
                          profile.gender.substring(1)),
                ],
              ),
              const SizedBox(height: 16),
              _InfoTile(
                emoji: '🎯',
                label: 'Daily Hydration Goal',
                value: '${(profile.dailyGoalMl / 1000).toStringAsFixed(1)}L',
                wide: true,
              ),
              const SizedBox(height: 28),

              // ─── Theme ──────────────────────────────────────────────
              _SettingsRow(
                icon: isDark ? Icons.dark_mode : Icons.light_mode,
                label: isDark ? 'Dark Mode' : 'Light Mode',
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) =>
                      ref.read(themeModeProvider.notifier).toggle(),
                  activeColor: AppTheme.primaryBlue,
                ),
              ),

              const Divider(height: 32),

              // ─── Menu Items ──────────────────────────────────────────
              _SettingsRow(
                icon: Icons.edit_outlined,
                label: 'Edit Profile',
                onTap: () => Navigator.pushNamed(context, '/profile-setup'),
              ),
              _SettingsRow(
                icon: Icons.notifications_outlined,
                label: 'Notification Settings',
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
              _SettingsRow(
                icon: Icons.security_outlined,
                label: 'Privacy & Permissions',
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
              _SettingsRow(
                icon: Icons.info_outline,
                label: 'About HydroIQ',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'HydroIQ',
                  applicationVersion: '1.0.0',
                  children: const [
                    Text('Smart hydration tracking powered by AI.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ─── Logout ─────────────────────────────────────────────
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: AppTheme.errorRed),
                label: const Text('Sign Out',
                    style: TextStyle(color: AppTheme.errorRed)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(
                      color: AppTheme.errorRed, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String emoji, label, value;
  final bool wide;

  const _InfoTile({
    required this.emoji,
    required this.label,
    required this.value,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final widget = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38)),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
        ],
      ),
    );

    return wide ? widget : Expanded(child: widget);
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing ??
          Icon(Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.black26),
      onTap: onTap,
    );
  }
}
