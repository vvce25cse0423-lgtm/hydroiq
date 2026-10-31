import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/notification_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/app_providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey     = GlobalKey<FormState>();

  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _successMsg;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (AppConstants.isSupabaseConfigured) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (session != null && mounted) {
          ref.invalidate(userProfileProvider);
          unawaited(NotificationService().scheduleHydrationReminders());
          _navigateAfterAuth(session.user.id);
        }
      });
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _successMsg = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final res = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (!mounted) return;

      if (res.user != null && res.session != null) {
        // Direct session established
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString(AppConstants.keyUserId, res.user!.id);
        if (res.user!.email != null) {
          await prefs.setString(AppConstants.keyUserEmail, res.user!.email!);
        }

        ref.invalidate(userProfileProvider);
        unawaited(NotificationService().scheduleHydrationReminders());
        await _navigateAfterAuth(res.user!.id);
      } else if (res.user != null && res.session == null) {
        // Confirmation email may be required — attempt direct sign in
        try {
          final signInRes = await supabase.auth.signInWithPassword(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
          if (!mounted) return;
          if (signInRes.session != null && signInRes.user != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_logged_in', true);
            await prefs.setString(AppConstants.keyUserId, signInRes.user!.id);
            if (signInRes.user!.email != null) {
              await prefs.setString(AppConstants.keyUserEmail, signInRes.user!.email!);
            }
            ref.invalidate(userProfileProvider);
            unawaited(NotificationService().scheduleHydrationReminders());
            await _navigateAfterAuth(signInRes.user!.id);
            return;
          }
        } catch (_) {
          // Fall through to notification banner
        }

        if (mounted) {
          setState(() => _successMsg =
              'Account created! Please check your email to confirm, then sign in.');
        }
      } else {
        setState(() => _error = 'Sign up failed. Please try again.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Sign up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
      _successMsg = null;
    });
    try {
      if (!AppConstants.isSupabaseConfigured) {
        setState(() => _error = 'Supabase credentials are not configured.');
        return;
      }
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.hydroiq://login-callback/',
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Google Sign In failed. Please try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _navigateAfterAuth(String userId) async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString(AppConstants.keyUserId, userId);
    final permissionsSetup =
        prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;

    try {
      final profile = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
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
      Navigator.pushReplacementNamed(context, '/profile-setup');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final keyboardInset = mediaQuery.viewInsets.bottom;

    // Background image template aspect ratio: 460 x 1024
    const double imgW = 460.0;
    const double imgH = 1024.0;
    const double imgAR = imgW / imgH; // ~0.4492
    final double screenAR = size.width / size.height;

    double renderedW;
    double renderedH;
    double offsetX;
    double offsetY;

    if (screenAR > imgAR) {
      renderedW = size.width;
      renderedH = size.width / imgAR;
      offsetX = 0;
      offsetY = (size.height - renderedH) / 2.0;
    } else {
      renderedH = size.height;
      renderedW = size.height * imgAR;
      offsetY = 0;
      offsetX = (size.width - renderedW) / 2.0;
    }

    // Exact bounding box of the card in the template:
    // Left: 41px, Top: 352px, Width: 378px, Corner Radius: 28px
    final double lockedLeft   = offsetX + renderedW * (41.0 / imgW);
    final double lockedTop    = offsetY + renderedH * (352.0 / imgH);
    final double lockedWidth  = renderedW * (378.0 / imgW);
    final double lockedRadius = renderedW * (28.0 / imgW);

    // Card content height is ~395dp.
    // Ensure the card fits comfortably on screen without scrolling:
    const double approxCardHeight = 400.0;
    final double maxAllowedTop = size.height - approxCardHeight - 16.0;
    final double baseTop = math.min(lockedTop, math.max(16.0, maxAllowedTop));

    // Smoothly lift the card when the keyboard is active
    double activeTop = baseTop;
    if (keyboardInset > 0) {
      final availableBottom = size.height - keyboardInset - 12.0;
      final cardBottom = baseTop + approxCardHeight;
      if (cardBottom > availableBottom) {
        activeTop = math.max(12.0, baseTop - (cardBottom - availableBottom));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE8F2FC),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Photorealistic Sign Up Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/signup_background.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
          ),

          // 2. The Interactive "Create Account" Card
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            left: lockedLeft,
            top: activeTop,
            width: lockedWidth,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FBFE),
                borderRadius: BorderRadius.circular(lockedRadius),
                border: Border.all(
                  color: Colors.white,
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x240F254B),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(lockedRadius),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title: "Create Account"
                        const Text(
                          'Create Account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F2A59),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Subtitle: "Start your hydration journey"
                        const Text(
                          'Start your hydration journey',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B607E),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Cyan Curved Accent Arc Underline
                        Center(
                          child: CustomPaint(
                            size: const Size(88, 6),
                            painter: _CyanSwooshPainter(),
                          ),
                        ),

                        // Error Banner (if any)
                        if (_error != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: Color(0xFFDC2626), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFDC2626),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Success Message Banner (if any)
                        if (_successMsg != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFF93C5FD)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.mark_email_read_rounded,
                                    color: Color(0xFF2563EB), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _successMsg!,
                                    style: const TextStyle(
                                      color: Color(0xFF1E40AF),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Input 1: Email
                        _buildInputField(
                          controller: _emailCtrl,
                          hintText: 'Email',
                          prefixIcon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter your email';
                            }
                            if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$')
                                .hasMatch(v.trim())) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 8),

                        // Input 2: Password
                        _buildInputField(
                          controller: _passCtrl,
                          hintText: 'Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscureText: _obscurePass,
                          textInputAction: TextInputAction.next,
                          suffixIcon: GestureDetector(
                            onTap: () =>
                                setState(() => _obscurePass = !_obscurePass),
                            child: Icon(
                              _obscurePass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                              size: 17,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Enter a password';
                            }
                            if (v.length < 6) {
                              return 'Min 6 characters';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 8),

                        // Input 3: Confirm Password
                        _buildInputField(
                          controller: _confirmCtrl,
                          hintText: 'Confirm Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _signup(),
                          suffixIcon: GestureDetector(
                            onTap: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                            child: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                              size: 17,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Confirm your password';
                            }
                            if (v != _passCtrl.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 11),

                        // Action Button: "Create Account ->"
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF007BFF), // Deep ocean blue
                                Color(0xFF00B4D8), // Vibrant cyan glow
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3D0080FF),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: (_loading || _googleLoading)
                                  ? null
                                  : _signup,
                              child: Center(
                                child: _loading
                                    ? const SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.0,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Create Account',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // "OR" Divider
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.grey.shade300,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // "Sign in with Google" White Pill Button
                        Container(
                          height: 43,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x08000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: (_loading || _googleLoading)
                                  ? null
                                  : _signUpWithGoogle,
                              child: Center(
                                child: _googleLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          color: Color(0xFF007BFF),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/icons/google_icon.png',
                                            width: 18,
                                            height: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            'Sign in with Google',
                                            style: TextStyle(
                                              color: Color(0xFF334155),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Footer: "Already have an account? Sign In"
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                  context, '/login'),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: Color(0xFF0284C7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
    FormFieldValidator<String>? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2EAF2),
          width: 1.0,
        ),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              prefixIcon,
              color: const Color(0xFF64748B),
              size: 18,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: suffixIcon,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 38,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        validator: validator,
      ),
    );
  }
}

/// Custom painter for the subtle cyan curved smile/arc under "Start your hydration journey"
class _CyanSwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00C6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, 1);
    path.quadraticBezierTo(size.width / 2, size.height, size.width, 1);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
