import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Enable only after all screens have been migrated.
const bool kEnableAdaptiveAppearance = true;

class AppearanceController extends ChangeNotifier {
  AppearanceController._();

  static final AppearanceController instance =
      AppearanceController._();

  static const String _preferenceKey = 'app_appearance_mode';

  ThemeMode _mode = ThemeMode.light;
  bool _loaded = false;
  bool _saving = false;

  ThemeMode get mode => _mode;
  bool get isLoaded => _loaded;
  bool get isSaving => _saving;

  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_preferenceKey);

      switch (saved) {
        case 'dark':
          _mode = ThemeMode.dark;
          break;
        case 'system':
          _mode = ThemeMode.system;
          break;
        default:
          _mode = ThemeMode.light;
      }
    } catch (error) {
      _mode = ThemeMode.light;
      debugPrint('Appearance preferences could not be loaded.');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<bool> setMode(ThemeMode mode) async {
    if (!_loaded || _saving) return false;
    if (_mode == mode) return true;

    _saving = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      final saved = await prefs.setString(
        _preferenceKey,
        mode.name,
      );

      if (!saved) return false;

      _mode = mode;
      return true;
    } catch (error) {
      debugPrint('Appearance preferences could not be saved.');
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}