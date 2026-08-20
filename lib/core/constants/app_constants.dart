class AppConstants {
  AppConstants._();

  static const String appName       = 'HydroIQ';
  static const String appVersion    = '1.0.0';
  static const String privacyPolicyUrl = 'https://hydroiq.app/privacy-policy';

  // Keys from --dart-define; fall back to your actual project values
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nmnkkmmjevcvvfzifbbn.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_TOvECK5SJrnK5bGawJDU0g_FvB_17PT',
  );
  static const String weatherApiKey = String.fromEnvironment(
    'WEATHER_API_KEY', defaultValue: '');
  static const String weatherBaseUrl =
      'https://api.openweathermap.org/data/2.5';

  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY', defaultValue: '');
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  static const String keyOnboardingDone     = 'onboarding_done';
  static const String keyUserId             = 'user_id';
  static const String keyUserEmail          = 'user_email';
  static const String keyThemeMode          = 'theme_mode';
  static const String keyPermissionsSetup   = 'permissions_setup';
  static const String keyLocationPermission = 'perm_location';
  static const String keyActivityPermission = 'perm_activity';
  static const String keyMicPermission      = 'perm_microphone';
  static const String keyNotifPermission    = 'perm_notification';
  static const String keyStoragePermission  = 'perm_storage';
  static const String keyManualCity         = 'manual_city';
  static const String keyDailyGoalMl        = 'daily_goal_ml';
  static const String keyWeightKg            = 'user_weight_kg';
  static const String keyLastSyncDate       = 'last_sync_date';

  static const int defaultDailyGoalMl    = 2000;
  static const List<int> quickAddAmounts = [100, 250, 500, 1000];

  static const int notifReminderId = 1001;
  static const int notifGoalId     = 1002;
  static const int notifStreakId   = 1003;

  static const double strideLength    = 0.762;
  static const double caloriesPerStep = 0.04;
  static const int sleepGoalHours     = 8;
}
