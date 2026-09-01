import 'package:shared_preferences/shared_preferences.dart';

import '../data/db_sync_service.dart';
import '../data/market_database.dart';
import '../models/daily_digest.dart';
import '../models/growth_window.dart';
import '../models/market.dart';
import '../models/stock_row.dart';
import '../state/digest_router.dart';
import '../state/settings_controller.dart';
import '../utils/formatters.dart';
import 'notifier.dart';

/// Network and cache health from one check.
class DigestRefresh {
  const DigestRefresh({
    required this.changed,
    required this.succeeded,
    required this.failures,
  });

  final List<Market> changed;
  final List<Market> succeeded;
  final Map<Market, String> failures;

  bool get allSucceeded => failures.isEmpty;
}

/// What one scheduled run did, so the caller can report it.
class DigestRun {
  const DigestRun({required this.refresh, required this.digest});

  /// Files whose bytes changed in this run.
  List<Market> get refreshed => refresh.changed;

  final DigestRefresh refresh;

  /// The 7-day comparison, or null when it was skipped.
  final DailyDigest? digest;

  bool get postedAnything => digest?.hasNews ?? false;
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
  static const _lastAttemptKey = 'digest_last_attempt';
  static const _lastSuccessKey = 'digest_last_success';
  static const _lastErrorKey = 'digest_last_error';
  static const _failureCountKey = 'digest_failure_count';
  static const _lastHealthAlertKey = 'digest_last_health_alert';

  /// Payload carried by a 7-day alert, so a tap opens the list it is about.
  static final tapPayload = const NotificationRoute.screen(
    window: GrowthWindow.sevenDays,
  ).toPayload();

  /// At most this many rows appear when the consolidated alert is expanded.
  /// The title and body still report the full count.
  static const maxSummaryLines = 8;

  /// The day the last alert went out, as `yyyy-mm-dd`, or null.
  String? get lastSentDay => _prefs.getString(_lastSentKey);

  /// The last alert's text, for the settings screen to show what went out.
  (String, String)? get lastSentText {
    final title = _prefs.getString(_lastTitleKey);
    final body = _prefs.getString(_lastBodyKey);
    return title == null || body == null ? null : (title, body);
  }

  DateTime? get lastAttempt => _storedDate(_lastAttemptKey);
  DateTime? get lastSuccess => _storedDate(_lastSuccessKey);
  String? get lastError => _prefs.getString(_lastErrorKey);

  /// The tickers the last run saw, which today's is compared against.
  Set<String> get snapshot => _prefs.getStringList(_snapshotKey)?.toSet() ?? {};

  static String dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Downloads every file and records health for the in-app status panel.
  /// Successful file refreshes are routine plumbing, not user-facing news.
  Future<DigestRefresh> refresh({bool allowHealthAlert = true}) async {
    final changed = <Market>[];
    final succeeded = <Market>[];
    final failures = <Market, String>{};
    await _prefs.setString(_lastAttemptKey, _now().toIso8601String());

    for (final market in Market.values) {
      try {
        final before = _prefs.getString('$_stampPrefix${market.id}');
        final asset = await _sync.sync(market);
        final stamp =
            '${asset.etag ?? asset.lastModified ?? ''}'
            ':${asset.sizeBytes}';

        // A first sync has nothing to compare against, so it is recorded
        // rather than announced as a change.
        if (before != null && before != stamp) {
          changed.add(market);
        }
        succeeded.add(market);
        await _prefs.setString('$_stampPrefix${market.id}', stamp);
      } on Object catch (error) {
        failures[market] = error.toString();
      }
    }

    if (failures.isEmpty) {
      await _prefs.setString(_lastSuccessKey, _now().toIso8601String());
      await _prefs.remove(_lastErrorKey);
      await _prefs.setInt(_failureCountKey, 0);
    } else {
      final labels = failures.keys.map((market) => market.label).join(', ');
      await _prefs.setString(_lastErrorKey, 'Could not update $labels');
      final failureCount = (_prefs.getInt(_failureCountKey) ?? 0) + 1;
      await _prefs.setInt(_failureCountKey, failureCount);
      if (allowHealthAlert) {
        try {
          await _maybeWarnAboutStaleData(failures.keys, failureCount);
        } on Object {
          // Notification availability must never turn a completed data check
          // into a failed check or a WorkManager retry loop.
        }
      }
    }

    return DigestRefresh(
      changed: changed,
      succeeded: succeeded,
      failures: failures,
    );
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

    final settings = SettingsController(_prefs);
    final selectedMarkets = settings.alertMarkets;
    final minimumMove = settings.minimumAlertMove;
    final visibleRows = [
      for (final row in digest.rows)
        if (selectedMarkets.contains(row.market) &&
            row.pctChange.abs() >= minimumMove)
          row,
    ];
    final visibleKeys = {for (final row in visibleRows) row.key};
    final announcement = DailyDigest(
      date: digest.date,
      rows: visibleRows,
      newKeys: digest.newKeys.intersection(visibleKeys),
      droppedKeys: digest.droppedKeys,
      isFirstRun: digest.isFirstRun,
    );

    var posted = false;
    if ((announcement.hasNews || force) &&
        await _notifier.permissionStatus() ==
            NotificationPermissionStatus.enabled) {
      posted = await _announce(
        announcement,
        force: force,
        includeWatchlist:
            settings.alertDeliveryMode == AlertDeliveryMode.summaryAndWatchlist,
      );
    }

    await _remember(digest, posted: posted, sent: announcement);
    return digest;
  }

