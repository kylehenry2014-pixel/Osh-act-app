import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/entry.dart';
import 'entries_repository.dart';
import 'notification_service.dart';

/// One choice in the "Acts to include" list of the Daily Citation settings.
class CitationSource {
  final String key;
  final String label;
  const CitationSource(this.key, this.label);
}

/// Sends one section from the Acts and Regulations as a local notification
/// every day at 12:00. Entirely on the device - no server involved. The
/// next 30 days are scheduled at once, and the schedule is refreshed every
/// time the app opens or the settings change. Off until the user opts in.
class DailyCitationService {
  DailyCitationService._();
  static final DailyCitationService instance = DailyCitationService._();

  static const _enabledKey = 'daily_citation_enabled';
  static const _sourcesKey = 'daily_citation_sources';

  // Certificate reminders use IDs below 1,000,000, so this range never clashes.
  static const int _baseId = 9000000;
  static const int _slots = 60;
  static const int _daysAhead = 30;
  static const int _sendHour = 12;

  static const _ohsActKey = 'ohs_act';
  static const _ohsRegsKey = 'ohs_regs';
  static const _otherPrefix = 'act:';

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _scheduleKey = 'daily_citation_schedule_v2';

  Future<void> _citationQueue = Future<void>.value();

  Future<T> _serialise<T>(Future<T> Function() task) {
    final operation = _citationQueue.then((_) => task());

    _citationQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return operation;
  }

  Future<void> _prepareNotifications() async {
    await NotificationService.instance.init();

    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
  }

  Future<void> _checkWrite(
    SharedPreferences prefs,
    Future<bool> write,
  ) async {
    try {
      if (!await write) {
        throw StateError('Could not save citation settings.');
      }
    } catch (_) {
      await prefs.reload();
      rethrow;
    }
  }

  /// The Acts the user can pick from: the OHS Act, the OHS Regulations as
  /// one group, and every other Act found in the data.
  List<CitationSource> availableSources() {
    final repo = EntriesRepository.instance;
    final sources = <CitationSource>[
      const CitationSource(_ohsActKey, 'OHS Act'),
      const CitationSource(_ohsRegsKey, 'OHS Regulations'),
    ];
    for (final c in repo.collectionsInCategory('OtherActs')) {
      sources.add(CitationSource('$_otherPrefix$c', c));
    }
    return sources;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.get(_enabledKey);

    if (stored == null) return false;

    if (stored is! bool) {
      throw const FormatException(
        'Invalid daily citation preference.',
      );
    }

    return stored;
  }

  Future<Set<String>> selectedSources() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.get(_sourcesKey);
    final valid = availableSources().map((s) => s.key).toSet();

    if (stored == null) return valid;

    if (stored is! List ||
        stored.any((value) => value is! String)) {
      throw const FormatException(
        'Invalid daily citation sources.',
      );
    }

    final chosen = stored.whereType<String>()
        .where(valid.contains)
        .toSet();

    if (chosen.isEmpty) {
      throw StateError(
        'Select at least one available legislation source.',
      );
    }

