import 'package:shared_preferences/shared_preferences.dart';

import '../data/db_sync_service.dart';
import '../data/market_database.dart';
import '../models/daily_digest.dart';
import '../models/growth_window.dart';
import '../models/market.dart';
import '../models/stock_row.dart';
import 'notifier.dart';

/// Builds the morning digest of the 7-day screen and posts it.
///
/// Deliberately independent of [AppState]: the same code runs on the UI
/// isolate when the app is opened and on the background isolate the scheduler
/// wakes, and the background one has no widget tree to read state from.
class DigestService {
  DigestService({
    required SharedPreferences preferences,
    required DbSyncService sync,
    required Notifier notifier,
    DateTime Function()? clock,
  }) : _prefs = preferences,
       _sync = sync,
       _notifier = notifier,
       _now = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DbSyncService _sync;
  final Notifier _notifier;
  final DateTime Function() _now;

  static const _snapshotKey = 'digest_snapshot_7d';
  static const _lastSentKey = 'digest_last_sent';
  static const _lastTitleKey = 'digest_last_title';
  static const _lastBodyKey = 'digest_last_body';

  /// Payload carried by the digest notification, so a tap can open the list
  /// the digest describes rather than wherever the app was last.
  static const tapPayload = 'digest:7d';

  /// The day the last digest went out, as `yyyy-mm-dd`, or null.
  String? get lastSentDay => _prefs.getString(_lastSentKey);

  /// The last digest's text, for the settings screen to show what went out.
  (String, String)? get lastSentText {
    final title = _prefs.getString(_lastTitleKey);
    final body = _prefs.getString(_lastBodyKey);
    return title == null || body == null ? null : (title, body);
  }

  /// The tickers the last digest carried, which today's run is compared to.
  Set<String> get snapshot => _prefs.getStringList(_snapshotKey)?.toSet() ?? {};

  static String dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// True when today's digest has not gone out yet.
  bool get isDue => lastSentDay != dayKey(_now());

  /// Fetches the files, builds the digest and posts it.
  ///
  /// Returns null when the digest has already gone out today and [force] is
  /// not set — the scheduler is inexact and may fire twice, and the app also
  /// asks on every launch.
  ///
  /// Set [refresh] to false to read whatever is cached, which is what the
  /// app does when it has just synced for itself.
  Future<DailyDigest?> run({bool force = false, bool refresh = true}) async {
    if (!force && !isDue) return null;

    if (refresh) {
      for (final market in Market.values) {
        try {
          await _sync.sync(market);
        } on Object {
          // A failed download is not a reason to skip the digest: the cached
          // file is still worth summarising, and the run may simply be late.
        }
      }
    }

    final digest = DailyDigest.build(
      rows: await _sevenDayRows(),
      previousKeys: snapshot,
      date: _now(),
    );

    // Nothing published at all: no notification, and the snapshot is left
    // alone so tomorrow still compares against the last real run.
    if (digest.isEmpty) return digest;

    await _notifier.show(
      AppNotification(
        id: NotificationIds.digest,
        title: digest.title,
        body: digest.body,
        payload: tapPayload,
      ),
    );

    await _prefs.setStringList(_snapshotKey, digest.keys.toList()..sort());
    await _prefs.setString(_lastSentKey, dayKey(_now()));
    await _prefs.setString(_lastTitleKey, digest.title);
    await _prefs.setString(_lastBodyKey, digest.body);
    return digest;
  }

  /// Builds today's digest without posting or recording anything.
  Future<DailyDigest> preview() async => DailyDigest.build(
    rows: await _sevenDayRows(),
    previousKeys: snapshot,
    date: _now(),
  );

  Future<List<StockRow>> _sevenDayRows() async {
    final rows = <StockRow>[];
    for (final market in Market.values) {
      final cached = await _sync.cached(market);
      if (cached == null) continue;
      MarketDatabase? database;
      try {
        database = await MarketDatabase.open(market, cached.path);
        if (!database.availableWindows.contains(GrowthWindow.sevenDays)) {
          continue;
        }
        rows.addAll(await database.stocks(GrowthWindow.sevenDays));
      } on Object {
        // A corrupt or half-written file is skipped; the other market still
        // produces a digest.
      } finally {
        await database?.close();
      }
    }
    return rows;
  }

  /// Forgets what the last digest carried, so the next one starts fresh.
  Future<void> reset() async {
    await _prefs.remove(_snapshotKey);
    await _prefs.remove(_lastSentKey);
    await _prefs.remove(_lastTitleKey);
    await _prefs.remove(_lastBodyKey);
  }
}
