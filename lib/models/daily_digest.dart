import 'market.dart';
import 'stock_row.dart';
import '../utils/formatters.dart';

/// What the day's run published in the 7-day window, and what changed.
///
/// The pipeline republishes both files every morning; the interesting part of
/// a new run is not the whole list but the names that were not in yesterday's,
/// so the digest carries both and the notification leads with the newcomers.
class DailyDigest {
  const DailyDigest({
    required this.date,
    required this.rows,
    required this.newKeys,
    required this.droppedKeys,
    required this.isFirstRun,
  });

  /// The day this digest describes, in local time.
  final DateTime date;

  /// Every row published in the 7-day window, both markets, strongest first.
  final List<StockRow> rows;

  /// Rows present today that were not in the previous digest, by [StockRow.key].
  final Set<String> newKeys;

  /// Rows in the previous digest that today's run dropped.
  final Set<String> droppedKeys;

  /// True when there was no previous snapshot to compare against, so nothing
  /// can honestly be called new.
  final bool isFirstRun;

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

  /// Today's newcomers, strongest first.
  List<StockRow> get newcomers => [
    for (final row in rows)
      if (newKeys.contains(row.key)) row,
  ];

  int countFor(Market market) =>
      rows.where((row) => row.market == market).length;

  /// The notification's first line.
  String get title {
    if (isEmpty) return 'No 7-day screen published today';
    if (isFirstRun || newKeys.isEmpty) {
      return '${rows.length} in the 7-day screen';
    }
    final count = newKeys.length;
    return '$count new in the 7-day screen';
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
    parts.add(_marketBreakdown);
    return parts.join(' · ');
  }

  String get _marketBreakdown {
    final counts = [
      for (final market in Market.values)
        if (countFor(market) > 0) '${countFor(market)} ${market.label}',
    ];
    return counts.isEmpty ? '' : counts.join(' · ');
  }
}
