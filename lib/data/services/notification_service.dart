import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _quickAddId    = 9001;
  static const String _quickCh   = 'hydroiq_quick_add';
  static const String _mainCh    = 'hydroiq_channel';
  static const String _remCh     = 'hydroiq_reminders';
  static const String _hydrateCh = 'hydroiq_hydrate_remind';

  static const String actionAdd250 = 'add_250';
  static const String actionAdd500 = 'add_500';

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _bgHandler,
    );
    // Request notification permission (Android 13+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await showQuickAddNotification(currentMl: 0, goalMl: 2500);
  }

  void _onResponse(NotificationResponse r) {
    if (r.actionId != null) _storePending(r.actionId!);
  }

  void _storePending(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_notification_action', action);
  }

  // ── Persistent quick-add notification ────────────────────────────────────
  Future<void> showQuickAddNotification({
    required int currentMl,
    required int goalMl,
  }) async {
    final pct = goalMl > 0 ? ((currentMl / goalMl) * 100).round() : 0;
    final androidDetails = AndroidNotificationDetails(
      _quickCh, 'Quick Add Water',
      channelDescription: 'Tap +250ml or +500ml to log water anytime',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: goalMl,
      progress: currentMl,
      icon: '@mipmap/ic_launcher',
      actions: const [
        AndroidNotificationAction(actionAdd250, '+ 250ml',
            showsUserInterface: true, cancelNotification: false),
        AndroidNotificationAction(actionAdd500, '+ 500ml',
            showsUserInterface: true, cancelNotification: false),
      ],
    );
    await _plugin.show(
      _quickAddId,
      '💧 HydroIQ · ${currentMl}ml / ${goalMl}ml ($pct%)',
      'Tap + buttons to log water instantly.',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> updateProgress({required int currentMl, required int goalMl}) =>
      showQuickAddNotification(currentMl: currentMl, goalMl: goalMl);

  // ── Scheduled hydration reminders every 2 hours ───────────────────────────
  Future<void> scheduleHydrationReminders() async {
    // Cancel existing hydration reminders
    for (int id = 3000; id < 3020; id++) {
      await _plugin.cancel(id);
    }

    const messages = [
      '💧 Time to hydrate! Your body needs water.',
      '🚰 Don\'t forget to drink water. Stay hydrated!',
      '💦 Quick reminder — sip some water right now!',
      '🌊 Hydration check! Have you drunk water recently?',
      '💧 Your next glass of water is waiting for you!',
      '⚡ Stay energized — drink some water now!',
      '🏃 Active body needs water. Drink up!',
      '🌟 Hydration tip: drink a glass now before you get thirsty!',
    ];

    // Schedule reminders every 2 hours from 8am to 10pm
    int id = 3000;
    int msgIdx = 0;
    for (int hour = 8; hour <= 22; hour += 2) {
      await scheduleDailyReminder(
        id: id++,
        hour: hour,
        minute: 0,
        title: 'HydroIQ — Hydration Reminder 💧',
        body: messages[msgIdx % messages.length],
        channelId: _hydrateCh,
        channelName: 'Hydration Reminders',
      );
      msgIdx++;
    }
  }

  Future<void> scheduleDailyReminder({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    String? channelId,
    String? channelName,
  }) async {
    await _plugin.cancel(id);
    final ch = channelId ?? _remCh;
    final chName = channelName ?? 'Daily Reminders';
    final androidDetails = AndroidNotificationDetails(
      ch, chName,
      channelDescription: 'Scheduled health reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.zonedSchedule(
      id, title, body,
      _nextTime(hour, minute),
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _mainCh, 'HydroIQ Alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(id, title, body,
        const NotificationDetails(android: androidDetails));
  }

  Future<void> scheduleIntervalReminders(int intervalHours) async {
    for (int id = 3000; id < 3020; id++) await _plugin.cancel(id);
    const messages = [
      '💧 Time to hydrate! Your body needs water.',
      "🚰 Don't forget to drink water. Stay hydrated!",
      '💦 Quick reminder — sip some water right now!',
      '🌊 Hydration check! Have you drunk water recently?',
      '💧 Your next glass of water is waiting for you!',
      '⚡ Stay energized — drink some water now!',
    ];
    int id = 3000;
    int msgIdx = 0;
    for (int hour = 8; hour <= 22; hour += intervalHours.clamp(1, 6)) {
      await scheduleDailyReminder(
        id: id++, hour: hour, minute: 0,
        title: 'HydroIQ — Hydration Reminder 💧',
        body: messages[msgIdx % messages.length],
        channelId: _hydrateCh,
        channelName: 'Hydration Reminders',
      );
      msgIdx++;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

@pragma('vm:entry-point')
void _bgHandler(NotificationResponse r) async {
  if (r.actionId != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_notification_action', r.actionId!);
    } catch (_) {}
  }
}
