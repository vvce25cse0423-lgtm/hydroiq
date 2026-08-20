import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';
import '../../../data/models/app_models.dart';

enum _ReportPeriod { week7, days15, months3 }

extension _PeriodLabel on _ReportPeriod {
  String get label => switch (this) {
    _ReportPeriod.week7   => '7 Days',
    _ReportPeriod.days15  => '15 Days',
    _ReportPeriod.months3 => '3 Months',
  };
  int get days => switch (this) {
    _ReportPeriod.week7   => 7,
    _ReportPeriod.days15  => 15,
    _ReportPeriod.months3 => 90,
  };
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _ReportPeriod _selectedPeriod = _ReportPeriod.week7;
  bool _generatingReport = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userProfileProvider.notifier).loadProfile();
    });
  }

  Future<void> _logout() async {
    await ref.read(supabaseServiceProvider).signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  Future<void> _generateReport(UserProfile profile) async {
    if (_generatingReport) return;
    setState(() => _generatingReport = true);
    try {
      final supabase = ref.read(supabaseServiceProvider);
      final userId   = supabase.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final end   = DateTime.now();
      final start = end.subtract(Duration(days: _selectedPeriod.days));

      final results = await Future.wait([
        supabase.getHydrationLogsForRange(userId, start, end),
        supabase.getStepLogsForRange(userId, start, end),
        supabase.getRecentSleepLogs(userId, _selectedPeriod.days),
      ]);

      final hydrationLogs = results[0] as List<HydrationLog>;
      final stepLogs      = results[1] as List<StepLog>;
      final sleepLogs     = results[2] as List<SleepLog>;

      // ── Build PDF ──────────────────────────────────────────────────────
      final pdf  = pw.Document();
      final days = _selectedPeriod.days;

      // Computed stats
      final totalHydration = hydrationLogs.fold<int>(0, (s, l) => s + l.amountMl);
      final avgHydration   = hydrationLogs.isEmpty ? 0.0 : totalHydration / days;
      final goalMl         = (profile.weightKg * 35).clamp(1500.0, 6000.0);
      final hydPct         = goalMl > 0 ? (avgHydration / goalMl * 100) : 0.0;

      final totalSteps = stepLogs.fold<int>(0, (s, l) => s + l.steps);
      // Divide by actual days (not records) for true daily average
      final avgSteps   = days > 0 ? totalSteps / days : 0.0;

      // Filter sessions with valid duration (>0) before averaging
      final validSleep = sleepLogs.where((l) => l.durationHours > 0).toList();
      final avgSleep   = validSleep.isEmpty
          ? 0.0
          : validSleep.fold<double>(0, (s, l) => s + l.durationHours) / validSleep.length;
      // Use validSleep for best/shortest calculations too
      final sleepForStats = validSleep.isEmpty ? sleepLogs : validSleep;

      // Helper colours
      const blue   = PdfColor.fromInt(0xFF0D47A1);
      const cyan   = PdfColor.fromInt(0xFF29B6F6);
      const grey   = PdfColor.fromInt(0xFF78909C);
      const light  = PdfColor.fromInt(0xFFE3F2FD);
      const white  = PdfColors.white;

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(
                colors: [blue, cyan],
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight),
              borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('HydroIQ Health Report',
                      style: pw.TextStyle(
                          color: white, fontSize: 22,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('${_selectedPeriod.label} · ${profile.name}',
                      style: pw.TextStyle(color: white, fontSize: 13)),
                  pw.SizedBox(height: 2),
                  pw.Text('Generated: ${_fmtDate(DateTime.now())}',
                      style: pw.TextStyle(color: white, fontSize: 11)),
                ]),
                pw.Text('💧', style: pw.TextStyle(fontSize: 36)),
              ])),

          pw.SizedBox(height: 20),

          // Profile row
          _pdfSection('👤 Profile', [
            _pdfRow('Name',   profile.name),
            _pdfRow('Age',    '${profile.age} years'),
            _pdfRow('Weight', '${profile.weightKg.toStringAsFixed(0)} kg'),
            _pdfRow('Gender', profile.gender[0].toUpperCase() + profile.gender.substring(1)),
            _pdfRow('Base goal', '${(goalMl / 1000).toStringAsFixed(1)} L/day'),
          ], blue, light),

          pw.SizedBox(height: 14),

          // Hydration
          _pdfSection('💧 Hydration ($days days)', [
            _pdfRow('Daily average',      '${avgHydration.toStringAsFixed(0)} ml'),
            _pdfRow('Total consumed',     '${totalHydration} ml'),
            _pdfRow('Daily goal',         '${goalMl.toStringAsFixed(0)} ml'),
            _pdfRow('Goal achievement',   '${hydPct.toStringAsFixed(0)}%'),
            _pdfRow('Log entries',        '${hydrationLogs.length}'),
          ], const PdfColor.fromInt(0xFF0288D1), const PdfColor.fromInt(0xFFE1F5FE)),

          pw.SizedBox(height: 14),

          // Steps
          _pdfSection('👣 Steps ($days days)', [
            _pdfRow('Daily average', '${avgSteps.toStringAsFixed(0)} steps'),
            _pdfRow('Total steps',   '$totalSteps'),
            _pdfRow('Records',       '${stepLogs.length}'),
          ], const PdfColor.fromInt(0xFF2E7D32), const PdfColor.fromInt(0xFFE8F5E9)),

          pw.SizedBox(height: 14),

          // Sleep
          _pdfSection('😴 Sleep ($days days)', sleepLogs.isEmpty
              ? [_pdfRow('Data', 'No sleep sessions recorded in this period')]
              : [
                  _pdfRow('Average duration', '${avgSleep.toStringAsFixed(1)} hrs'),
                  _pdfRow('Sessions', '${sleepLogs.length} (${validSleep.length} with duration data)'),
                  _pdfRow('Best night', '${sleepForStats.map((s) => s.durationHours).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} hrs'),
                  _pdfRow('Shortest night', '${sleepForStats.map((s) => s.durationHours).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} hrs'),
                ],
            const PdfColor.fromInt(0xFF4527A0), const PdfColor.fromInt(0xFFEDE7F6)),

          pw.SizedBox(height: 20),

          // Footer
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: light,
              borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text(
              'This report is generated from data logged in HydroIQ. '
              'Consult a healthcare professional for medical advice.',
              style: pw.TextStyle(color: grey, fontSize: 10))),
        ],
      ));

      // ── Save to downloads ─────────────────────────────────────────────
      final bytes    = await pdf.save();
      final dir      = await getDownloadsDirectory() ??
                       await getApplicationDocumentsDirectory();
      final fileName = 'HydroIQ_${_selectedPeriod.label.replaceAll(' ', '')}'
                       '_${_fmtDate(DateTime.now()).replaceAll('/', '-')}.pdf';
      final file     = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Saved: $fileName'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => OpenFile.open(file.path)),
        duration: const Duration(seconds: 5)));

      // Also open it immediately
      await OpenFile.open(file.path);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingReport = false);
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static pw.Widget _pdfSection(String title, List<pw.Widget> rows,
      PdfColor accent, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: accent, width: 0.5)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title,
            style: pw.TextStyle(
                color: accent, fontSize: 14,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Divider(color: accent, thickness: 0.5),
        pw.SizedBox(height: 6),
        ...rows,
      ]));
  }

  static pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  color: PdfColor.fromInt(0xFF455A64), fontSize: 11)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final isDark       = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings')),
        ]),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (profile) {
          if (profile == null) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('No profile found.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.read(userProfileProvider.notifier).loadProfile(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/profile-setup'),
                child: const Text('Set up profile')),
            ]));
          }

          final goalL = (profile.weightKg * 35).clamp(1500.0, 6000.0) / 1000;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Avatar
              Center(child: Column(children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF29B6F6)]),
                    borderRadius: BorderRadius.circular(28)),
                  child: Center(child: Text(
                    profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 40, color: Colors.white,
                        fontWeight: FontWeight.w800)))),
                const SizedBox(height: 14),
                Text(profile.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(profile.email,
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54)),
              ])),
              const SizedBox(height: 28),

              Row(children: [
                _InfoTile(emoji: '🎂', label: 'Age',    value: '${profile.age} yrs'),
                const SizedBox(width: 12),
                _InfoTile(emoji: '⚖️', label: 'Weight', value: '${profile.weightKg.toStringAsFixed(0)} kg'),
                const SizedBox(width: 12),
                _InfoTile(
                    emoji: profile.gender == 'male' ? '♂️' : profile.gender == 'female' ? '♀️' : '⚧️',
                    label: 'Gender',
                    value: profile.gender[0].toUpperCase() + profile.gender.substring(1)),
              ]),
              const SizedBox(height: 16),
              _InfoTile(emoji: '🎯', label: 'Daily Goal',
                  value: '${goalL.toStringAsFixed(1)}L', wide: true),
              const SizedBox(height: 28),

              // Health Reports card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0xFF0D47A1).withOpacity(0.3),
                           const Color(0xFF29B6F6).withOpacity(0.15)]
                        : [const Color(0xFFE3F2FD), const Color(0xFFE0F7FA)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.picture_as_pdf_rounded,
                          color: AppTheme.primaryBlue, size: 22)),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Health Reports',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('Hydration · Steps · Sleep as PDF',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ])),
                  ]),
                  const SizedBox(height: 16),

                  // Period chips
                  Row(children: _ReportPeriod.values.map((p) {
                    final sel = _selectedPeriod == p;
                    return Expanded(child: GestureDetector(
                      onTap: () => setState(() => _selectedPeriod = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(
                            right: p != _ReportPeriod.months3 ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppTheme.primaryBlue
                              : AppTheme.primaryBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sel
                                  ? AppTheme.primaryBlue
                                  : AppTheme.primaryBlue.withOpacity(0.2))),
                        child: Center(child: Text(p.label,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: sel ? Colors.white : AppTheme.primaryBlue))))));
                  }).toList()),
                  const SizedBox(height: 16),

                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generatingReport
                          ? null
                          : () => _generateReport(profile),
                      icon: _generatingReport
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(_generatingReport
                          ? 'Generating…'
                          : 'Download ${_selectedPeriod.label} PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))))),
                ]),
              ),
              const SizedBox(height: 24),

              _SettingsRow(
                icon: isDark ? Icons.dark_mode : Icons.light_mode,
                label: isDark ? 'Dark Mode' : 'Light Mode',
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                  activeColor: AppTheme.primaryBlue)),
              const Divider(height: 32),
              _SettingsRow(icon: Icons.edit_outlined, label: 'Edit Profile',
                  onTap: () => Navigator.pushNamed(context, '/profile-setup')),
              _SettingsRow(icon: Icons.notifications_outlined,
                  label: 'Notification Settings',
                  onTap: () => Navigator.pushNamed(context, '/settings')),
              _SettingsRow(icon: Icons.info_outline, label: 'About HydroIQ',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'HydroIQ',
                    applicationVersion: '1.0.0',
                    children: const [
                      Text('Smart hydration tracking powered by AI.')])),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: AppTheme.errorRed),
                label: const Text('Sign Out',
                    style: TextStyle(color: AppTheme.errorRed)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppTheme.errorRed, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)))),
              const SizedBox(height: 32),
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
  const _InfoTile({required this.emoji, required this.label,
      required this.value, this.wide = false});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38)),
            Text(value, style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ]));
    return wide ? tile : Expanded(child: tile);
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _SettingsRow({required this.icon, required this.label,
      this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppTheme.primaryBlue, size: 20)),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing ??
          Icon(Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.black26),
      onTap: onTap);
  }
}
