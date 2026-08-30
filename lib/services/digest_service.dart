import 'package:shared_preferences/shared_preferences.dart';

import '../data/db_sync_service.dart';
import '../data/market_database.dart';
import '../models/daily_digest.dart';
import '../models/growth_window.dart';
import '../models/market.dart';
import '../models/stock_row.dart';
import '../utils/formatters.dart';
import 'notifier.dart';

/// What one scheduled run did, so the caller can report it.
class DigestRun {
  const DigestRun({required this.refreshed, required this.digest});

  /// Files whose bytes changed in this run.
  final List<Market> refreshed;

  /// The 7-day comparison, or null when it was skipped.
  final DailyDigest? digest;

  bool get postedAnything => refreshed.isNotEmpty || (digest?.hasNews ?? false);
}

/// Keeps the files current and says when a ticker joins the 7-day screen.
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
  static const _stampPrefix = 'digest_file_stamp_';

  /// Payload carried by a 7-day alert, so a tap opens the list it is about.
  static const tapPayload = 'digest:7d';

  /// At most this many tickers per file get a notification of their own; the
  /// rest are counted in the summary. A run that adds forty names should not
  /// put forty notifications in the shade.
  ///
  /// Per file, not in total: each market's alerts are their own group, so this
  /// is what one collapsed group opens into.
  static const maxAlertsPerMarket = 8;

  /// The day the last alert went out, as `yyyy-mm-dd`, or null.
  String? get lastSentDay => _prefs.getString(_lastSentKey);

  /// The last alert's text, for the settings screen to show what went out.
  (String, String)? get lastSentText {
    final title = _prefs.getString(_lastTitleKey);
    final body = _prefs.getString(_lastBodyKey);
    return title == null || body == null ? null : (title, body);
  }

  /// The tickers the last run saw, which today's is compared against.
  Set<String> get snapshot => _prefs.getStringList(_snapshotKey)?.toSet() ?? {};

  static String dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Downloads every file and posts a notification for each one that changed.
  ///
  /// The conditional request means an unchanged file costs nothing and says
  /// nothing: a notification every couple of hours reporting no change would
  /// be noise.
  Future<List<Market>> refresh() async {
    final changed = <Market>[];

    for (final market in Market.values) {
      try {
        final before = _prefs.getString('$_stampPrefix${market.id}');
        final asset = await _sync.sync(market);
        final stamp = '${asset.etag ?? asset.lastModified ?? ''}'
            ':${asset.sizeBytes}';

        // A first sync has nothing to compare against, so it is recorded
        // rather than announced as a change.
        if (before != null && before != stamp) {
          changed.add(market);
          await _notifier.show(
            AppNotification(
              id: NotificationIds.forFile(market),
              title: '${market.emoji} ${market.objectKey} refreshed',
              // No time in the body: the shade stamps every notification with
              // its arrival, and the clock format carries seconds and a zone
              // that read as noise here.
              body: '${Fmt.bytes(asset.sizeBytes)} downloaded',
            ),
          );
        }
        await _prefs.setString('$_stampPrefix${market.id}', stamp);
      } on Object {
        // A failed download is not worth a notification of its own; the app
        // shows the failure on its data-source screen.
      }
    }

    return changed;
  }

  /// Notifies about tickers that were not in the 7-day screen last time.
  ///
  /// Nothing new means nothing posted. There is no once-a-day guard: the
  /// comparison itself is the guard, so running twice a day — which the 9 and
  /// 11 o'clock refreshes do — cannot repeat a ticker.
  Future<DailyDigest?> notifyNewcomers({bool force = false}) async {
    final digest = DailyDigest.build(
      rows: await _sevenDayRows(),
      previousKeys: snapshot,
      date: _now(),
    );

    if (digest.isEmpty) return digest;

    // The first run has no yesterday to compare against, so it records the
    // baseline silently rather than announcing 113 "new" tickers.
    if (digest.isFirstRun && !force) {
      await _remember(digest, posted: false);
      return digest;
    }

    if (digest.newcomers.isEmpty && !force) {
      await _remember(digest, posted: false);
      return digest;
    }

    // One file at a time. They are separate screens over separate universes,
    // so a morning that adds names to both is two pieces of news: each gets
    // its own alerts under its own summary, and neither can crowd the other
    // out of a shared budget.
    var posted = false;
    for (final market in Market.values) {
      posted = await _announce(digest.onlyFor(market), force: force) || posted;
    }

    await _remember(digest, posted: posted);
    return digest;
  }

  /// Posts one file's newcomers. Returns whether anything went out.
  Future<bool> _announce(DailyDigest digest, {required bool force}) async {
    final market = digest.market!;
    if (digest.isEmpty) return false;

    final newcomers = digest.newcomers;
    if (newcomers.isEmpty && !force) return false;

    // One notification per ticker: the ticker and its name in the title, what
    // it did underneath.
    final alerts = (newcomers.isEmpty ? digest.rows : newcomers)
        .take(maxAlertsPerMarket)
        .toList();
    if (alerts.isEmpty) return false;

    for (final row in alerts) {
      await _notifier.show(
        AppNotification(
          id: NotificationIds.forTicker(row.key),
          title: '${row.pctChange >= 0 ? '📈' : '📉'} ${row.ticker} — '
              '${row.shortName}',
          body: alertBody(row),
          payload: tapPayload,
          group: NotificationIds.sevenDayGroupFor(market),
        ),
      );
    }

    // A summary above them, which is what Android collapses the group into.
    // It carries a line per ticker rather than one long sentence, so the
    // expanded group reads as a list.
    if (alerts.length > 1) {
      await _notifier.show(
        AppNotification(
          id: NotificationIds.digestFor(market),
          title: '${market.emoji} ${digest.title}',
          body: digest.body,
          payload: tapPayload,
          group: NotificationIds.sevenDayGroupFor(market),
          isGroupSummary: true,
          lines: [for (final row in alerts) summaryLine(row)],
          summaryText:
              '${digest.rows.length} ${market.instrumentNoun} in the screen',
        ),
      );
    }

    return true;
  }

  /// What one ticker's notification says under its name.
  ///
  /// The ticker and its name are the title, so the body starts at the news:
  /// two lines rather than one sentence, because the move is the news, the
  /// price is what you check next, and the cut-off says why the ticker is in the file
  /// at all. Prices carry the market's own currency — a bare `$` in front of
  /// an ASX price reads as US dollars.
  static String alertBody(StockRow row) {
    final direction = row.pctChange >= 0 ? 'Increased' : 'Fell';
    final move =
        '$direction ${Fmt.percent(row.pctChange.abs(), decimals: 1)} '
        'in the last week.';
    final price = 'Current price ${row.market.money(row.latestPrice)}';

    final cutOff = row.threshold;
    if (cutOff == null) return '$move\n$price';
    return '$move\n$price · 7-day screen cut-off ${_cutOff(cutOff)}';
  }

  /// One ticker's line in the grouped summary.
  static String summaryLine(StockRow row) =>
      '${row.ticker} ${Fmt.signedPercent(row.pctChange, decimals: 1)} · '
      '${row.market.money(row.latestPrice)} · ${row.shortName}';

  /// Thresholds are published as round numbers far more often than not, and
  /// `20.0%` in a notification reads as false precision.
  static String _cutOff(double value) => Fmt.percent(
    value,
    decimals: value == value.roundToDouble() ? 0 : 1,
  );

  /// Refreshes, reports changed files, then reports new tickers.
  Future<DigestRun> run({bool force = false, bool refresh = true}) async {
    final refreshed = refresh ? await this.refresh() : <Market>[];
    return DigestRun(
      refreshed: refreshed,
      digest: await notifyNewcomers(force: force),
    );
  }

  /// Builds the comparison without posting or recording anything.
  Future<DailyDigest> preview() async => DailyDigest.build(
    rows: await _sevenDayRows(),
    previousKeys: snapshot,
    date: _now(),
  );

  Future<void> _remember(DailyDigest digest, {required bool posted}) async {
    await _prefs.setStringList(_snapshotKey, digest.keys.toList()..sort());
    if (!posted) return;
    await _prefs.setString(_lastSentKey, dayKey(_now()));
    await _prefs.setString(_lastTitleKey, digest.title);
    await _prefs.setString(_lastBodyKey, digest.body);
  }

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
        // produces a comparison.
      } finally {
        await database?.close();
      }
    }
    return rows;
  }

  /// Forgets what the last run saw, so the next one starts fresh.
  Future<void> reset() async {
    await _prefs.remove(_snapshotKey);
    await _prefs.remove(_lastSentKey);
    await _prefs.remove(_lastTitleKey);
    await _prefs.remove(_lastBodyKey);
    for (final market in Market.values) {
      await _prefs.remove('$_stampPrefix${market.id}');
    }
  }
}
