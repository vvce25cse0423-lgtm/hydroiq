import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/app_models.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Background callback invoked by Android Home Screen Widget when
/// user taps "+250 ml" or "+500 ml" without opening the app.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;

  if (uri.scheme == 'hydroiq' && (uri.host == 'add' || uri.path.contains('add'))) {
    final amount = int.tryParse(uri.queryParameters['amount'] ?? '') ?? 250;
    final prefs = await SharedPreferences.getInstance();

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final lastDay = prefs.getString('widget_last_day') ?? '';

    int currentMl = prefs.getInt('widget_current_ml_int') ?? 0;
    if (lastDay != todayStr) {
      currentMl = 0;
      await prefs.setString('widget_last_day', todayStr);
    }

    final storedWeight = prefs.getDouble(AppConstants.keyWeightKg) ?? 0.0;
    final goalMl = storedWeight > 0
        ? (storedWeight * 35).round().clamp(1500, 6000)
        : (prefs.getInt(AppConstants.keyDailyGoalMl) ?? AppConstants.defaultDailyGoalMl);

    final newTotal = currentMl + amount;
    await prefs.setInt('widget_current_ml_int', newTotal);

    // Queue pending amount so app adds it to the provider if app is opened later
    final pending = prefs.getInt('pending_widget_added_ml') ?? 0;
    await prefs.setInt('pending_widget_added_ml', pending + amount);

    // Update the widget display immediately
    await WidgetService.updateWidget(currentMl: newTotal, goalMl: goalMl);

    // Update notification progress bar
    try {
      NotificationService().updateProgress(currentMl: newTotal, goalMl: goalMl);
    } catch (_) {}

    // If Supabase is initialized and user is logged in, sync log directly
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final log = HydrationLog(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: user.id,
          amountMl: amount,
          loggedAt: DateTime.now(),
          note: 'Quick-add via Home Screen Widget',
        );
        await SupabaseService().addHydrationLog(log);
        // Clear pending since directly logged
        await prefs.setInt('pending_widget_added_ml', 0);
      }
    } catch (_) {}
  }
}

/// Service to manage HydroIQ Android Home Screen Widget data and updates
class WidgetService {
  WidgetService._();

  static const String appWidgetProvider = 'HydroIQWidgetProvider';

  /// Initialize HomeWidget and register the background interactivity callback
  static Future<void> initialize() async {
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (e) {
      debugPrint('WidgetService.initialize error: $e');
    }
  }

  /// Update widget with latest hydration numbers
  static Future<void> updateWidget({
    required int currentMl,
    required int goalMl,
  }) async {
    try {
      final safeGoal = goalMl > 0 ? goalMl : AppConstants.defaultDailyGoalMl;
      final pct = ((currentMl / safeGoal) * 100).round().clamp(0, 100);

      // Formatted numbers with commas (e.g., "1,250")
      final formattedCurrent = _formatNumber(currentMl);
      final formattedGoal = _formatNumber(safeGoal);

      String statusText;
      if (currentMl >= safeGoal) {
        statusText = '🎉 Daily goal achieved!';
      } else {
        final remaining = safeGoal - currentMl;
        statusText = '💧 ${_formatNumber(remaining)} ml left today';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('widget_current_ml_int', currentMl);
      await prefs.setString('widget_last_day', DateTime.now().toIso8601String().substring(0, 10));

      await HomeWidget.saveWidgetData<String>('current_ml', formattedCurrent);
      await HomeWidget.saveWidgetData<String>('goal_ml', formattedGoal);
      await HomeWidget.saveWidgetData<int>('progress', pct);
      await HomeWidget.saveWidgetData<String>('percentage', '$pct%');
      await HomeWidget.saveWidgetData<String>('status_text', statusText);

      await HomeWidget.updateWidget(
        name: appWidgetProvider,
        androidName: appWidgetProvider,
      );
    } catch (e) {
      debugPrint('WidgetService.updateWidget error: $e');
    }
  }

  static String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
