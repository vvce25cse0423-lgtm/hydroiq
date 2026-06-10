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
      state = AsyncValue.data(profile);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _service.upsertProfile(profile);
    state = AsyncValue.data(profile);
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final user = _service.currentUser;
    if (user == null) return;
    await _service.updateProfile(user.id, updates);
    await loadProfile();
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
    loadToday();
  }

  Future<void> loadToday() async {
    final user = _service.currentUser;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
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
    NotificationService().updateProgress(currentMl: total, goalMl: AppConstants.defaultDailyGoalMl);
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
  return WeatherNotifier(ref.watch(weatherServiceProvider));
});

class WeatherNotifier extends StateNotifier<AsyncValue<WeatherData?>> {
  final WeatherService _service;

  WeatherNotifier(this._service) : super(const AsyncValue.data(null));

  Future<void> fetchByCoords(double lat, double lon) async {
    state = const AsyncValue.loading();
    try {
      final data = await _service.fetchByCoordinates(lat, lon);
      state = AsyncValue.data(data);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> fetchByCity(String city) async {
    state = const AsyncValue.loading();
    try {
      final data = await _service.fetchByCity(city);
      state = AsyncValue.data(data);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }
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

final smartGoalProvider = Provider<int>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final weather = ref.watch(weatherProvider).valueOrNull;
  final steps = ref.watch(todayStepsProvider);

  if (profile == null) return AppConstants.defaultDailyGoalMl;

  // Base calculation: weight × 35 ml/kg
  double base = profile.weightKg * 35;

  // Gender adjustment
  if (profile.gender == 'male') base += 200;

  // Age adjustment
  if (profile.age > 60) base -= 200;
  if (profile.age < 18) base -= 100;

  // Weather adjustment
  if (weather != null) {
    base += weather.recommendedExtraMl;
  }

  // Step adjustment: +200ml per 5000 steps
  base += (steps / 5000) * 200;

  return base.round().clamp(1500, 4000);
});
