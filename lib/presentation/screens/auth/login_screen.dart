import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/notification_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
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
    final size = MediaQuery.of(context).size;
    final topSpacerHeight = math.max(size.height * 0.28, 170.0);

    return Scaffold(
      backgroundColor: const Color(0xFFE8F2FC),
      body: Stack(
        children: [
          // 1. Fullscreen Photorealistic Template Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_background.jpg',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),

          // 2. Interactive Foreground Elements
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top spacing to position the Card right below the header divider
                    SizedBox(height: topSpacerHeight),

                    // The Exact Login Card
                    Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
                      decoration: BoxDecoration(
                        color: const Color(0xF7FFFFFF), // Frosted glass white
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.9),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F0F254B),
                            blurRadius: 28,
                            offset: Offset(0, 10),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
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
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F2A59),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Subtitle
                            const Text(
                              'Sign in to continue your hydration journey',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w400,
                              ),
                            ),

                            // Error Message Banner (if any)
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFFCA5A5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: Color(0xFFDC2626), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Color(0xFFDC2626),
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 22),

                            // Email Input Pill Field
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(16),
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
                                    fontSize: 14.5,
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    prefixIcon: Icon(
                                      Icons.mail_outline_rounded,
                                      color: Color(0xFF64748B),
                                      size: 20,
                                    ),
                                    hintText: 'Email',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 15),
                                  ),
                                  validator: (v) =>
                                      v == null || !v.contains('@')
                                          ? 'Enter a valid email'
                                          : null,
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Password Input Pill Field
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(16),
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
                                    fontSize: 14.5,
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF64748B),
                                      size: 20,
                                    ),
                                    suffixIcon: IconButton(
                                      splashRadius: 18,
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: const Color(0xFF64748B),
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                    hintText: 'Password',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 15),
                                  ),
                                  validator: (v) =>
                                      v == null || v.length < 6
                                          ? 'Min 6 characters'
                                          : null,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // "Sign In ->" Gradient Action Button
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
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
                                    color: Color(0x4D0080FF),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: (_loading || _googleLoading)
                                      ? null
                                      : _login,
                                  child: Center(
                                    child: _loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.2,
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
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

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
                                      horizontal: 14),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 11.5,
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

                            const SizedBox(height: 18),

                            // "Sign in with Google" White Pill Button
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1.0,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: (_loading || _googleLoading)
                                      ? null
                                      : _loginWithGoogle,
                                  child: Center(
                                    child: _googleLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
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
                                                width: 20,
                                                height: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              const Text(
                                                'Sign in with Google',
                                                style: TextStyle(
                                                  color: Color(0xFF334155),
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Footer: "Don't have an account? Sign Up"
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13.5,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.pushReplacementNamed(
                                      context, '/signup'),
                                  child: const Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      color: Color(0xFF0284C7),
                                      fontSize: 13.5,
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

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