  /// Posts one consolidated update, plus optional quiet watchlist links.
  Future<bool> _announce(
    DailyDigest digest, {
    required bool force,
    required bool includeWatchlist,
  }) async {
    if (digest.isEmpty) return false;

    final newcomers = digest.newcomers;
    if (newcomers.isEmpty && !force) return false;

    final alerts = newcomers.isEmpty ? digest.rows : newcomers;
    await _notifier.show(
      AppNotification(
        id: NotificationIds.digest,
        title: digest.title,
        body: digest.body,
        payload: tapPayload,
        lines: [
          for (final row in alerts.take(maxSummaryLines)) summaryLine(row),
        ],
        summaryText: digest.marketBreakdown,
        actionLabel: 'View screen',
      ),
    );

    if (includeWatchlist) {
      final watchlist = _prefs.getStringList('watchlist')?.toSet() ?? const {};
      for (final row in newcomers.where((row) => watchlist.contains(row.key))) {
        await _notifier.show(
          AppNotification(
            id: NotificationIds.forTicker(row.key),
            title: '⭐ ${row.ticker} entered the 7-day screen',
            body: alertBody(row),
            payload: NotificationRoute.stock(
              market: row.market,
              ticker: row.ticker,
            ).toPayload(),
            kind: AppNotificationKind.watchlistAlert,
            silent: true,
            actionLabel: 'View stock',
          ),
        );
      }
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
    final asOf = row.dataAsOf ?? row.lastDate;
    final price =
        'Screened price ${row.market.money(row.latestPrice)}'
        '${asOf == null ? '' : ' · data as of $asOf'}';

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
  static String _cutOff(double value) =>
      Fmt.percent(value, decimals: value == value.roundToDouble() ? 0 : 1);

  /// Refreshes, reports changed files, then reports new tickers.
  Future<DigestRun> run({bool force = false, bool refresh = true}) async {
    final report = refresh
        ? await this.refresh()
        : DigestRefresh(
            changed: const [],
            succeeded: Market.values,
            failures: const {},
          );
    return DigestRun(
      refresh: report,
      // Never compare yesterday's cache with today's snapshot after a failed
      // network run. WorkManager retries the refresh instead.
      digest: report.allSucceeded ? await notifyNewcomers(force: force) : null,
    );
  }

  /// Sends exactly one example, independent of the current screen contents.
  Future<void> sendSample() async {
    await _notifier.show(
      AppNotification(
        id: NotificationIds.test,
        title: '2 new in the 7-day screen',
        body: 'MRNA +18.4%, QETH +12.1% · 1 US · 1 ASX',
        payload: tapPayload,
        kind: AppNotificationKind.sample,
        lines: const [
          r'MRNA +18.4% · $42.16 · Moderna, Inc.',
          r'QETH +12.1% · A$18.90 · Betashares Ethereum ETF',
        ],
        summaryText: 'Example only',
        actionLabel: 'View screen',
      ),
    );
  }

  /// Builds the comparison without posting or recording anything.
  Future<DailyDigest> preview() async {
    final settings = SettingsController(_prefs);
    final selectedMarkets = settings.alertMarkets;
    final minimumMove = settings.minimumAlertMove;
    return DailyDigest.build(
      rows: [
        for (final row in await _sevenDayRows())
          if (selectedMarkets.contains(row.market) &&
              row.pctChange.abs() >= minimumMove)
            row,
      ],
      previousKeys: snapshot,
      date: _now(),
    );
  }

  Future<void> _maybeWarnAboutStaleData(
    Iterable<Market> failedMarkets,
    int failureCount,
  ) async {
    if (failureCount < 2 || !SettingsController(_prefs).dataHealthAlerts) {
      return;
    }

    final stale = <Market>[];
    for (final market in failedMarkets) {
      final cached = await _sync.cached(market);
      if (cached == null || _now().difference(cached.syncedAt).inHours >= 24) {
        stale.add(market);
      }
    }
    if (stale.isEmpty) return;

    final today = dayKey(_now());
    if (_prefs.getString(_lastHealthAlertKey) == today) return;
    if (await _notifier.permissionStatus() !=
        NotificationPermissionStatus.enabled) {
      return;
    }

    final labels = stale.map((market) => market.label).join(', ');
    await _notifier.show(
      AppNotification(
        id: NotificationIds.dataHealth,
        title: 'Market data needs attention',
        body: '$labels could not refresh and may be more than 24 hours old.',
        payload: const NotificationRoute.dataSources().toPayload(),
        kind: AppNotificationKind.dataHealth,
        silent: true,
        actionLabel: 'View data sources',
      ),
    );
    await _prefs.setString(_lastHealthAlertKey, today);
  }

  DateTime? _storedDate(String key) =>
      DateTime.tryParse(_prefs.getString(key) ?? '');

  Future<void> _remember(
    DailyDigest digest, {
    required bool posted,
    DailyDigest? sent,
  }) async {
    await _prefs.setStringList(_snapshotKey, digest.keys.toList()..sort());
    if (!posted) return;
    final delivered = sent ?? digest;
    await _prefs.setString(_lastSentKey, dayKey(_now()));
    await _prefs.setString(_lastTitleKey, delivered.title);
    await _prefs.setString(_lastBodyKey, delivered.body);
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
    await _prefs.remove(_lastAttemptKey);
    await _prefs.remove(_lastSuccessKey);
    await _prefs.remove(_lastErrorKey);
    await _prefs.remove(_failureCountKey);
    await _prefs.remove(_lastHealthAlertKey);
    for (final market in Market.values) {
      await _prefs.remove('$_stampPrefix${market.id}');
    }
  }
}
