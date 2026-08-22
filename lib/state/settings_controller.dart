import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences that outlive a session.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  static const _themeKey = 'theme_mode';
  static const _compactKey = 'compact_rows';

  final SharedPreferences _prefs;

  ThemeMode get themeMode {
    switch (_prefs.getString(_themeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  /// Denser list rows for people scanning long result sets.
  bool get compactRows => _prefs.getBool(_compactKey) ?? false;

  Future<void> setCompactRows(bool value) async {
    await _prefs.setBool(_compactKey, value);
    notifyListeners();
  }
}
