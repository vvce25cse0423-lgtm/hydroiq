import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Header('HydroIQ Privacy Policy'),
          _Body('Last updated: July 2026'),
          const SizedBox(height: 16),

          _Section('1. What Data We Collect', [
            'Account information: email address and display name used to create your account.',
            'Health data: daily water intake logs, step counts, and sleep session records you choose to track.',
            'Profile data: age, weight, gender, and daily hydration goal used to personalise your recommendations.',
            'Location data: approximate city-level location used only to fetch local weather for hydration advice. Exact GPS coordinates are never stored.',
            'Device data: anonymous crash reports and app performance metrics (if crash reporting is enabled).',
          ]),

          _Section('2. How We Use Your Data', [
            'To provide core app features: hydration tracking, step counting, sleep analysis, and personalised goals.',
            'To generate AI-powered health insights using Google Gemini. Only anonymised, aggregated data is sent — never your name or email.',
            'To send optional local notifications for hydration reminders. We never send marketing emails.',
            'We do NOT sell, rent, or share your personal data with advertisers or third-party data brokers.',
          ]),

          _Section('3. Health Connect Data', [
            'HydroIQ uses Android Health Connect to read step counts and sleep sessions.',
            'We only request READ access. We never write to or modify your Health Connect data.',
            'Health Connect data is stored locally on your device and optionally in your private Supabase account.',
            'Health data is never shared with third parties. It is never used for advertising.',
            'You can revoke Health Connect access at any time via Android Settings → Apps → HydroIQ → Permissions.',
          ]),

          _Section('4. Data Storage & Security', [
            'Your data is stored in a private Supabase (PostgreSQL) database protected by row-level security. Only you can access your own records.',
            'All data transmission uses HTTPS/TLS encryption.',
            'API keys and credentials are never stored in the app binary. They are injected at build time.',
            'We retain your data for as long as your account is active. You can delete all data at any time from Settings → Delete My Account.',
          ]),

          _Section('5. Third-Party Services', [
            'Supabase (supabase.com) — database and authentication. Privacy policy: supabase.com/privacy',
            'Google Gemini API — AI chat responses. Data policy: ai.google.dev/gemini-api/terms',
            'OpenWeatherMap — weather data by city name. Privacy policy: openweathermap.org/privacy-policy',
            'Android Health Connect — on-device health data platform by Google.',
          ]),

          _Section('6. Your Rights', [
            'Access: you can view all your stored data in the app at any time.',
            'Deletion: use Settings → Delete My Account to permanently erase all your data.',
            'Correction: update your profile information from the Profile screen.',
            'Portability: contact us to request a copy of your data in machine-readable format.',
          ]),

          _Section('7. Children\'s Privacy', [
            'HydroIQ is not intended for children under 13. We do not knowingly collect data from children. If you believe a child has provided data, please contact us for immediate deletion.',
          ]),

          _Section('8. Contact', [
            'For privacy questions, data requests, or account deletion assistance, email: privacy@hydroiq.app',
          ]),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'By using HydroIQ, you agree to this Privacy Policy. '
              'We may update this policy; we will notify you of significant changes via in-app notice.',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3));
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white54 : Colors.black45));
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> points;
  const _Section(this.title, this.points);
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, height: 2.0)),
        ...points.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 8),
              child: Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    shape: BoxShape.circle),
              ),
            ),
            Expanded(child: Text(p,
                style: TextStyle(fontSize: 13, height: 1.6,
                    color: isDark ? Colors.white70 : Colors.black87))),
          ]),
        )),
      ]),
    );
  }
}
