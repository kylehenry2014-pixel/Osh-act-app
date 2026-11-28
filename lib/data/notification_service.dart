import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../models/certificate.dart';
import 'notification_inbox_repository.dart';
import 'notification_schedule_repository.dart';

class NotificationService {
  static final NotificationService instance =
      NotificationService._();

  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  final _scheduleLedger =
      NotificationScheduleRepository.instance;

  // Notification history is secondary to platform reminders.
  Future<void> _protectLedger(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      debugPrint(
        'Certificate notification history unavailable: '
        '${error.runtimeType}',
      );
    }
  }

  String? _pendingNotificationPayload;

  String? get pendingNotificationPayload =>
      _pendingNotificationPayload;

  void clearPendingNotification(String payload) {
    if (_pendingNotificationPayload == payload) {
      _pendingNotificationPayload = null;
    }
  }

  void _captureNotificationResponse(
    NotificationResponse response,
  ) {
    final payload = response.payload;

    if (payload == null) return;

    final separator = payload.indexOf(':');

    if (separator <= 0 ||
        separator == payload.length - 1) {
      return;
    }

    final type = payload.substring(0, separator);
    final reference = payload.substring(separator + 1);

    if (reference.trim().isEmpty ||
        (type != 'certificate' &&
            type != 'citation')) {
      return;
    }

    _pendingNotificationPayload = payload;
  }

  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> _queue = Future<void>.value();

  static const List<int> _reminderDaysBefore = [
    30, 14, 7, 1, 0,
  ];

  static const String _idMapKey =
      'certificate_notification_ids_v2';

  static const String _nextIdKey =
      'certificate_notification_next_id_v2';

  static const String _migrationKey =
      'certificate_notification_migration_v2';

  // Reserved certificate range.
  // Daily citations use IDs starting at 9,000,000.
  static const int _firstId = 10000000;
  static const int _lastId = 2000000000;
  static const int _blockSize = 10;

  Future<T> _serialise<T>(
    Future<T> Function() operation,
  ) {
    final result = _queue.then((_) => operation());

    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Notification operation failed: $error');
      },
    );

    return result;
  }

  Future<void> init() {
    if (_initialized) return Future<void>.value();

    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();

    await _refreshTimezone();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse:
          _captureNotificationResponse,
    );

    // Recover the notification that launched the app.
    try {
      final launchDetails =
          await _plugin.getNotificationAppLaunchDetails();

      if (launchDetails?.didNotificationLaunchApp == true) {
        final response =
            launchDetails?.notificationResponse;

        if (response != null &&
            _pendingNotificationPayload == null) {
          _captureNotificationResponse(response);
        }
      }
    } catch (error) {
      debugPrint(
        'Notification launch details unavailable: '
        '${error.runtimeType}',
      );
    }

    _initialized = true;
  }

  Future<void> _refreshTimezone() async {
    try {
      final timezoneName =
          await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(
        tz.getLocation(timezoneName),
      );
    } catch (error) {
      // The scheduling helper below converts native local
      // DateTime values to absolute instants if this fails.
      debugPrint('Device timezone lookup failed: $error');
    }
  }

  Future<bool> requestPermissions() async {
    await init();

    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      try {
        final granted =
            await android.requestNotificationsPermission();

        return granted ?? false;
      } catch (error) {
        debugPrint('Notification permission failed: $error');
        return false;
      }
    }

    final ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    if (ios != null) {
      try {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        return granted ?? false;
      } catch (error) {
        debugPrint('iOS notification permission failed: $error');
        return false;
      }
    }

    return true;
  }

  /// Optional exact alarm access.
  /// Not requested automatically when saving certificates.
  Future<bool> requestExactAlarmAccess() async {
    await init();

    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return true;

    try {
      return await android.requestExactAlarmsPermission()
          ?? false;
    } catch (error) {
      debugPrint('Exact alarm access unavailable: $error');
      return false;
    }
  }

  Future<Map<String, int>> _readIdMap(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_idMapKey);

    if (raw == null) return <String, int>{};

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw StateError('Invalid notification ID storage.');
    }

    final result = <String, int>{};
    final used = <int>{};

    for (final entry in decoded.entries) {
      final value = entry.value;

      if (entry.key is! String ||
          value is! int ||
          value < _firstId ||
          value > _lastId ||
          value % _blockSize != 0 ||
          !used.add(value)) {
        throw StateError('Invalid notification ID allocation.');
      }

      result[entry.key as String] = value;
    }

    return result;
  }

  Future<int> _allocateId(String certId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readIdMap(prefs);

    final existing = map[certId];

    if (existing != null) return existing;

    var next = prefs.getInt(_nextIdKey) ?? _firstId;

    if (next < _firstId || next % _blockSize != 0) {
      next = _firstId;
    }

    for (final value in map.values) {
      if (value >= next) {
        next = value + _blockSize;
      }
    }

    if (next + _blockSize > _lastId) {
      throw StateError('Notification ID range exhausted.');
    }

    map[certId] = next;

    if (!await prefs.setString(
      _idMapKey,
      jsonEncode(map),
    )) {
      throw StateError('Could not save notification IDs.');
    }

    if (!await prefs.setInt(
      _nextIdKey,
      next + _blockSize,
    )) {
      throw StateError('Could not save notification counter.');
    }

    return next;
  }

  Future<void> scheduleForCertificate(
    Certificate cert,
  ) {
    return _serialise(() async {
      await init();
      await _refreshTimezone();
      await _scheduleCertificate(cert);
    });
  }

  Future<void> _scheduleCertificate(
    Certificate cert,
  ) async {
    await _protectLedger(
      () => _scheduleLedger.reconcileDue(),
    );

    final baseId = await _allocateId(cert.id);
    final now = DateTime.now();

    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    var exactAllowed = false;

    if (android != null) {
      try {
        exactAllowed =
            await android.canScheduleExactNotifications()
                ?? false;
      } catch (error) {
        debugPrint('Exact alarm check failed: $error');
      }
    }

    var failures = 0;

    for (var i = 0;
        i < _reminderDaysBefore.length;
        i++) {
      final daysBefore = _reminderDaysBefore[i];
      final id = baseId + i;

      // Calendar-day arithmetic avoids DST subtraction errors.
      final fireDate = DateTime(
        cert.expiryDate.year,
        cert.expiryDate.month,
        cert.expiryDate.day - daysBefore,
        9,
      );

      try {
        if (!fireDate.isAfter(now)) {
          await _plugin.cancel(id);
          await _protectLedger(
            () => _scheduleLedger.removePlatformId(id),
          );
          continue;
        }

        final title = daysBefore == 0
            ? '${cert.name} expires today'
            : '${cert.name} expires in $daysBefore '
              'day${daysBefore == 1 ? '' : 's'}';

        final body =
            'Expiry date: ${_formatDate(cert.expiryDate)}. '
            'Open the app to review.';

        final when = tz.TZDateTime.from(
          fireDate,
          tz.local,
        );

        await _scheduleReminder(
          id: id,
          title: title,
          body: body,
          when: when,
          exactAllowed: exactAllowed,
          payload: 'certificate:${cert.id}',
        );

        final expiryKey =
            '${cert.expiryDate.year}-'
            '${cert.expiryDate.month.toString().padLeft(2, '0')}-'
            '${cert.expiryDate.day.toString().padLeft(2, '0')}';

        await _protectLedger(
          () => _scheduleLedger.record(
            ScheduledInboxNotification(
              platformId: id,
              notification: InboxNotification(
                id: 'certificate_${cert.id}_${expiryKey}_$daysBefore',
                type: InboxNotificationType.certificateReminder,
                title: title,
                message: body,
                createdAt: when.toUtc(),
                referenceId: cert.id,
              ),
            ),
          ),
        );
      } catch (error) {
        failures++;
        debugPrint(
          'Certificate reminder $id failed: $error',
        );
      }
    }

    if (failures > 0) {
      throw StateError(
        '$failures certificate reminder(s) could not be updated.',
      );
    }
  }

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required bool exactAllowed,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'certificate_expiry',
        'Certificate Expiry Reminders',
        channelDescription:
            'Reminders before your saved certificates expire',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    Future<void> schedule(
      AndroidScheduleMode mode,
    ) {
      return _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }

    if (exactAllowed) {
      try {
        await schedule(
          AndroidScheduleMode.exactAllowWhileIdle,
        );
        return;
      } catch (error) {
        debugPrint(
          'Exact scheduling failed; trying inexact: $error',
        );
      }
    }

    await schedule(
      AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelForCertificate(
    String certId,
  ) {
    return _serialise(() async {
      await init();

      final prefs =
          await SharedPreferences.getInstance();

      final map = await _readIdMap(prefs);
      final baseId = map[certId];

      await _protectLedger(
        () => _scheduleLedger.reconcileDue(),
      );

      if (baseId != null) {
        for (var i = 0;
            i < _reminderDaysBefore.length;
            i++) {
          await _plugin.cancel(baseId + i);
          await _protectLedger(
            () => _scheduleLedger.removePlatformId(baseId + i),
          );
        }
      }

      await _protectLedger(
        () => _scheduleLedger.removeReference(
          InboxNotificationType.certificateReminder,
          certId,
        ),
      );

      if (baseId == null) return;

      map.remove(certId);

      if (!await prefs.setString(
        _idMapKey,
        jsonEncode(map),
      )) {
        throw StateError(
          'Could not update notification ID storage.',
        );
      }
    });
  }

  /// Rebuild reminders from existing certificate records.
  /// Call only after the certificate repository has loaded.
  Future<void> reconcileCertificates(
    List<Certificate> certificates,
  ) {
    final snapshot = List<Certificate>.of(certificates);

    return _serialise(() async {
      await init();
      await _refreshTimezone();

      final prefs =
          await SharedPreferences.getInstance();

      var failures = 0;

      // Schedule replacement reminders before removing
      // notifications from the legacy ID range.
      for (final cert in snapshot) {
        try {
          await _scheduleCertificate(cert);
        } catch (error) {
          failures++;
          debugPrint(
            'Certificate reminder reconciliation failed: $error',
          );
        }
      }

      if (failures == 0 &&
          !(prefs.getBool(_migrationKey) ?? false)) {
        final pending =
            await _plugin.pendingNotificationRequests();

        for (final request in pending) {
          // Previous certificate IDs were below 1,000,000.
          // Daily citation IDs are outside this range.
          if (request.id >= 0 &&
              request.id < 1000000 &&
              request.id % 10 < 5) {
            await _plugin.cancel(request.id);
          }
        }

        if (!await prefs.setBool(_migrationKey, true)) {
          throw StateError(
            'Could not record notification migration.',
          );
        }
      }

      // Remove reminders belonging to deleted certificates.
      final map = await _readIdMap(prefs);
      final activeIds =
          snapshot.map((cert) => cert.id).toSet();

      final staleIds = map.keys
          .where((id) => !activeIds.contains(id))
          .toList();

      await _protectLedger(
        () => _scheduleLedger.reconcileDue(),
      );

      for (final certId in staleIds) {
        final baseId = map[certId]!;

        for (var i = 0;
            i < _reminderDaysBefore.length;
            i++) {
          await _plugin.cancel(baseId + i);
          await _protectLedger(
            () => _scheduleLedger.removePlatformId(baseId + i),
          );
        }

        await _protectLedger(
          () => _scheduleLedger.removeReference(
            InboxNotificationType.certificateReminder,
            certId,
          ),
        );

        map.remove(certId);
      }

      if (!await prefs.setString(
        _idMapKey,
        jsonEncode(map),
      )) {
        throw StateError(
          'Could not reconcile notification IDs.',
        );
      }

      if (failures > 0) {
        throw StateError(
          '$failures certificate(s) require reminder retry.',
        );
      }
    });
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}