import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/app_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone   = prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
    final permissionsSetup = prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentSession?.user ?? supabase.auth.currentUser;

    if (!onboardingDone) {
      Navigator.pushReplacementNamed(context, '/onboarding'); return;
    }
    if (user == null) {
      Navigator.pushReplacementNamed(context, '/login'); return;
    }

    ref.invalidate(userProfileProvider);
    ref.invalidate(todayLogsProvider);

    try {
      final profile = await supabase.from('users')
          .select().eq('id', user.id).maybeSingle();
      if (!mounted) return;
      if (profile == null) {
        Navigator.pushReplacementNamed(context, '/profile-setup');
      } else if (!permissionsSetup) {
        Navigator.pushReplacementNamed(context, '/permission-setup');
      } else {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
          context, permissionsSetup ? '/dashboard' : '/permission-setup');
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/images/splash_background.jpg',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
