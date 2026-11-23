import 'dart:math';

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
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// The chosen sources. Everything is selected until the user changes it.
  Future<Set<String>> selectedSources() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_sourcesKey);
    final valid = availableSources().map((s) => s.key).toSet();
    if (stored == null) return valid;
    final chosen = stored.where((k) => valid.contains(k)).toSet();
    return chosen.isEmpty ? valid : chosen;
  }

  Future<void> setSelectedSources(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sourcesKey, keys.toList());
    await refresh();
  }

  /// Turns the daily citation on or off. Returns the resulting state: false
  /// if the user asked for it on but notification permission was refused.
  Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final granted = await _requestPermission();
      if (!granted) {
        await prefs.setBool(_enabledKey, false);
        await refresh();
        return false;
      }
    }
    await prefs.setBool(_enabledKey, enabled);
    await refresh();
    return enabled;
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
  Future<void> refresh() async {
    try {
      await NotificationService.instance.init();
      await _cancelAll();
      if (!await isEnabled()) return;

      final repo = EntriesRepository.instance;
      if (!repo.isLoaded) await repo.load();
      final pool = await _pool();
      if (pool.isEmpty) return;

      final now = DateTime.now();
      final rng = Random(now.year * 10000 + now.month * 100 + now.day);
      final order = List<Entry>.from(pool)..shuffle(rng);

      var scheduled = 0;
      var index = 0;
      for (var d = 0; d <= _daysAhead && scheduled < _daysAhead; d++) {
        final when = DateTime(now.year, now.month, now.day + d, _sendHour);
        if (!when.isAfter(now)) continue;
        final entry = order[index % order.length];
        index++;
        await _plugin.zonedSchedule(
          _baseId + scheduled,
          _title(entry),
          _snippet(entry, 140),
          tz.TZDateTime.from(when, tz.local),
          _details(entry),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduled++;
      }
    } catch (_) {
      // Notifications are a convenience - never let a failure here affect the app.
    }
  }

  /// Shows one citation immediately so the user can see how it looks.
  Future<bool> sendTest() async {
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
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelAll() async {
    for (var i = 0; i < _slots; i++) {
      await _plugin.cancel(_baseId + i);
    }
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
