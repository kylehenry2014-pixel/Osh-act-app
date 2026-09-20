import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/certificate.dart';

/// Schedules local (on-device) notifications reminding the user before a
/// certificate expires. Entirely offline - no server involved, so this
/// works even without Firebase configured.
///
/// Reminder schedule: 30, 14, 7 and 1 day(s) before expiry, plus one on the
/// day itself. Each certificate gets a block of notification IDs derived
/// from a hash of its own id, so scheduling/cancelling one certificate's
/// reminders never touches another's.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const List<int> _reminderDaysBefore = [30, 14, 7, 1, 0];

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // we ask explicitly in requestPermissions()
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  /// Requests notification permission. Safe to call multiple times - the OS
  /// only prompts once; subsequent calls just report the current state.
  Future<bool> requestPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      // Exact-alarm permission is separate on Android 12+; without it,
      // reminders may fire a little late but will still fire.
      await androidImpl.requestExactAlarmsPermission();
      return granted ?? false;
    }
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// Schedules (or reschedules) all reminders for a certificate. Call this
  /// whenever a certificate is added or its expiry date/name changes.
  Future<void> scheduleForCertificate(Certificate cert) async {
    await cancelForCertificate(cert.id);

    for (var i = 0; i < _reminderDaysBefore.length; i++) {
      final daysBefore = _reminderDaysBefore[i];
      final fireDate = DateTime(
        cert.expiryDate.year,
        cert.expiryDate.month,
        cert.expiryDate.day,
        9, // 9am local time - a reasonable time to see a reminder
      ).subtract(Duration(days: daysBefore));

      if (fireDate.isBefore(DateTime.now())) continue; // don't schedule past reminders

      final title = daysBefore == 0
          ? '${cert.name} expires today'
          : '${cert.name} expires in $daysBefore day${daysBefore == 1 ? '' : 's'}';

      await _plugin.zonedSchedule(
        _notificationId(cert.id, i),
        title,
        'Expiry date: ${_formatDate(cert.expiryDate)}. Open the app to review.',
        tz.TZDateTime.from(fireDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'certificate_expiry',
            'Certificate Expiry Reminders',
            channelDescription: 'Reminders before your saved certificates expire',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Cancels every scheduled reminder for a certificate. Call this when a
  /// certificate is deleted, or right before rescheduling on an edit.
  Future<void> cancelForCertificate(String certId) async {
    for (var i = 0; i < _reminderDaysBefore.length; i++) {
      await _plugin.cancel(_notificationId(certId, i));
    }
  }

  /// Derives a stable, small int notification ID from the certificate's id
  /// and reminder slot, so each of a certificate's up-to-5 reminders has a
  /// unique, deterministic ID we can cancel individually later.
  int _notificationId(String certId, int slot) {
    final hash = certId.hashCode & 0x7FFFFFFF; // keep positive
    return (hash % 100000) * 10 + slot;
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
