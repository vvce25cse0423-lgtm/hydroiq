import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';

// Keys shared with UI screens
const kStepsToday      = 'steps_today';
const kStepsBaseline   = 'pedometer_day_baseline';
const kStepsBaselineDay= 'pedometer_baseline_day';
const kSleepTracking   = 'sleep_is_tracking';
const kSleepStartMs    = 'sleep_start_ms';
const kPhonePickedUp   = 'sleep_phone_picked_up';
const kLastActiveMs    = 'sleep_last_active_ms';

const _taskSleep       = 'hydroiq_sleep_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();

    if (task == _taskSleep) {
      // Check if sleep should auto-stop based on stored motion flag
      final isTracking = prefs.getBool(kSleepTracking) ?? false;
      if (!isTracking) return Future.value(true);

      final lastActiveMs = prefs.getInt(kLastActiveMs) ?? 0;
      if (lastActiveMs > 0) {
        final lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveMs);
        if (DateTime.now().difference(lastActive).inMinutes >= 5) {
          // Auto-stop sleep
          await prefs.remove(kSleepTracking);
          await prefs.remove(kSleepStartMs);
          await prefs.remove(kLastActiveMs);
          await prefs.remove(kPhonePickedUp);

          await NotificationService().showNotification(
            id: 7001,
            title: '☀️ Good morning!',
            body: 'HydroIQ detected you\'re awake. Sleep logged! Drink some water.',
          );
        }
      }
    }

    return Future.value(true);
  });
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> startSleepMonitoring() async {
    await Workmanager().registerPeriodicTask(
      _taskSleep,
      _taskSleep,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> stopSleepMonitoring() async {
    await Workmanager().cancelByUniqueName(_taskSleep);
  }
}
