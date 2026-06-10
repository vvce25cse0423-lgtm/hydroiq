import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_models.dart';

class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ─── AUTH ────────────────────────────────────────────────────────────────

  Future<AuthResponse> signUp(String email, String password) async {
    try {
      return await _client.auth.signUp(email: email, password: password);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Connection failed. Please check your internet and try again.');
    }
  }

  Future<AuthResponse> signIn(String email, String password) async {
    try {
      return await _client.auth.signInWithPassword(
          email: email, password: password);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Connection failed. Please check your internet and try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }

  User? get currentUser =>
      _client.auth.currentUser ?? _client.auth.currentSession?.user;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ─── USER PROFILE ────────────────────────────────────────────────────────

  Future<void> upsertProfile(UserProfile profile) async {
    await _client.from('users').upsert(profile.toMap());
  }

  Future<UserProfile?> getProfile(String userId) async {
    try {
      final data = await _client.from('users').select()
          .eq('id', userId).maybeSingle();
      if (data == null) return null;
      return UserProfile.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    await _client.from('users').update(updates).eq('id', userId);
  }

  // ─── HYDRATION LOGS ──────────────────────────────────────────────────────

  Future<void> addHydrationLog(HydrationLog log) async {
    await _client.from('hydration_logs').insert(log.toMap());
  }

  Future<List<HydrationLog>> getHydrationLogsForDate(
      String userId, DateTime date) async {
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      final data = await _client.from('hydration_logs').select()
          .eq('user_id', userId)
          .gte('logged_at', start.toIso8601String())
          .lt('logged_at', end.toIso8601String())
          .order('logged_at', ascending: false);
      return (data as List).map((e) => HydrationLog.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<HydrationLog>> getHydrationLogsForRange(
      String userId, DateTime start, DateTime end) async {
    try {
      final data = await _client.from('hydration_logs').select()
          .eq('user_id', userId)
          .gte('logged_at', start.toIso8601String())
          .lt('logged_at', end.toIso8601String())
          .order('logged_at');
      return (data as List).map((e) => HydrationLog.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteHydrationLog(String logId) async {
    await _client.from('hydration_logs').delete().eq('id', logId);
  }

  // ─── STEP LOGS ───────────────────────────────────────────────────────────

  Future<void> upsertStepLog(StepLog log) async {
    await _client.from('step_logs').upsert(log.toMap(), onConflict: 'user_id,date');
  }

  Future<List<StepLog>> getStepLogsForRange(
      String userId, DateTime start, DateTime end) async {
    try {
      final data = await _client.from('step_logs').select()
          .eq('user_id', userId)
          .gte('date', start.toIso8601String())
          .lt('date', end.toIso8601String())
          .order('date');
      return (data as List).map((e) => StepLog.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── SLEEP LOGS ──────────────────────────────────────────────────────────

  Future<void> addSleepLog(SleepLog log) async {
    await _client.from('sleep_logs').insert(log.toMap());
  }

  Future<List<SleepLog>> getRecentSleepLogs(String userId, int days) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final data = await _client.from('sleep_logs').select()
          .eq('user_id', userId)
          .gte('sleep_start', since.toIso8601String())
          .order('sleep_start', ascending: false);
      return (data as List).map((e) => SleepLog.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── AI CHAT ─────────────────────────────────────────────────────────────

  Future<void> saveChat(String userId, List<ChatMessage> messages) async {
    await _client.from('ai_chats').upsert({
      'user_id': userId,
      'messages': messages.map((m) => m.toMap()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<List<ChatMessage>> loadChat(String userId) async {
    try {
      final data = await _client.from('ai_chats').select()
          .eq('user_id', userId).maybeSingle();
      if (data == null) return [];
      final messages = data['messages'] as List? ?? [];
      return messages.map((m) => ChatMessage.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearChat(String userId) async {
    await _client.from('ai_chats').delete().eq('user_id', userId);
  }

  // ─── SETTINGS ────────────────────────────────────────────────────────────

  Future<void> saveSettings(String userId, Map<String, dynamic> settings) async {
    await _client.from('settings').upsert(
        {'user_id': userId, ...settings}, onConflict: 'user_id');
  }

  Future<Map<String, dynamic>?> getSettings(String userId) async {
    try {
      return await _client.from('settings').select()
          .eq('user_id', userId).maybeSingle();
    } catch (_) {
      return null;
    }
  }
}
