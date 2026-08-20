import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/app_models.dart';
import '../data/services/supabase_service.dart';
import '../data/services/weather_service.dart';
import '../data/services/ai_service.dart';
import '../core/constants/app_constants.dart';
import '../data/services/notification_service.dart';

// ─── CORE SERVICES ────────────────────────────────────────────────────────────

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService();
});

final aiServiceProvider = Provider<AiService>((ref) {
  return AiService();
});

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

// ─── AUTH ─────────────────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseServiceProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseServiceProvider).currentUser;
});

// ─── THEME ────────────────────────────────────────────────────────────────────

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, bool>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<bool> {
  ThemeModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(AppConstants.keyThemeMode) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyThemeMode, state);
  }
}

// ─── USER PROFILE ─────────────────────────────────────────────────────────────

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  return UserProfileNotifier(ref.watch(supabaseServiceProvider));
});

class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final SupabaseService _service;

  UserProfileNotifier(this._service) : super(const AsyncValue.loading()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = _service.currentUser;
    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      final profile = await _service.getProfile(user.id);
      // Cache weightKg locally so smartGoalProvider fallback & notification
      // progress bar always have a fresh weight even without re-saving profile.
      if (profile != null && profile.weightKg > 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(AppConstants.keyWeightKg, profile.weightKg);
      }
      state = AsyncValue.data(profile);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _service.upsertProfile(profile);
    // Cache weightKg locally so HydrationNotifier can derive the correct goal
    // without a network call (fixes stale 6L issue from DB daily_goal_ml).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(AppConstants.keyWeightKg, profile.weightKg);
    state = AsyncValue.data(profile);
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final user = _service.currentUser;
    if (user == null) return;
    await _service.updateProfile(user.id, updates);
    await loadProfile();
  }

  /// Store today's addon (weather/sleep/steps) in SharedPreferences.
  /// daily_goal_ml on the profile stays as weight-based baseline only.
  static const kAddonDate    = 'goal_addon_date';
  static const kAddonWeather = 'goal_addon_weather';
  static const kAddonSleep   = 'goal_addon_sleep';
  static const kAddonSteps   = 'goal_addon_steps';

  static Future<void> setAddon(String key, int ml) async {
    final prefs   = await SharedPreferences.getInstance();
    final today   = DateTime.now().toIso8601String().substring(0, 10);
    final stored  = prefs.getString(kAddonDate) ?? '';
    if (stored != today) {
      // New day — wipe all addons
      await prefs.setString(kAddonDate, today);
      await prefs.setInt(kAddonWeather, 0);
      await prefs.setInt(kAddonSleep,   0);
      await prefs.setInt(kAddonSteps,   0);
    }
    await prefs.setInt(key, ml);
  }

  static Future<int> getTodayTotal() async {
    final prefs  = await SharedPreferences.getInstance();
    final today  = DateTime.now().toIso8601String().substring(0, 10);
    final stored = prefs.getString(kAddonDate) ?? '';
    if (stored != today) return 0;
    return (prefs.getInt(kAddonWeather) ?? 0) +
           (prefs.getInt(kAddonSleep)   ?? 0) +
           (prefs.getInt(kAddonSteps)   ?? 0);
  }

  // Keep for backward compat — now just invalidates smartGoalProvider via loadProfile
  Future<void> addToGoal(int extraMl) async {
    // no-op: addons are stored in SharedPreferences, not in profile
  }
}

// ─── HYDRATION ────────────────────────────────────────────────────────────────

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final todayLogsProvider =
    StateNotifierProvider<HydrationNotifier, AsyncValue<List<HydrationLog>>>(
        (ref) {
  return HydrationNotifier(ref.watch(supabaseServiceProvider));
});

class HydrationNotifier
    extends StateNotifier<AsyncValue<List<HydrationLog>>> {
  final SupabaseService _service;

  HydrationNotifier(this._service) : super(const AsyncValue.loading()) {
    _initAndCheckDay();
  }

  static const String _lastDayKey = 'hydration_last_active_date';

  Future<void> _initAndCheckDay() async {
    await _checkNewDay();
    await loadToday();
  }

  /// On a new calendar day: the goal persists, logs reset automatically
  /// because loadToday() queries by date. No action needed except to
  /// record today's date so we know when the next new day arrives.
  Future<void> _checkNewDay() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final lastStr  = prefs.getString(_lastDayKey) ?? '';
      if (lastStr != todayStr) {
        // New day — save today's date. Logs are fetched fresh by loadToday().
        await prefs.setString(_lastDayKey, todayStr);
      }
    } catch (_) {}
  }

  Future<void> loadToday() async {
    final user = _service.currentUser;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      // Always check day on every load (handles midnight crossover while app open)
      await _checkNewDay();
      final logs =
          await _service.getHydrationLogsForDate(user.id, DateTime.now());
      state = AsyncValue.data(logs);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> addLog(int amountMl, {String? note}) async {
    final user = _service.currentUser;
    if (user == null) return;

    final log = HydrationLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: user.id,
      amountMl: amountMl,
      loggedAt: DateTime.now(),
      note: note,
    );

    await _service.addHydrationLog(log);
    await loadToday();

    // Update the persistent notification progress bar
    final total = totalMlToday;
    // Derive goal from weight stored in SharedPrefs (written by UserProfileNotifier.saveProfile).
    // Falls back to keyDailyGoalMl so old installs still work.
    final prefs2  = await SharedPreferences.getInstance();
    final storedWeight = prefs2.getDouble(AppConstants.keyWeightKg) ?? 0.0;
    final goalMl  = storedWeight > 0
        ? (storedWeight * 35).round().clamp(1500, 6000)
        : (prefs2.getInt(AppConstants.keyDailyGoalMl) ?? AppConstants.defaultDailyGoalMl);
    NotificationService().updateProgress(currentMl: total, goalMl: goalMl);
    // Update home screen widget
  }

  Future<void> deleteLog(String logId) async {
    await _service.deleteHydrationLog(logId);
    await loadToday();
  }

  int get totalMlToday {
    return state.whenOrNull(
          data: (logs) => logs.fold<int>(0, (sum, l) => sum + l.amountMl),
        ) ??
        0;
  }
}

