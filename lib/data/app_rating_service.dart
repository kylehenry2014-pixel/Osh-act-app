import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppRatingService {
  AppRatingService._();

  static final instance = AppRatingService._();

  static const usageThreshold = Duration(minutes: 5);
  static const reminderInterval = Duration(days: 7);

  static const applicationId =
      'com.ohsactapp.ohs_act_regulations';

  static const _usageKey = 'app_rating_usage_ms_v1';
  static const _disabledKey = 'app_rating_disabled_v1';
  static const _openedKey = 'app_rating_store_opened_v1';
  static const _reminderKey = 'app_rating_reminder_v1';

  SharedPreferences? _prefs;

  final Stopwatch _foreground = Stopwatch();

  Future<void> _queue = Future<void>.value();

  int _savedMilliseconds = 0;
  int? _lastPersistedMilliseconds;

  bool _promptVisible = false;
  bool _initialised = false;

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

  Future<void> init() {
    return _serialise(() async {
      if (_initialised) return;

      final prefs = await SharedPreferences.getInstance();

      _savedMilliseconds =
          prefs.getInt(_usageKey) ?? 0;

      if (_savedMilliseconds < 0) {
        _savedMilliseconds = 0;
      }

      _lastPersistedMilliseconds =
          prefs.getInt(_usageKey) ?? 0;

      _prefs = prefs;
      _initialised = true;
    });
  }

  bool get isInitialised => _initialised;

  Duration get accumulatedUsage => Duration(
        milliseconds: _savedMilliseconds +
            _foreground.elapsedMilliseconds,
      );

  bool get automaticPromptDisabled {
    final prefs = _prefs;

    if (prefs == null) return true;

    return (prefs.getBool(_disabledKey) ?? false) ||
        (prefs.getBool(_openedKey) ?? false);
  }

  bool get shouldPrompt {
    final prefs = _prefs;

    if (!_initialised ||
        prefs == null ||
        _promptVisible ||
        !_foreground.isRunning ||
        automaticPromptDisabled) {
      return false;
    }

    final reminderAt = prefs.getInt(_reminderKey);

    if (reminderAt != null &&
        DateTime.now().millisecondsSinceEpoch <
            reminderAt) {
      return false;
    }

    return accumulatedUsage >= usageThreshold;
  }

  void resumeUsage() {
    if (!_initialised ||
        automaticPromptDisabled ||
        _promptVisible) {
      return;
    }

    if (!_foreground.isRunning) {
      _foreground.start();
    }
  }

  Future<void> pauseUsage() {
    _foreground.stop();
    return saveUsage();
  }

  Future<void> saveUsage() {
    return _serialise(() async {
      final prefs = _prefs;

      if (!_initialised || prefs == null) return;

      final elapsed = _foreground.elapsedMilliseconds;
      final total = _savedMilliseconds + elapsed;
      final wasRunning = _foreground.isRunning;

      _foreground.stop();
      _foreground.reset();

      if (wasRunning) {
        _foreground.start();
      }

      _savedMilliseconds = total;

      if (_lastPersistedMilliseconds == total) {
        return;
      }

      if (!await prefs.setInt(_usageKey, total)) {
        throw StateError(
          'Could not save app rating usage.',
        );
      }

      _lastPersistedMilliseconds = total;
    });
  }

  bool beginPrompt() {
    if (!shouldPrompt) return false;

    _promptVisible = true;
    _foreground.stop();

    return true;
  }

  void endPrompt() {
    _promptVisible = false;
  }

  Future<void> remindLater() {
    return _serialise(() async {
      final prefs = _prefs;

      if (prefs == null) {
        throw StateError('Rating service not ready.');
      }

      final nextReminder =
          DateTime.now().add(reminderInterval);

      if (!await prefs.setInt(
        _reminderKey,
        nextReminder.millisecondsSinceEpoch,
      )) {
        throw StateError(
          'Could not save rating reminder.',
        );
      }
    });
  }

  Future<void> dontAskAgain() {
    return _serialise(() async {
      final prefs = _prefs;

      if (prefs == null) {
        throw StateError('Rating service not ready.');
      }

      if (!await prefs.setBool(_disabledKey, true)) {
        throw StateError(
          'Could not save rating preference.',
        );
      }

      _foreground.stop();
    });
  }

  Future<bool> openGooglePlay() async {
    final marketUri = Uri.parse(
      'market://details?id=$applicationId',
    );

    final webUri = Uri.https(
      'play.google.com',
      '/store/apps/details',
      {'id': applicationId},
    );

    var opened = false;

    try {
      opened = await launchUrl(
        marketUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Fall back to the web listing.
    }

    if (!opened) {
      try {
        opened = await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }

    if (opened) {
      await _serialise(() async {
        final prefs = _prefs;

        if (prefs != null) {
          if (!await prefs.setBool(_openedKey, true)) {
            throw StateError(
              'Could not save rating prompt preference.',
            );
          }

          _foreground.stop();
        }
      });
    }

    return opened;
  }
}