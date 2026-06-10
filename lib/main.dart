import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/services/notification_service.dart';
import 'data/services/background_service.dart';
import 'providers/app_providers.dart';
import 'presentation/screens/auth/splash_screen.dart';
import 'presentation/screens/auth/onboarding_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/signup_screen.dart';
import 'presentation/screens/auth/profile_setup_screen.dart';
import 'presentation/screens/permissions/permission_setup_screen.dart';
import 'presentation/screens/dashboard/main_shell.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/weather/weather_screen.dart';

late ProviderContainer _container;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  _container = ProviderContainer();

  // Init services
  await BackgroundService.initialize();
  await NotificationService().initialize();

  // Schedule hourly hydration reminders (8am–10pm)
  await NotificationService().scheduleHydrationReminders();

  // Process pending notification quick-add actions
  await _processPendingNotificationAction(_container);

  runApp(UncontrolledProviderScope(
    container: _container,
    child: const HydroIQApp(),
  ));
}

Future<void> _processPendingNotificationAction(ProviderContainer container) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString('pending_notification_action');
    if (action != null) {
      await prefs.remove('pending_notification_action');
      int ml = 0;
      if (action == NotificationService.actionAdd250) ml = 250;
      if (action == NotificationService.actionAdd500) ml = 500;
      if (ml > 0) {
        Future.delayed(const Duration(seconds: 2), () {
          try {
            container.read(todayLogsProvider.notifier).addLog(ml,
                note: 'Added via notification');
          } catch (_) {}
        });
      }
    }
  } catch (_) {}
}

class HydroIQApp extends ConsumerWidget {
  const HydroIQApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'HydroIQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      routes: {
        '/':                 (ctx) => const SplashScreen(),
        '/onboarding':       (ctx) => const OnboardingScreen(),
        '/login':            (ctx) => const LoginScreen(),
        '/signup':           (ctx) => const SignupScreen(),
        '/profile-setup':    (ctx) => const ProfileSetupScreen(),
        '/permission-setup': (ctx) => const PermissionSetupScreen(),
        '/dashboard':        (ctx) => const MainShell(),
        '/profile':          (ctx) => const ProfileScreen(),
        '/settings':         (ctx) => const SettingsScreen(),
        '/weather':          (ctx) => const WeatherScreen(),
      },
    );
  }
}
