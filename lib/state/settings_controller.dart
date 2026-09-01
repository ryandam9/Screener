import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market.dart';

/// How much detail a screen update is allowed to put in the notification
/// shade. The default stays deliberately calm; watchlist alerts are useful,
/// but only after someone asks for them.
enum AlertDeliveryMode {
  summaryOnly,
  summaryAndWatchlist;

  String get label => switch (this) {
    summaryOnly => 'Summary only',
    summaryAndWatchlist => 'Summary + watchlist',
  };

  String get description => switch (this) {
    summaryOnly => 'One notification for each check with new matches.',
    summaryAndWatchlist =>
      'Also show a quiet, direct alert for starred tickers.',
  };
}

/// User preferences that outlive a session.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs);

  static const _themeKey = 'theme_mode';
  static const _compactKey = 'compact_rows';
  static const _sidebarKey = 'sidebar_collapsed';
  static const digestEnabledKey = 'digest_enabled';
  static const _alertModeKey = 'alert_delivery_mode';
  static const _alertMarketsKey = 'alert_markets';
  static const _minimumMoveKey = 'alert_minimum_move';
  static const _dataHealthKey = 'data_health_alerts';
  static const _checkHourKey = 'digest_check_hour';
  static const _followUpKey = 'digest_follow_up';

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

  /// The scheduled refresh and the alerts it posts.
  bool get digestEnabled => _prefs.getBool(digestEnabledKey) ?? false;

  Future<void> setDigestEnabled(bool value) async {
    await _prefs.setBool(digestEnabledKey, value);
    notifyListeners();
  }

  AlertDeliveryMode get alertDeliveryMode {
    final stored = _prefs.getString(_alertModeKey);
    return AlertDeliveryMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => AlertDeliveryMode.summaryOnly,
    );
  }

  Future<void> setAlertDeliveryMode(AlertDeliveryMode mode) async {
    await _prefs.setString(_alertModeKey, mode.name);
    notifyListeners();
  }

  /// Markets included in the consolidated alert. An absent preference means
  /// all markets; an empty set is never stored, because a notification with no
  /// possible content is indistinguishable from turning notifications off.
  Set<Market> get alertMarkets {
    final stored = _prefs.getStringList(_alertMarketsKey);
    if (stored == null) return Market.values.toSet();
    final markets = {
      for (final id in stored)
        if (Market.fromId(id) case final market?) market,
    };
    return markets.isEmpty ? Market.values.toSet() : markets;
  }

  Future<void> setAlertMarkets(Set<Market> markets) async {
    if (markets.isEmpty) return;
    await _prefs.setStringList(_alertMarketsKey, [
      for (final market in Market.values)
        if (markets.contains(market)) market.id,
    ]);
    notifyListeners();
  }

  /// Additional move required before a newcomer is announced. Zero preserves
  /// the published screen's own threshold.
  double get minimumAlertMove => _prefs.getDouble(_minimumMoveKey) ?? 0;

  Future<void> setMinimumAlertMove(double value) async {
    await _prefs.setDouble(_minimumMoveKey, value);
    notifyListeners();
  }

  bool get dataHealthAlerts => _prefs.getBool(_dataHealthKey) ?? true;

  Future<void> setDataHealthAlerts(bool value) async {
    await _prefs.setBool(_dataHealthKey, value);
    notifyListeners();
  }

  /// WorkManager is intentionally described as "around" this time: Android
  /// chooses the exact moment based on constraints and battery policy.
  TimeOfDay get primaryCheckTime => TimeOfDay(
    hour: (_prefs.getInt(_checkHourKey) ?? 9).clamp(0, 23),
    minute: 0,
  );

  bool get followUpCheck => _prefs.getBool(_followUpKey) ?? true;

  List<TimeOfDay> get checkTimes => [
    primaryCheckTime,
    if (followUpCheck)
      TimeOfDay(hour: (primaryCheckTime.hour + 2) % 24, minute: 0),
  ];

  Future<void> setPrimaryCheckTime(TimeOfDay value) async {
    await _prefs.setInt(_checkHourKey, value.hour);
    notifyListeners();
  }

  Future<void> setFollowUpCheck(bool value) async {
    await _prefs.setBool(_followUpKey, value);
    notifyListeners();
  }
}