    return chosen;
  }

  Future<void> setSelectedSources(Set<String> keys) {
    final requested = Set<String>.from(keys);

    return _serialise(() async {
      final valid = availableSources().map((s) => s.key).toSet();

      if (requested.isEmpty ||
          !requested.every(valid.contains)) {
        throw ArgumentError('Invalid citation source selection.');
      }

      final prefs = await SharedPreferences.getInstance();
      final sorted = requested.toList()..sort();

      await _checkWrite(
        prefs,
        prefs.setStringList(_sourcesKey, sorted),
      );

      await _refreshOnce();
    });
  }

  Future<bool> setEnabled(bool enabled) {
    return _serialise(() async {
      if (enabled && !await _requestPermission()) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();

      await _checkWrite(
        prefs,
        prefs.setBool(_enabledKey, enabled),
      );

      await _refreshOnce();

      return enabled;
    });
  }

  Future<bool> _requestPermission() async {
    await NotificationService.instance.init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// Clears the old schedule and, if the feature is on, schedules the next
  /// 30 daily citations. Safe to call as often as needed; on the same day it
  /// produces the same picks, so opening the app does not change them.
  Future<void> refresh() {
    return _serialise(_refreshOnce);
  }

  Future<void> _refreshOnce() async {
    await NotificationService.instance.init();

    final prefs = await SharedPreferences.getInstance();

    final pending = await _plugin.pendingNotificationRequests();

    final existingIds = pending
        .map((request) => request.id)
        .where((id) => id >= _baseId && id < _baseId + _slots)
        .toSet();

    if (!await isEnabled()) {
      for (final id in existingIds) {
        await _plugin.cancel(id);
      }

      await _checkWrite(prefs, prefs.remove(_scheduleKey));
      return;
    }

    await _prepareNotifications();

    final repo = EntriesRepository.instance;
    if (!repo.isLoaded) await repo.load();

    final keys = await selectedSources();
    final pool = await _pool();

    if (pool.isEmpty) {
      throw StateError('No citations available for the selected sources.');
    }

    final now = tz.TZDateTime.now(tz.local);

    final sortedKeys = keys.toList()..sort();

    final firstDay = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _sendHour,
    );

    final startDay = firstDay.isAfter(now)
        ? firstDay
        : tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day + 1,
            _sendHour,
          );

    final fingerprint = [
      'v2',
      tz.local.name,
      startDay.toIso8601String(),
      pool.length.toString(),
      ...sortedKeys,
    ].join('|');

    final desiredIds = <int>{
      for (var i = 0; i < _daysAhead; i++) _baseId + i,
    };

    if (prefs.get(_scheduleKey) == fingerprint &&
        existingIds.length == desiredIds.length &&
        existingIds.containsAll(desiredIds)) {
      return;
    }

    // Invalidate the previous schedule marker before changing
    // notifications so an interrupted refresh can be retried.
    await _checkWrite(prefs, prefs.remove(_scheduleKey));

    for (var d = 0; d < _daysAhead; d++) {
      final when = tz.TZDateTime(
        tz.local,
        startDay.year,
        startDay.month,
        startDay.day + d,
        _sendHour,
      );

      final seed = when.year * 10000 +
          when.month * 100 +
          when.day;

      final entry = pool[Random(seed).nextInt(pool.length)];

      // Reuse the reserved ID instead of cancelling
      // the entire existing schedule before rebuilding it.
      await _plugin.zonedSchedule(
        _baseId + d,
        _title(entry),
        _snippet(entry, 140),
        when,
        _details(entry),
        androidScheduleMode:
            AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    for (final id in existingIds.difference(desiredIds)) {
      await _plugin.cancel(id);
    }

    await _checkWrite(
      prefs,
      prefs.setString(_scheduleKey, fingerprint),
    );

    debugPrint('Daily citation schedule refreshed.');
  }

  Future<bool> sendTest() {
    return _serialise(() async {
      try {
        if (!await _requestPermission()) return false;

        final repo = EntriesRepository.instance;
        if (!repo.isLoaded) await repo.load();

        final pool = await _pool();
        if (pool.isEmpty) return false;

        final entry = pool[Random().nextInt(pool.length)];

        await _plugin.show(
          _baseId + _slots,
          _title(entry),
          _snippet(entry, 140),
          _details(entry),
        );

        return true;
      } catch (error) {
        debugPrint('Citation test notification failed: $error');
        return false;
      }
    });
  }

  Future<List<Entry>> _pool() async {
    final keys = await selectedSources();
    return EntriesRepository.instance.all
        .where((e) =>
            e.body.trim().length >= 40 && keys.any((k) => _matches(e, k)))
        .toList();
  }

  bool _matches(Entry e, String key) {
    if (key == _ohsActKey) return e.category == 'Act';
    if (key == _ohsRegsKey) {
      return e.category != 'Act' && e.category != 'OtherActs';
    }
    if (key.startsWith(_otherPrefix)) {
      return e.category == 'OtherActs' &&
          e.collection == key.substring(_otherPrefix.length);
    }
    return false;
  }

  String _title(Entry e) {
    final heading = e.title.trim();
    final base = '${e.collectionShort} ${e.num}';
    return heading.isEmpty ? base : '$base - $heading';
  }

  String _snippet(Entry e, int maxLength) {
    final text = e.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  NotificationDetails _details(Entry e) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_citation',
        'Daily Citation',
        channelDescription: 'A daily section from the Acts and Regulations',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(_snippet(e, 450)),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }
}
