import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/notification_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _loading = false, _googleLoading = false, _obscure = true;
  String? _error;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    if (AppConstants.isSupabaseConfigured) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateAfterAuth(session.user.id);
          }
        });
      }

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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (!mounted) return;

      if (res.user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString(AppConstants.keyUserId, res.user!.id);
        if (res.user!.email != null) {
          await prefs.setString(AppConstants.keyUserEmail, res.user!.email!);
        }

        // Reload profile provider after sign-in
        ref.invalidate(userProfileProvider);
        // Schedule hydration notifications
        unawaited(NotificationService().scheduleHydrationReminders());
        await _navigateAfterAuth(res.user!.id);
      } else {
        setState(() => _error = 'Sign in failed. Please check your credentials.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
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
    final permissionsSetup = prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;

    try {
      final profile = await Supabase.instance.client
          .from('users').select().eq('id', userId).maybeSingle();
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
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailCtrl.dispose();
    _passCtrl.dispose();
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
      // Screen is wider than image (fitted by width)
      renderedW = size.width;
      renderedH = size.width / imgAR;
      offsetX = 0;
      offsetY = (size.height - renderedH) / 2.0;
    } else {
      // Screen is taller than image (fitted by height)
      renderedH = size.height;
      renderedW = size.height * imgAR;
      offsetY = 0;
      offsetX = (size.width - renderedW) / 2.0;
    }

    // Exact bounding box of the container inside the template:
    // Left: 41px, Top: 358px, Width: 378px, Corner Radius: 28px
    final double lockedLeft   = offsetX + renderedW * (41.0 / imgW);
    final double lockedTop    = offsetY + renderedH * (358.0 / imgH);
    final double lockedWidth  = renderedW * (378.0 / imgW);
    final double lockedRadius = renderedW * (28.0 / imgW);

    // Compact card content height is ~348dp.
    // Ensure the card top leaves enough space above the screen bottom so all elements
    // (down to "Don't have an account? Sign Up") are 100% visible on screen without scrolling.
    const double approxCardHeight = 348.0;
    final double maxAllowedTop = size.height - approxCardHeight - 16.0;
    final double baseTop = math.min(lockedTop, math.max(16.0, maxAllowedTop));

    // If keyboard is open, smoothly lift the card so inputs remain clearly visible
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
      resizeToAvoidBottomInset: false, // Handled via animated activeTop
      body: Stack(
        children: [
          // 1. Fullscreen Photorealistic Template Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_background.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
          ),

          // 2. The Locked "Welcome back!" Container
          // Anchored cleanly below the divider, fully visible from title
          // to "Don't have an account? Sign Up" without requiring any scrolling.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            left: lockedLeft,
            top: activeTop,
            width: lockedWidth,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FBFE), // Solid clean frosted white background
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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Title
                        const Text(
                          'Welcome back!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F2A59),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Subtitle
                        const Text(
                          'Sign in to continue your hydration journey',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        // Error Message Banner (if any)
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: Color(0xFFDC2626), size: 15),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFDC2626),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Email Input Pill Field
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                          ),
                          child: Center(
                            child: TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E293B),
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  Icons.mail_outline_rounded,
                                  color: Color(0xFF64748B),
                                  size: 18,
                                ),
                                hintText: 'Email',
                                hintStyle: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                              validator: (v) =>
                                  v == null || !v.contains('@')
                                      ? 'Enter a valid email'
                                      : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 9),

                        // Password Input Pill Field
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1.0,
                            ),
                          ),
                          child: Center(
                            child: TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _login(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E293B),
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF64748B),
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  splashRadius: 16,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF64748B),
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                hintText: 'Password',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              validator: (v) =>
                                  v == null || v.length < 6
                                      ? 'Min 6 characters'
                                      : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // "Sign In ->" Gradient Action Button
                        Container(
                          height: 45,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF007BFF), // Vibrant ocean blue
                                Color(0xFF00B4D8), // Cyan blue glow
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
                                  : _login,
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
                                            'Sign In',
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

                        const SizedBox(height: 10),

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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10),
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

                        const SizedBox(height: 10),

                        // "Sign in with Google" White Pill Button
                        Container(
                          height: 44,
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
                                  : _loginWithGoogle,
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
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Footer: "Don't have an account? Sign Up"
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account? ",
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12.5,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                  context, '/signup'),
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: Color(0xFF0284C7),
                                  fontSize: 12.5,
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
}
