import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
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
  bool _loading = false, _obscure = true;
  String? _error;
  String? _successMsg;

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });

    try {
      final supabase = Supabase.instance.client;

      final res = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      if (!mounted) return;

      if (res.user != null && res.session != null) {
        // Signed up and auto-confirmed (email confirm disabled)
        ref.invalidate(userProfileProvider);
        await _navigateAfterAuth();
      } else if (res.user != null && res.session == null) {
        // Email confirmation required — attempt immediate sign-in anyway
        try {
          final signInRes = await supabase.auth.signInWithPassword(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
          if (!mounted) return;
          if (signInRes.session != null) {
            ref.invalidate(userProfileProvider);
            await _navigateAfterAuth();
          } else {
            setState(() => _successMsg =
                'Account created! Please check your email to confirm, then sign in.');
          }
        } catch (_) {
          if (mounted) {
            setState(() => _successMsg =
                'Account created! Please check your email to confirm, then sign in.');
          }
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

  Future<void> _navigateAfterAuth() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final permissionsSetup = prefs.getBool(AppConstants.keyPermissionsSetup) ?? false;
    // New user — always go to profile setup first
    if (!permissionsSetup) {
      Navigator.pushReplacementNamed(context, '/profile-setup');
    } else {
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose(); _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          height: size.height,
          child: Column(children: [
            Container(
              height: size.height * 0.28,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF0D47A1), Color(0xFF00BCD4)]),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40))),
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🚀', style: TextStyle(fontSize: 52)),
                SizedBox(height: 10),
                Text('Create Account', style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                SizedBox(height: 4),
                Text('Start your hydration journey',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ])),
            ),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Form(key: _formKey, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: AppTheme.errorRed, fontSize: 13))),
                    ]),
                  ),
                  if (_successMsg != null) Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.mail_outline, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_successMsg!,
                          style: const TextStyle(color: Colors.orange, fontSize: 13))),
                    ]),
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'Enter a valid email' : null),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure))),
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min 6 characters' : null),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signup(),
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) =>
                        v != _passCtrl.text ? 'Passwords do not match' : null),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                      child: _loading
                          ? const SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Create Account',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Already have an account? '),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: const Text('Sign In', style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700))),
                  ]),
                ],
              )),
            )),
          ]),
        ),
      ),
    );
  }
}
