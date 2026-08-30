import 'market.dart';
import 'stock_row.dart';
import '../utils/formatters.dart';

/// What the day's run published in the 7-day window, and what changed.
///
/// The pipeline republishes every file each morning; the interesting part of
/// a new run is not the whole list but the names that were not in yesterday's,
/// so the digest carries both and the notification leads with the newcomers.
class DailyDigest {
  const DailyDigest({
    required this.date,
    required this.rows,
    required this.newKeys,
    required this.droppedKeys,
    required this.isFirstRun,
    this.market,
  });

  /// The day this digest describes, in local time.
  final DateTime date;

  /// Every row published in the 7-day window, every market, strongest first.
  final List<StockRow> rows;

  /// Rows present today that were not in the previous digest, by [StockRow.key].
  final Set<String> newKeys;

  /// Rows in the previous digest that today's run dropped.
  final Set<String> droppedKeys;

  /// True when there was no previous snapshot to compare against, so nothing
  /// can honestly be called new.
  final bool isFirstRun;

  /// The one file this digest describes, or null when it covers them all.
  ///
  /// The files are separate screens over separate universes, and a run that
  /// adds names to more than one of them has that many pieces of news, not
  /// one. [onlyFor] narrows a whole-run digest to a single market so each can
  /// be announced on its own.
  final Market? market;

  /// Builds the digest for [rows] against the tickers the last one carried.
  factory DailyDigest.build({
    required List<StockRow> rows,
    required Set<String> previousKeys,
    required DateTime date,
  }) {
    final sorted = [...rows]
      ..sort((a, b) => b.pctChange.compareTo(a.pctChange));
    final keys = {for (final row in sorted) row.key};
    final first = previousKeys.isEmpty;

    return DailyDigest(
      date: DateTime(date.year, date.month, date.day),
      rows: sorted,
      newKeys: first ? const {} : keys.difference(previousKeys),
      droppedKeys: first ? const {} : previousKeys.difference(keys),
      isFirstRun: first,
    );
  }

  /// The snapshot to compare tomorrow's run against.
  Set<String> get keys => {for (final row in rows) row.key};

  bool get isEmpty => rows.isEmpty;

  /// True when this run has something to announce: a ticker that was not in
  /// the screen last time.
  bool get hasNews => newKeys.isNotEmpty;

  /// Today's newcomers, strongest first.
  List<StockRow> get newcomers => [
    for (final row in rows)
      if (newKeys.contains(row.key)) row,
  ];

  int countFor(Market market) =>
      rows.where((row) => row.market == market).length;

  /// Today's newcomers in one market, strongest first.
  List<StockRow> newcomersFor(Market market) => [
    for (final row in newcomers)
      if (row.market == market) row,
  ];

  /// This digest narrowed to one file.
  ///
  /// Everything a notification needs — the title, the leaders, the counts —
  /// then describes that market alone, rather than a pooled list in which the
  /// louder file always wins.
  DailyDigest onlyFor(Market market) {
    final mine = [
      for (final row in rows)
        if (row.market == market) row,
    ];
    final keys = {for (final row in mine) row.key};
    // Dropped tickers have no row today to read a market off, so they are
    // matched on the market prefix [StockRow.key] is built with.
    final prefix = '${market.id}:';

    return DailyDigest(
      date: date,
      rows: mine,
      newKeys: newKeys.intersection(keys),
      droppedKeys: {
        for (final key in droppedKeys)
          if (key.startsWith(prefix)) key,
      },
      isFirstRun: isFirstRun,
      market: market,
    );
  }

  /// What this digest is about: one file's screen, or all of them.
  String get _screen =>
      market == null ? '7-day screen' : '${market!.label} 7-day screen';

  /// The notification's first line.
  String get title {
    if (isEmpty) return 'No $_screen published today';
    if (isFirstRun || newKeys.isEmpty) {
      return '${rows.length} in the $_screen';
    }
    final count = newKeys.length;
    return '$count new in the $_screen';
  }

  /// The notification's body: the names, then the shape of the day.
  String get body {
    if (isEmpty) {
      return 'Today’s run published no rows for the 7-day window.';
    }

    final lead = newcomers.isEmpty ? rows : newcomers;
    final named = lead.take(4).toList();
    final leaders = [
      for (final row in named)
        '${row.ticker} ${Fmt.signedPercent(row.pctChange, decimals: 1)}',
    ].join(', ');
    final remainder = lead.length - named.length;

    final parts = <String>[
      remainder > 0 ? '$leaders and $remainder more' : leaders,
    ];
    if (!isFirstRun && newKeys.isEmpty) {
      parts.add('no new names since the last run');
    }
    // The title already names the file when the digest is scoped to one, so
    // the breakdown would only repeat it.
    if (market == null) parts.add(marketBreakdown);
    return parts.join(' · ');
  }

  /// How many rows each file contributed, e.g. `8 ASX · 153 US`.
  String get marketBreakdown {
    final counts = [
      for (final market in Market.values)
        if (countFor(market) > 0) '${countFor(market)} ${market.label}',
    ];
    return counts.isEmpty ? '' : counts.join(' · ');
  }
}
