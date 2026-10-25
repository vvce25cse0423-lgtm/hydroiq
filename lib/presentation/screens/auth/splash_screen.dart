import 'dart:math' as math;
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
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  late AnimationController _loadingController;
  late Animation<double> _progressAnim;

  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnim;

  late AnimationController _sparkleController;

  @override
  void initState() {
    super.initState();

    // 1. Overall screen fade-in
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    // 2. Graphical loading bar from left to right (2.5 seconds)
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _progressAnim = CurvedAnimation(
      parent: _loadingController,
      curve: Curves.easeInOutCubic,
    );

    // 3. Shimmer reflection traversing the liquid fill
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmerAnim = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.linear,
    );

    // 4. Subtle ambient sparkle pulse
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Start graphical loading animation immediately
    _loadingController.forward();

    final startTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone =
        prefs.getBool(AppConstants.keyOnboardingDone) ?? false;
    final permissionsSetup =
        prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentSession?.user ?? supabase.auth.currentUser;

    ref.invalidate(userProfileProvider);
    ref.invalidate(todayLogsProvider);

    String targetRoute = '/dashboard';

    if (!onboardingDone) {
      targetRoute = '/onboarding';
    } else if (user == null) {
      targetRoute = '/login';
    } else {
      try {
        final profile = await supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (profile == null) {
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
    }

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
    _fadeController.dispose();
    _loadingController.dispose();
    _shimmerController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final barWidth = math.min(size.width * 0.78, 320.0);

    return Scaffold(
      backgroundColor: const Color(0xFF02143B),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
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
              alignment: const Alignment(0, 0.76),
              child: SizedBox(
                width: barWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glass Capsule Progress Bar (Left to Right Fill)
                    Container(
                      height: 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: const Color(0x6602163B), // Translucent dark glass
                        border: Border.all(
                          color: const Color(0x8C3888E8),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x591E6FD9),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            // Capsule track inner glass gradient
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x14FFFFFF),
                                    Colors.transparent,
                                    Color(0x4D0D3370),
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
                                      // Glowing Liquid Gradient Fill
                                      Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Color(0xFF3B82F6), // Vibrant Azure
                                              Color(0xFF60A5FA), // Cyan blue
                                              Color(0xFFBAE6FD), // Light ice blue
                                              Color(0xFFFFFFFF), // Core white glow
                                            ],
                                            stops: [0.0, 0.45, 0.85, 1.0],
                                          ),
                                        ),
                                      ),

                                      // 3D Glass Top Reflection Sheen
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: 10,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Color(0xA6FFFFFF),
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
                                              width: 50,
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Color(0x00FFFFFF),
                                                    Color(0x66FFFFFF),
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

                    const SizedBox(height: 14),

                    // "Fetching data..." + Sparkle Star Row
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Centered "Fetching data..." with animated trailing dots
                        AnimatedBuilder(
                          animation: _loadingController,
                          builder: (context, _) {
                            final dotIndex =
                                ((_loadingController.value * 8).toInt() % 4);
                            final dots = '.' * dotIndex;

                            return Text(
                              'Fetching data$dots',
                              style: const TextStyle(
                                color: Color(0xEB8BB5E8),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.7,
                                shadows: [
                                  Shadow(
                                    color: Color(0x801E6FD9),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // Four-pointed sparkle star on the right side
                        Positioned(
                          right: 8,
                          child: AnimatedBuilder(
                            animation: _sparkleController,
                            builder: (context, _) {
                              final scale =
                                  0.85 + (_sparkleController.value * 0.35);
                              final opacity =
                                  0.65 + (_sparkleController.value * 0.35);
                              return Transform.scale(
                                scale: scale,
                                child: Opacity(
                                  opacity: opacity,
                                  child: const SparkleStar(
                                    size: 16,
                                    color: Color(0xFF9CC3F3),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 4-pointed diamond sparkle star matching the graphic
class SparkleStar extends StatelessWidget {
  final double size;
  final Color color;

  const SparkleStar({
    super.key,
    this.size = 16,
    this.color = const Color(0xFF9CC3F3),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SparkleStarPainter(color: color),
    );
  }
}

class _SparkleStarPainter extends CustomPainter {
  final Color color;

  _SparkleStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rOuter = size.width / 2;
    final rInner = size.width * 0.16;

    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i * math.pi) / 4 - (math.pi / 2);
      final r = (i % 2 == 0) ? rOuter : rInner;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Subtle soft glow behind star
    final glowPaint = Paint()
      ..color = const Color(0x669CC3F3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkleStarPainter oldDelegate) =>
      oldDelegate.color != color;
}
