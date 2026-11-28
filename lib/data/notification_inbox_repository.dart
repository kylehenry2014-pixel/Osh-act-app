import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InboxNotificationType {
  dailyCitation,
  certificateReminder,
  appUpdate,
  general,
}

@immutable
class InboxNotification {
  final String id;
  final InboxNotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String? referenceId;

  const InboxNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.referenceId,
  });

  InboxNotification copyWithRead(bool value) {
    return InboxNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: value,
      referenceId: referenceId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isRead': isRead,
        'referenceId': referenceId,
      };

  factory InboxNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    return InboxNotification(
      id: json['id'] as String,
      type: InboxNotificationType.values.byName(
        json['type'] as String,
      ),
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(
        json['createdAt'] as String,
      ),
      isRead: json['isRead'] as bool? ?? false,
      referenceId: json['referenceId'] as String?,
    );
  }
}

class NotificationInboxRepository extends ChangeNotifier {
  NotificationInboxRepository._();

  static final instance = NotificationInboxRepository._();

  static const _storageKey = 'notification_inbox_v1';

  List<InboxNotification> _items = [];
  bool _loaded = false;
  bool _hasStorageDamage = false;

  Future<void> _queue = Future<void>.value();

  bool get isLoaded => _loaded;
  bool get hasStorageDamage => _hasStorageDamage;

  List<InboxNotification> get all =>
      List<InboxNotification>.unmodifiable(_items);

  List<InboxNotification> get unread =>
      List<InboxNotification>.unmodifiable(
        _items.where((item) => !item.isRead),
      );

  int get unreadCount =>
      _items.where((item) => !item.isRead).length;

  Future<void> _serialise(
    Future<void> Function() operation,
  ) {
    final next = _queue.then((_) => operation());

    _queue = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return next;
  }

  Future<void> load() {
    return _serialise(_loadInternal);
  }

  Future<void> _loadInternal() async {
    if (_loaded) return;

    final prefs = await SharedPreferences.getInstance();

    try {
      final raw = prefs.getString(_storageKey);

      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;

        final restored = decoded.map((entry) {
          return InboxNotification.fromJson(
            Map<String, dynamic>.from(entry as Map),
          );
        }).toList();

        final ids = <String>{};

        for (final item in restored) {
          if (item.id.isEmpty || !ids.add(item.id)) {
            throw const FormatException(
              'Invalid or duplicate notification ID.',
            );
          }
        }

        restored.sort(
          (a, b) => b.createdAt.compareTo(a.createdAt),
        );

        _items = restored;
      }

      _hasStorageDamage = false;
      _loaded = true;
    } catch (error) {
      _hasStorageDamage = true;
      debugPrint('Notification inbox storage unavailable.');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _ensureReady() async {
    if (_hasStorageDamage) {
      throw StateError(
        'Notification storage requires recovery.',
      );
    }

    if (!_loaded) {
      await _loadInternal();
    }
  }

  Future<void> _save(
    List<InboxNotification> updated,
  ) async {
    if (!_loaded || _hasStorageDamage) {
      throw StateError(
        'Notification storage is not ready.',
      );
    }

    final sorted = List<InboxNotification>.of(updated);

    sorted.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );

    final prefs = await SharedPreferences.getInstance();

    final saved = await prefs.setString(
      _storageKey,
      jsonEncode(
        sorted.map((item) => item.toJson()).toList(),
      ),
    );

    if (!saved) {
      throw StateError(
        'Notification inbox could not be saved.',
      );
    }

    _items = sorted;
    notifyListeners();
  }

  Future<void> add(InboxNotification notification) {
    return _serialise(() async {
      await _ensureReady();

      if (notification.id.trim().isEmpty) {
        throw ArgumentError('Notification ID is required.');
      }

      if (_items.any(
        (item) => item.id == notification.id,
      )) {
        return;
      }

      await _save([
        ..._items,
        notification,
      ]);
    });
  }

  Future<void> markAsRead(String id) {
    return _serialise(() async {
      await _ensureReady();

      if (!_items.any(
        (item) => item.id == id && !item.isRead,
      )) {
        return;
      }

      await _save(
        _items.map((item) {
          return item.id == id
              ? item.copyWithRead(true)
              : item;
        }).toList(),
      );
    });
  }

  Future<void> markAllAsRead() {
    return _serialise(() async {
      await _ensureReady();

      if (unreadCount == 0) return;

      await _save(
        _items
            .map((item) => item.copyWithRead(true))
            .toList(),
      );
    });
  }
}