/// App-wide constants for HydroIQ
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'HydroIQ';
  static const String appVersion = '1.0.0';

  // Supabase
  static const String supabaseUrl = 'https://nmnkkmmjevcvvfzifbbn.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_TOvECK5SJrnK5bGawJDU0g_FvB_17PT';

  // OpenWeatherMap
  static const String weatherApiKey = '624d64f50bcf3cf596ccf7693dce142f';
  static const String weatherBaseUrl = 'https://api.openweathermap.org/data/2.5';

  // Gemini AI
  static const String geminiApiKey = 'AIzaSyDk0vAga4ylbycpRZTEwzLLt2YD2cRqzHE';
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  // SharedPreferences Keys
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyUserId = 'user_id';
  static const String keyUserEmail = 'user_email';
  static const String keyThemeMode = 'theme_mode';
  static const String keyPermissionsSetup = 'permissions_setup';
  static const String keyLocationPermission = 'perm_location';
  static const String keyActivityPermission = 'perm_activity';
  static const String keyMicPermission = 'perm_microphone';
  static const String keyNotifPermission = 'perm_notification';
  static const String keyStoragePermission = 'perm_storage';
  static const String keyManualCity = 'manual_city';
  static const String keyDailyGoalMl = 'daily_goal_ml';
  static const String keyLastSyncDate = 'last_sync_date';

  // Hydration Defaults
  static const int defaultDailyGoalMl = 2000;
  static const List<int> quickAddAmounts = [100, 250, 500, 1000];

  // Notification IDs
  static const int notifReminderId = 1001;
  static const int notifGoalId = 1002;
  static const int notifStreakId = 1003;

  // Step Constants
  static const double strideLength = 0.762; // meters
  static const double caloriesPerStep = 0.04;

  // Sleep Constants
  static const int sleepGoalHours = 8;
}
