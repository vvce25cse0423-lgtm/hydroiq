import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
    with TickerProviderStateMixin {
  late AnimationController _loadingController;
  late Animation<double> _progressAnim;

  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();

    // 1. Graphical loading bar from left to right (2.5 seconds)
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _progressAnim = CurvedAnimation(
      parent: _loadingController,
      curve: Curves.easeInOutCubic,
    );

    // 2. Shimmer reflection traversing the liquid fill
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmerAnim = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.linear,
    );

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Start graphical loading animation immediately
    _loadingController.forward();

    final startTime = DateTime.now();

    // Ensure Supabase is initialized before checking auth
    if (AppConstants.isSupabaseConfigured) {
      try {
        Supabase.instance.client;
      } catch (_) {
        try {
          await Supabase.initialize(
            url: AppConstants.supabaseUrl,
            anonKey: AppConstants.supabaseAnonKey,
          );
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone =
        prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
    final permissionsSetup =
        prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;
    final wasLoggedIn =
        prefs.getBool('is_logged_in') ?? false;

    // Detect user session
    var user = AppConstants.isSupabaseConfigured
        ? (Supabase.instance.client.auth.currentSession?.user ??
            Supabase.instance.client.auth.currentUser)
        : null;

    // If previously logged in but currentSession is still completing restoration,
    // give Supabase auth state change up to 1500ms to resolve before deciding
    if (user == null && wasLoggedIn && AppConstants.isSupabaseConfigured) {
      try {
        await Supabase.instance.client.auth.onAuthStateChange
            .firstWhere((data) => data.session != null)
            .timeout(const Duration(milliseconds: 1500));
        user = Supabase.instance.client.auth.currentSession?.user ??
            Supabase.instance.client.auth.currentUser;
      } catch (_) {
        user = Supabase.instance.client.auth.currentUser;
      }
    }

    if (user != null) {
      await prefs.setBool('is_logged_in', true);
      await prefs.setString(AppConstants.keyUserId, user.id);
      if (user.email != null) {
        await prefs.setString(AppConstants.keyUserEmail, user.email!);
      }
    }

    ref.invalidate(userProfileProvider);
    ref.invalidate(todayLogsProvider);

    String targetRoute = '/dashboard';
    dynamic fetchedProfile;

    if (!onboardingDone) {
      targetRoute = '/onboarding';
    } else if (AppConstants.isSupabaseConfigured && user == null) {
      targetRoute = '/login';
    } else if (AppConstants.isSupabaseConfigured && user != null) {
      try {
        fetchedProfile = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (fetchedProfile == null) {
          targetRoute = '/profile-setup';
        } else if (!permissionsSetup) {
          targetRoute = '/permission-setup';
        } else {
          targetRoute = '/dashboard';
        }
      } catch (_) {
        targetRoute =
            permissionsSetup ? '/dashboard' : '/permission-setup';
      }
    } else {
      targetRoute = permissionsSetup ? '/dashboard' : '/permission-setup';
    }

    // Fetch weather data early at splash screen so dashboard shows it immediately
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && permissionsSetup) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        await ref
            .read(weatherProvider.notifier)
            .fetchByCoords(pos.latitude, pos.longitude);
      } else if (fetchedProfile != null &&
          fetchedProfile['city'] != null &&
          (fetchedProfile['city'] as String).isNotEmpty) {
        await ref
            .read(weatherProvider.notifier)
            .fetchByCity(fetchedProfile['city'] as String);
      }
    } catch (_) {}

    // Ensure user sees the complete graphical loading sequence (at least 2.5s)
    final elapsed = DateTime.now().difference(startTime);
    final remainingMs = 2500 - elapsed.inMilliseconds;
    if (remainingMs > 0) {
      await Future.delayed(Duration(milliseconds: remainingMs));
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, targetRoute);
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final barWidth = math.min(size.width * 0.74, 290.0);

    return Scaffold(
      backgroundColor: const Color(0xFF02143B),
      body: Stack(
        children: [
          // High-resolution clean splash artwork
          Positioned.fill(
            child: Image.asset(
              'assets/images/splash_background.jpg',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),

          // Graphical Loading Bar & Status overlay
          Align(
            alignment: const Alignment(0, 0.73),
            child: SizedBox(
              width: barWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glass Capsule Progress Bar (Left to Right Fill)
                  Container(
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: const Color(0x55001938), // Translucent dark glass track
                      border: Border.all(
                        color: const Color(0xDC00E5FF),
                        width: 1.6,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8000B0FF),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Color(0x3300E5FF),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          // Capsule track inner glass gradient
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x1AFFFFFF),
                                  Colors.transparent,
                                  Color(0x33001845),
                                ],
                              ),
                            ),
                          ),

                          // Animated Liquid Fill (Left to Right)
                          AnimatedBuilder(
                            animation: _progressAnim,
                            builder: (context, _) {
                              final progress =
                                  _progressAnim.value.clamp(0.0, 1.0);
                              if (progress <= 0.005) {
                                return const SizedBox.shrink();
                              }
                              return FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: Stack(
                                  children: [
                                    // Glowing Liquid Gradient Fill (matching user image)
                                    Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Color(0xFF00A3FF), // Deep electric cyan
                                            Color(0xFF00E5FF), // Bright cyan
                                            Color(0xFF67E8F9), // Ice cyan
                                            Color(0xFFFFFFFF), // Core white glow
                                          ],
                                          stops: [0.0, 0.55, 0.90, 1.0],
                                        ),
                                      ),
                                    ),

                                    // 3D Glass Top Reflection Sheen
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      height: 8,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x99FFFFFF),
                                              Color(0x00FFFFFF),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Continuous shimmer light sweep
                                    AnimatedBuilder(
                                      animation: _shimmerAnim,
                                      builder: (context, _) {
                                        final offset =
                                            (_shimmerAnim.value * 2.0 - 0.5) *
                                                barWidth;
                                        return Transform.translate(
                                          offset: Offset(offset, 0),
                                          child: Container(
                                            width: 45,
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Color(0x00FFFFFF),
                                                  Color(0x80FFFFFF),
                                                  Color(0x00FFFFFF),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Centered "Loading..." with animated trailing dots
                  AnimatedBuilder(
                    animation: _loadingController,
                    builder: (context, _) {
                      final dotIndex =
                          ((_loadingController.value * 8).toInt() % 4);
                      final dots = '.' * dotIndex;

                      return Text(
                        'Loading$dots',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF90CAF9),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1.1,
                          shadows: [
                            Shadow(
                              color: Color(0x6600B0FF),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
