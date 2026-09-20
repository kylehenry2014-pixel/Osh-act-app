import 'dart:convert';
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

  String get currentLanguage => _currentLanguage;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_languageKey) ?? 'en';

    for (final lang in kSupportedLanguages) {
      if (lang.code == 'en') continue;
      try {
        final raw = await rootBundle.loadString('assets/data/translations_${lang.code}.json');
        final List<dynamic> jsonList = json.decode(raw) as List<dynamic>;
        final map = <String, EntryTranslation>{};
        for (final item in jsonList) {
          final t = EntryTranslation.fromJson(item as Map<String, dynamic>);
          map[t.entryId] = t;
        }
        _byLanguage[lang.code] = map;
      } catch (_) {
        // No translation file yet for this language - falls back to English everywhere.
        _byLanguage[lang.code] = {};
      }
    }
    _loaded = true;
  }

  Future<void> setLanguage(String code) async {
    _currentLanguage = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
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