final todayTotalProvider = Provider<int>((ref) {
  return ref.watch(todayLogsProvider).whenOrNull(
        data: (logs) => logs.fold<int>(0, (sum, l) => sum + l.amountMl),
      ) ??
      0;
});

// ─── WEATHER ─────────────────────────────────────────────────────────────────

final weatherProvider =
    StateNotifierProvider<WeatherNotifier, AsyncValue<WeatherData?>>((ref) {
  return WeatherNotifier(ref.watch(weatherServiceProvider), ref);
});

class WeatherNotifier extends StateNotifier<AsyncValue<WeatherData?>> {
  final WeatherService _service;
  final Ref _ref;

  WeatherNotifier(this._service, this._ref) : super(const AsyncValue.data(null));

  Future<void> _applyWeatherGoal(WeatherData data) async {
    if (data.recommendedExtraMl <= 0) return;
    try {
      // Store weather addon for today — auto-resets on new day
      await UserProfileNotifier.setAddon(
          UserProfileNotifier.kAddonWeather, data.recommendedExtraMl);
      // Invalidate smartGoalProvider so UI rebuilds
      _ref.invalidate(todayAddonProvider);
    } catch (_) {}
  }

  Future<void> fetchByCoords(double lat, double lon) async {
    state = const AsyncValue.loading();
    try {
      final data = await _service.fetchByCoordinates(lat, lon);
      state = AsyncValue.data(data);
      await _applyWeatherGoal(data);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> fetchByCity(String city) async {
    if (city.trim().isEmpty) return;
    state = const AsyncValue.loading();
    try {
      final data = await _service.fetchByCity(city.trim());
      state = AsyncValue.data(data);
      await _applyWeatherGoal(data);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  void clearError() => state = const AsyncValue.data(null);
}

// ─── STEPS ───────────────────────────────────────────────────────────────────

final todayStepsProvider = StateNotifierProvider<StepsNotifier, int>((ref) {
  return StepsNotifier();
});

class StepsNotifier extends StateNotifier<int> {
  StepsNotifier() : super(0);

  void update(int steps) => state = steps;
}

// ─── AI CHAT ─────────────────────────────────────────────────────────────────

final chatMessagesProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier(
    ref.watch(aiServiceProvider),
    ref.watch(supabaseServiceProvider),
  );
});

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final AiService _ai;
  final SupabaseService _supabase;
  bool _isLoading = false;

  ChatNotifier(this._ai, this._supabase) : super([]) {
    _loadHistory();
  }

  bool get isLoading => _isLoading;

  Future<void> _loadHistory() async {
    final user = _supabase.currentUser;
    if (user == null) return;
    try {
      final msgs = await _supabase.loadChat(user.id);
      state = msgs;
    } catch (_) {}
  }

  Future<void> sendMessage(String text) async {
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    state = [...state, userMsg];
    _isLoading = true;

    final history = state
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final response = await _ai.sendMessage(text, history);

    final aiMsg = ChatMessage(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      role: 'assistant',
      content: response,
      timestamp: DateTime.now(),
    );
    state = [...state, aiMsg];
    _isLoading = false;

    // Persist to Supabase
    final user = _supabase.currentUser;
    if (user != null) {
      await _supabase.saveChat(user.id, state);
    }
  }

  Future<void> clearHistory() async {
    state = [];
    final user = _supabase.currentUser;
    if (user != null) {
      await _supabase.clearChat(user.id);
    }
  }
}

// ─── SMART RECOMMENDATION ─────────────────────────────────────────────────────

// Reactive addon provider — refreshed whenever invalidated
final todayAddonProvider = FutureProvider<int>((ref) async {
  return UserProfileNotifier.getTodayTotal();
});

final smartGoalProvider = Provider<int>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null) return AppConstants.defaultDailyGoalMl;

  // Always derive baseline fresh from weightKg so a stale daily_goal_ml
  // value in the DB (e.g. clamped 6000 from an old sign-up) never overrides
  // the correct weight-based calculation shown on the profile screen.
  final baseline = profile.weightKg > 0
      ? (profile.weightKg * 35).round().clamp(1500, 6000)
      : AppConstants.defaultDailyGoalMl;

  // Add today's addons (weather + sleep + steps) — sync read from addon provider
  final addon = ref.watch(todayAddonProvider).valueOrNull ?? 0;
  return (baseline + addon).clamp(1500, 9000);
});
