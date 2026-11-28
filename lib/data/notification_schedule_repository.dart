import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/certificate.dart';
import 'notification_inbox_repository.dart';

/// A successfully scheduled local reminder.
/// Its due date does not prove operating system delivery.
class ScheduledInboxNotification {
  final int platformId;
  final InboxNotification notification;

  const ScheduledInboxNotification({
    required this.platformId,
    required this.notification,
  });

  DateTime get scheduledAt => notification.createdAt;

  Map<String, dynamic> toJson() => {
        'platformId': platformId,
        'notification': notification.toJson(),
      };

  factory ScheduledInboxNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    return ScheduledInboxNotification(
      platformId: json['platformId'] as int,
      notification: InboxNotification.fromJson(
        Map<String, dynamic>.from(
          json['notification'] as Map,
        ),
      ),
    );
  }
}

/// Persistent ledger of scheduled certificate and citation reminders.
/// Future reminders remain separate from the visible notification inbox.
class NotificationScheduleRepository {
  NotificationScheduleRepository._();

  static final instance = NotificationScheduleRepository._();

  static const _storageKey =
      'notification_schedule_ledger_v1';

  Future<void> _queue = Future<void>.value();

  Future<T> _serialise<T>(
    Future<T> Function() operation,
  ) {
    final next = _queue.then<T>(
      (_) => operation(),
    );

    _queue = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return next;
  }

  void _validate(ScheduledInboxNotification item) {
    final notification = item.notification;

    if (item.platformId < 0 ||
        notification.id.trim().isEmpty ||
        notification.title.trim().isEmpty ||
        notification.isRead ||
        (notification.type !=
                InboxNotificationType.certificateReminder &&
            notification.type !=
                InboxNotificationType.dailyCitation)) {
      throw const FormatException(
        'Invalid scheduled notification.',
      );
    }
  }

  Future<List<ScheduledInboxNotification>> _read(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_storageKey);

    if (raw == null) return [];

    final decoded = jsonDecode(raw);

    if (decoded is! List) {
      throw const FormatException(
        'Invalid notification schedule storage.',
      );
    }

    final items = <ScheduledInboxNotification>[];
    final ids = <String>{};
    final platformIds = <int>{};

    for (final entry in decoded) {
      final item = ScheduledInboxNotification.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );

      _validate(item);

      if (!ids.add(item.notification.id) ||
          !platformIds.add(item.platformId)) {
        throw const FormatException(
          'Duplicate scheduled notification.',
        );
      }

