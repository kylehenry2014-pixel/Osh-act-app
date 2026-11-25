import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/translation.dart';

/// Languages the app supports, or is working toward. isiZulu and isiXhosa
/// are listed but held back from general use until their translations
/// have been reviewed by a native speaker, given the accuracy stakes of
/// translating safety law.
class AppLanguage {
  final String code;
  final String label;
  final String ttsLocale;
  final bool available;
  const AppLanguage(this.code, this.label, this.ttsLocale, this.available);
}

const List<AppLanguage> kSupportedLanguages = [
  AppLanguage('en', 'English', 'en-ZA', true),
  AppLanguage('af', 'Afrikaans', 'af-ZA', true),
];

class TranslationsRepository {
  TranslationsRepository._();
  static final TranslationsRepository instance = TranslationsRepository._();

  static const _languageKey = 'app_language';

  final Map<String, Map<String, EntryTranslation>> _byLanguage = {};
  String _currentLanguage = 'en';
  bool _loaded = false;

  Future<void>? _loading;
  Future<void> _languageQueue = Future<void>.value();

  bool _preferencesReloadRequired = false;

  bool _isSupportedLanguage(String code) {
    return kSupportedLanguages.any(
      (language) =>
          language.code == code && language.available,
    );
  }

  String get currentLanguage => _currentLanguage;

  Future<void> load() {
    if (_loaded) return Future<void>.value();

    return _loading ??=
        _loadOnce().whenComplete(() => _loading = null);
  }

  Future<void> _loadOnce() async {
    var preferredLanguage = 'en';

    // Invalid preferences must not prevent access
    // to the original English legislation.
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_preferencesReloadRequired) {
        await prefs.reload();
        _preferencesReloadRequired = false;
      }

      final stored = prefs.get(_languageKey);

      if (stored is String &&
          _isSupportedLanguage(stored)) {
        preferredLanguage = stored;
      } else if (stored != null) {
        debugPrint(
          'Unsupported language preference. Using English.',
        );
      }
    } catch (_) {
      _preferencesReloadRequired = true;

      debugPrint(
        'Language preferences unavailable. Using English.',
      );
    }

    final translations =
        <String, Map<String, EntryTranslation>>{};

    for (final lang in kSupportedLanguages) {
      if (lang.code == 'en' || !lang.available) {
        continue;
      }

      try {
        final raw = await rootBundle.loadString(
          'assets/data/translations_${lang.code}.json',
        );

        final decoded = jsonDecode(raw);

        if (decoded is! List) {
          throw const FormatException(
            'Invalid translation catalogue.',
          );
        }

        final map = <String, EntryTranslation>{};

        for (final item in decoded) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException(
              'Invalid translation record.',
            );
          }

          final translation =
              EntryTranslation.fromJson(item);

          if (translation.entryId.trim().isEmpty) {
            throw const FormatException(
              'Missing translation entry ID.',
            );
          }

          if (map.containsKey(translation.entryId)) {
            throw const FormatException(
              'Duplicate translation entry ID.',
            );
          }

          map[translation.entryId] = translation;
        }

        translations[lang.code] = map;
      } catch (_) {
        // Do not publish a partially damaged catalogue.
        // Original English content remains available.
        translations[lang.code] = {};

        debugPrint(
          'Translation catalogue unavailable: ${lang.code}',
        );
      }
    }

    _byLanguage
      ..clear()
      ..addAll(translations);

    _currentLanguage = preferredLanguage;
    _loaded = true;
  }

  Future<void> setLanguage(String code) {
    final operation = _languageQueue.then((_) async {
      await load();

      if (!_isSupportedLanguage(code)) {
        throw ArgumentError('Unsupported language.');
      }

      if (code != 'en' &&
          (_byLanguage[code]?.isEmpty ?? true)) {
        throw StateError(
          'This translation is currently unavailable.',
        );
      }

      final prefs = await SharedPreferences.getInstance();

      if (_preferencesReloadRequired) {
        await prefs.reload();
        _preferencesReloadRequired = false;
      }

      try {
        final saved = await prefs.setString(
          _languageKey,
          code,
        );

        if (!saved) {
          throw StateError(
            'Could not save the language preference.',
          );
        }
      } catch (_) {
        _preferencesReloadRequired = true;

        try {
          await prefs.reload();
          _preferencesReloadRequired = false;
        } catch (_) {
          debugPrint(
            'Language preference reload failed.',
          );
        }

        rethrow;
      }

      // Change the active language only after
      // the preference write reports success.
      _currentLanguage = code;
    });

    _languageQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return operation;
  }

  /// Returns the translation for [entryId] in the current language, or
  /// null if the current language is English or no translation exists yet
  /// for that specific entry (callers should fall back to the English text).
  EntryTranslation? translationFor(String entryId) {
    if (_currentLanguage == 'en') return null;
    return _byLanguage[_currentLanguage]?[entryId];
  }

  int translatedCount(String languageCode) => _byLanguage[languageCode]?.length ?? 0;
}
