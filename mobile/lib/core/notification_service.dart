import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Local notification service for deferred wind-down reminders (PS-04).
///
/// Uses `flutter_local_notifications` with `zonedSchedule` so that
/// notifications fire even if the app is backgrounded.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Channel for post-session wind-down reminders.
  static const _windDownChannel = AndroidNotificationDetails(
    'wind_down_channel',
    'Post-Session Reminders',
    channelDescription: 'Reminders to complete post-session feedback',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _iosDetails = DarwinNotificationDetails();

  static const _notificationDetails = NotificationDetails(
    android: _windDownChannel,
    iOS: _iosDetails,
  );

  /// Initialize the plugin and timezone database. Call once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Schedule a deferred wind-down notification [delay] from now.
  ///
  /// Default delay is 30 minutes — gives the user time to eat before
  /// we nudge them for post-session feedback.
  Future<void> scheduleDeferredWindDown({
    required String sessionId,
    Duration delay = const Duration(minutes: 30),
  }) async {
    if (!_initialized) await initialize();

    final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);

    // Use sessionId hashCode as notification id for uniqueness
    final notifId = sessionId.hashCode.abs() % 100000;

    await _plugin.zonedSchedule(
      notifId,
      'How was your cooking session?',
      'Tap to share quick feedback and save your preferences.',
      scheduledTime,
      _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
    );
  }

  /// Cancel a previously scheduled wind-down notification.
  Future<void> cancelWindDown(String sessionId) async {
    final notifId = sessionId.hashCode.abs() % 100000;
    await _plugin.cancel(notifId);
  }

  /// Cancel all pending notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