      items.add(item);
    }

    return items;
  }

  Future<void> _save(
    SharedPreferences prefs,
    List<ScheduledInboxNotification> items,
  ) async {
    final encoded = jsonEncode(
      items.map((item) => item.toJson()).toList(),
    );

    if (prefs.getString(_storageKey) == encoded) {
      return;
    }

    try {
      if (!await prefs.setString(
        _storageKey,
        encoded,
      )) {
        throw StateError(
          'Could not save notification schedule.',
        );
      }
    } catch (_) {
      await prefs.reload();
      rethrow;
    }
  }

  Future<List<ScheduledInboxNotification>> all() {
    return _serialise(() async {
      final prefs = await SharedPreferences.getInstance();

      return List<ScheduledInboxNotification>.unmodifiable(
        await _read(prefs),
      );
    });
  }

  /// Record a reminder only after successful platform scheduling.
  Future<void> record(
    ScheduledInboxNotification item,
  ) {
    return _serialise(() async {
      _validate(item);

      final prefs = await SharedPreferences.getInstance();
      final items = await _read(prefs);

      final updated = items.where((existing) {
        return existing.platformId != item.platformId &&
            existing.notification.id != item.notification.id;
      }).toList();

      updated.add(item);

      await _save(prefs, updated);
    });
  }

  /// Remove a cancelled or replaced platform reminder.
  Future<void> removePlatformId(int platformId) {
    return _serialise(() async {
      final prefs = await SharedPreferences.getInstance();
      final items = await _read(prefs);

      final updated = items.where((item) {
        return item.platformId != platformId;
      }).toList();

      if (updated.length == items.length) return;

      await _save(prefs, updated);
    });
  }

  /// Remove outstanding reminders associated with a deleted record.
  Future<void> removeReference(
    InboxNotificationType type,
    String referenceId,
  ) {
    return _serialise(() async {
      final prefs = await SharedPreferences.getInstance();
      final items = await _read(prefs);

      final updated = items.where((item) {
        return item.notification.type != type ||
            item.notification.referenceId != referenceId;
      }).toList();

      if (updated.length == items.length) return;

      await _save(prefs, updated);
    });
  }

  bool _isCurrentReminder(
    ScheduledInboxNotification item,
    SharedPreferences prefs,
  ) {
    final notification = item.notification;

    if (notification.type ==
        InboxNotificationType.dailyCitation) {
      final enabled = prefs.get('daily_citation_enabled');

      if (enabled == null) return false;

      if (enabled is! bool) {
        throw const FormatException(
          'Invalid daily citation preference.',
        );
      }

      return enabled;
    }

    if (notification.type !=
        InboxNotificationType.certificateReminder) {
      return false;
    }

    final reference = notification.referenceId;

    if (reference == null || reference.trim().isEmpty) {
      return false;
    }

    final raw = prefs.getString('saved_certificates');

    if (raw == null || raw.isEmpty) return false;

    final decoded = jsonDecode(raw);

    if (decoded is! List) {
      throw const FormatException(
        'Invalid certificate storage format.',
      );
    }

    final certificates = decoded.map((entry) {
      return Certificate.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
    }).toList();

    final matches = certificates.where(
      (certificate) => certificate.id == reference,
    ).toList();

    if (matches.isEmpty) return false;

    if (matches.length != 1) {
      throw const FormatException(
        'Duplicate certificate reference.',
      );
    }

    final certificate = matches.single;
    final expiry = certificate.expiryDate;

    final expiryKey =
        '${expiry.year}-'
        '${expiry.month.toString().padLeft(2, '0')}-'
        '${expiry.day.toString().padLeft(2, '0')}';

    const reminderDays = [30, 14, 7, 1, 0];

    for (final daysBefore in reminderDays) {
      final expectedId =
          'certificate_${certificate.id}_${expiryKey}_$daysBefore';

      final expectedTitle = daysBefore == 0
          ? '${certificate.name} expires today'
          : '${certificate.name} expires in $daysBefore '
            'day${daysBefore == 1 ? '' : 's'}';

      if (notification.id == expectedId &&
          notification.title == expectedTitle) {
        return true;
      }
    }

    return false;
  }

  /// Move due reminders into the inbox.
  /// A due reminder is not proof of operating system delivery.
  Future<void> reconcileDue({
    DateTime? now,
  }) {
    return _serialise(() async {
      final cutoff = (now ?? DateTime.now()).toUtc();

      final prefs = await SharedPreferences.getInstance();
      final items = await _read(prefs);

      final due = items.where((item) {
        return !item.scheduledAt.toUtc().isAfter(cutoff);
      }).toList();

      if (due.isEmpty) return;

      final inbox = NotificationInboxRepository.instance;

      for (final item in due) {
        if (!_isCurrentReminder(item, prefs)) {
          // Obsolete reminders must not enter the inbox.
          continue;
        }

        await inbox.add(item.notification);
      }

      // Remove transferred and obsolete due reminders.
      // Existing inbox history remains untouched.
      // Stable inbox IDs make interrupted operations retryable.
      final transferred = due.map(
        (item) => item.notification.id,
      ).toSet();

      final remaining = items.where((item) {
        return !transferred.contains(item.notification.id);
      }).toList();

      await _save(prefs, remaining);
    });
  }
}