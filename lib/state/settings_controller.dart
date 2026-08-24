import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences that outlive a session.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  static const _themeKey = 'theme_mode';
  static const _compactKey = 'compact_rows';
  static const _sidebarKey = 'sidebar_collapsed';
  static const _digestKey = 'digest_enabled';
  static const _digestHourKey = 'digest_hour';
  static const _digestMinuteKey = 'digest_minute';

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

  /// The desktop sidebar, narrowed to a rail of icons. Remembered, because
  /// someone who wants the width back wants it back every time.
  bool get sidebarCollapsed => _prefs.getBool(_sidebarKey) ?? false;

  Future<void> setSidebarCollapsed(bool value) async {
    await _prefs.setBool(_sidebarKey, value);
    notifyListeners();
  }

  Future<void> toggleSidebar() => setSidebarCollapsed(!sidebarCollapsed);

  /// The morning digest of the 7-day screen.
  bool get digestEnabled => _prefs.getBool(_digestKey) ?? false;

  Future<void> setDigestEnabled(bool value) async {
    await _prefs.setBool(_digestKey, value);
    notifyListeners();
  }

  /// When the digest goes out, local time.
  ///
  /// Defaults to a quarter past eight: the pipeline republishes both files at
  /// eight, and a digest built at eight sharp can summarise yesterday's.
  TimeOfDay get digestTime => TimeOfDay(
    hour: _prefs.getInt(_digestHourKey) ?? 8,
    minute: _prefs.getInt(_digestMinuteKey) ?? 15,
  );

  Future<void> setDigestTime(TimeOfDay value) async {
    await _prefs.setInt(_digestHourKey, value.hour);
    await _prefs.setInt(_digestMinuteKey, value.minute);
    notifyListeners();
  }
}
