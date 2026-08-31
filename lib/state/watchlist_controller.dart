import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market.dart';

/// Starred tickers, persisted as `market:TICKER` strings.
class WatchlistController extends ChangeNotifier {
  WatchlistController(this._prefs) {
    _entries = (_prefs.getStringList(_key) ?? const <String>[]).toSet();
  }

  static const _key = 'watchlist';

  final SharedPreferences _prefs;
  late Set<String> _entries;

  static String entryFor(Market market, String ticker) =>
      '${market.id}:$ticker';

  bool contains(Market market, String ticker) =>
      _entries.contains(entryFor(market, ticker));

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Every entry as `market:TICKER`, sorted — a stable description of what is
  /// starred, for callers that cache work against it.
  List<String> get keys => _entries.toList()..sort();

  /// Starred tickers for one market, without the market prefix.
  List<String> tickersFor(Market market) {
    final prefix = '${market.id}:';
    return [
      for (final entry in _entries)
        if (entry.startsWith(prefix)) entry.substring(prefix.length),
    ]..sort();
  }

  int countFor(Market market) => tickersFor(market).length;

  Future<bool> toggle(Market market, String ticker) async {
    final entry = entryFor(market, ticker);
    final added = !_entries.contains(entry);
    if (added) {
      _entries.add(entry);
    } else {
      _entries.remove(entry);
    }
    notifyListeners();
    await _persist();
    return added;
  }

  /// Puts a ticker back, for the undo a swipe deserves.
  Future<void> add(Market market, String ticker) async {
    if (_entries.add(entryFor(market, ticker))) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> remove(Market market, String ticker) async {
    if (_entries.remove(entryFor(market, ticker))) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      _prefs.setStringList(_key, _entries.toList()..sort());
}
