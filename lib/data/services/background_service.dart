import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';
import 'sleep_detection_engine.dart';

const kStepsToday       = 'steps_today';
const kStepsBaseline    = 'pedometer_day_baseline';
const kStepsBaselineDay = 'pedometer_baseline_day';

// SharedPrefs key for DND-was-active flag (written by native MainActivity)
const kSleepDndActive = 'sleep_dnd_was_active';

const _taskSleep = 'hydroiq_sleep_monitor';
const _taskSync  = 'hydroiq_health_sync';

const _sleepChannel = MethodChannel('com.hydroiq.app/sleep_controls');

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();

    if (task == _taskSleep) {
      final isTracking = prefs.getBool(kSleepTracking) ?? false;
      if (!isTracking) return true;

      final startMs = prefs.getInt(kSleepStartMs);
      if (startMs == null) return true;

      final start   = DateTime.fromMillisecondsSinceEpoch(startMs);
      final elapsed = DateTime.now().difference(start);

      // Hard cap: > 16h → auto-end
      if (elapsed.inHours >= 16) {
        await prefs.remove(kSleepTracking);
        await prefs.remove(kSleepStartMs);
        await prefs.remove(kSleepInterrupts);
        await prefs.remove(kSleepConfidence);
        await prefs.remove(kLastMotionMs);
        await prefs.remove(kSleepDndActive);
        await NotificationService().showNotification(
          id: 7002,
          title: '⏰ Sleep session ended',
          body: 'Session exceeded 16h and was automatically closed.',
        );
        return true;
      }

      // ── DND fallback check (backup for broadcast receiver on restricted devices) ──
      final dndWasActive = prefs.getBool(kSleepDndActive) ?? false;
      if (dndWasActive) {
        try {
          final isDND = await _sleepChannel
              .invokeMethod<bool>('isDNDEnabled') ?? true;
          if (!isDND) {
            // DND was disabled externally → stop sleep
            await prefs.remove(kSleepTracking);
            await prefs.remove(kSleepStartMs);
            await prefs.remove(kSleepInterrupts);
            await prefs.remove(kSleepConfidence);
            await prefs.remove(kLastMotionMs);
            await prefs.remove(kSleepDndActive);
            await NotificationService().showNotification(
              id: 7004,
              title: '☀️ Sleep tracking stopped',
              body: 'DND was turned off — sleep session ended automatically.',
            );
            return true;
          }
        } catch (_) {
          // MethodChannel may not be available in background isolate on some devices;
          // native BroadcastReceiver handles it instead — safe to ignore.
        }
      }

      // Check last motion timestamp
      final lastMotionMs = prefs.getInt(kLastMotionMs) ?? 0;
      final interrupts   = prefs.getInt(kSleepInterrupts) ?? 0;
      final confidence   = prefs.getDouble(kSleepConfidence) ?? 0.5;

      if (lastMotionMs > 0) {
        final sinceMotion = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastMotionMs))
            .inMinutes;

        // Repeated high-motion + low confidence → notify but don't force stop
        if (sinceMotion < 10 && interrupts > 5 && confidence < 0.25) {
          await NotificationService().showNotification(
            id: 7003,
            title: '📱 HydroIQ Sleep',
            body: 'It looks like you may be awake. Open app to confirm.',
          );
        }
      }
    }

    return true;
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
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> stopSleepMonitoring() async {
    await Workmanager().cancelByUniqueName(_taskSleep);
  }

  static Future<void> scheduleHealthSync() async {
    await Workmanager().registerPeriodicTask(
      _taskSync,
      _taskSync,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}
