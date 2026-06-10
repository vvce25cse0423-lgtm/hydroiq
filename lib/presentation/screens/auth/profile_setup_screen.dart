import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../providers/app_providers.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl   = TextEditingController();
  final _ageCtrl    = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _formKey    = GlobalKey<FormState>();
  String _gender = 'male';
  bool _loading = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // Get user from Supabase directly — works even if session is fresh
      final supabase = Supabase.instance.client;
      
      // Try currentUser first, then session user
      User? user = supabase.auth.currentUser;
      
      // If null, try refreshing the session
      if (user == null) {
        try {
          final session = await supabase.auth.refreshSession();
          user = session.user;
        } catch (_) {}
      }

      // If still null, get from current session directly
      if (user == null) {
        user = supabase.auth.currentSession?.user;
      }

      if (user == null) {
        // Last resort: navigate back to login
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      final weight = double.parse(_weightCtrl.text);
      final goal   = (weight * 35).round().clamp(1500, 4000);

      final profile = UserProfile(
        id: user.id,
        email: user.email ?? '',
        name: _nameCtrl.text.trim(),
        gender: _gender,
        age: int.parse(_ageCtrl.text),
        weightKg: weight,
        dailyGoalMl: goal,
        createdAt: DateTime.now(),
      );

      await ref.read(userProfileProvider.notifier).saveProfile(profile);
      if (mounted) Navigator.pushReplacementNamed(context, '/permission-setup');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose(); _weightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D47A1), Color(0xFFF5F9FF)],
            stops: [0, 0.4],
          ),
        ),
        child: SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(key: _formKey, child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text("Let's set up\nyour profile",
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800,
                      color: Colors.white, height: 1.2)),
              const SizedBox(height: 8),
              Text('We use this to personalize your hydration goals',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15)),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                      blurRadius: 20, offset: const Offset(0, 8))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null),
                  const SizedBox(height: 16),
                  const Text('Gender',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _GenderChip(label: '♂ Male',   value: 'male',
                        selected: _gender == 'male',   onTap: () => setState(() => _gender = 'male')),
                    const SizedBox(width: 10),
                    _GenderChip(label: '♀ Female', value: 'female',
                        selected: _gender == 'female', onTap: () => setState(() => _gender = 'female')),
                    const SizedBox(width: 10),
                    _GenderChip(label: '⚧ Other',  value: 'other',
                        selected: _gender == 'other',  onTap: () => setState(() => _gender = 'other')),
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age (years)',
                        prefixIcon: Icon(Icons.cake_outlined)),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 5 || n > 120 ? 'Enter age (5–120)' : null;
                    }),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Weight (kg)',
                        prefixIcon: Icon(Icons.monitor_weight_outlined)),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      return n == null || n < 20 || n > 300 ? 'Enter weight (20–300 kg)' : null;
                    }),
                  const SizedBox(height: 28),
                  SizedBox(height: 56, child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text('Continue →'))),
                ]),
              ),
            ],
          )),
        )),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _GenderChip({required this.label, required this.value,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primaryBlue : Colors.grey.withOpacity(0.3))),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ));
  }
}
