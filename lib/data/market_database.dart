import 'package:sqflite/sqflite.dart';

import '../models/growth_window.dart';
import '../models/market.dart';
import '../models/price_bar.dart';
import '../models/stock_row.dart';

/// Columns a list can be sorted by. Values are physical column names and are
/// interpolated into SQL, so the enum is the whitelist — never accept a raw
/// column name from anywhere else.
enum StockSort {
  pctChange('pct_change', 'Change'),
  ticker('ticker', 'Ticker'),
  name('name', 'Name'),
  latestPrice('latest_price', 'Price'),
  medianVolume('median_volume', 'Volume'),
  coverage('coverage', 'Coverage');

  const StockSort(this.column, this.label);
  final String column;
  final String label;
}

/// Filters applied to a stock list.
class StockQuery {
  const StockQuery({
    this.search,
    this.exchange,
    this.minPctChange,
    this.sort = StockSort.pctChange,
    this.descending = true,
    this.limit,
    this.offset,
    this.tickers,
  });

  final String? search;
  final String? exchange;
  final double? minPctChange;
  final StockSort sort;
  final bool descending;
  final int? limit;
  final int? offset;

  /// Restricts results to these tickers (used by the watchlist).
  final List<String>? tickers;

  StockQuery copyWith({
    String? search,
    String? exchange,
    double? minPctChange,
    StockSort? sort,
    bool? descending,
    int? limit,
    int? offset,
    List<String>? tickers,
    bool clearSearch = false,
    bool clearExchange = false,
    bool clearMinPctChange = false,
  }) {
    return StockQuery(
      search: clearSearch ? null : (search ?? this.search),
      exchange: clearExchange ? null : (exchange ?? this.exchange),
      minPctChange: clearMinPctChange
          ? null
          : (minPctChange ?? this.minPctChange),
      sort: sort ?? this.sort,
      descending: descending ?? this.descending,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      tickers: tickers ?? this.tickers,
    );
  }

  bool get hasFilters =>
      (search != null && search!.isNotEmpty) ||
      exchange != null ||
      (minPctChange != null && minPctChange! > 0);
}

/// Provenance of one window's table.
class RunInfo {
  const RunInfo({
    required this.market,
    required this.window,
    required this.rowCount,
    this.dataAsOf,
    this.runId,
  });

  final Market market;
  final GrowthWindow window;
  final int rowCount;
  final String? dataAsOf;
  final String? runId;

  /// The pipeline stamps run ids as `20260822T224430Z-a4761276`.
  DateTime? get runStartedAt {
    final id = runId;
    if (id == null || id.length < 16) return null;
    final stamp = id.split('-').first;
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
    ).firstMatch(stamp);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    ).toLocal();
  }
}

/// Aggregate stats for one window, used by the dashboard cards.
class WindowStat {
  const WindowStat({
    required this.window,
    required this.count,
    required this.medianPctChange,
    required this.maxPctChange,
    required this.minPctChange,
  });

  final GrowthWindow window;
  final int count;
  final double medianPctChange;
  final double maxPctChange;
  final double minPctChange;
}

/// Everything the dashboard needs about one market in a single round trip.
class MarketSummary {
  const MarketSummary({
    required this.market,
    required this.stats,
    required this.consistentCount,
    this.topGainer,
    this.dataAsOf,
  });

  final Market market;
  final List<WindowStat> stats;
  final int consistentCount;
  final StockRow? topGainer;
  final String? dataAsOf;

  WindowStat? statFor(GrowthWindow window) {
    for (final stat in stats) {
      if (stat.window == window) return stat;
    }
    return null;
  }
}

/// One opened market database.
///
/// The two published files do not share table names, so the physical tables
/// are discovered from `sqlite_master` at open time and mapped to windows by
/// suffix. Every query below goes through [_tableFor], which only ever returns
/// a name that came from that discovery.
class MarketDatabase {
  MarketDatabase._({
    required this.market,
    required this.path,
    required Database database,
    required Map<GrowthWindow, String> tables,
    required String? consistentTable,
    required String? seriesTable,
  }) : _db = database,
       _tables = tables,
       _consistentTable = consistentTable,
       _seriesTable = seriesTable;

  final Market market;
  final String path;
  final Database _db;
  final Map<GrowthWindow, String> _tables;
  final String? _consistentTable;
  final String? _seriesTable;

  /// The full growth curve costs roughly 650ms against the US file, and the
  /// dashboard asks for it on every rebuild, so it is computed once per open
  /// database. A filtered curve is cheap enough not to bother.
  List<GrowthPoint>? _growthCache;

  /// Windows this file actually contains, shortest first.
  List<GrowthWindow> get availableWindows {
    final windows = _tables.keys.toList()
      ..sort((a, b) => a.approximateDays.compareTo(b.approximateDays));
    return windows;
  }

  bool get hasConsistentTable => _consistentTable != null;

  /// True when the file publishes weekly price history alongside the windows.
  /// Older files carry only the per-window tables.
  bool get hasPriceHistory => _seriesTable != null;

  static Future<MarketDatabase> open(Market market, String path) async {
    final database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    final tables = <GrowthWindow, String>{};
    String? consistent;
    final candidates = <String>[];
    for (final row in rows) {
      final name = row['name'] as String?;
      if (name == null) continue;
      final window = GrowthWindow.fromTableName(name);
      if (window != null) {
        tables[window] = name;
      } else if (name.toLowerCase().contains('consistent')) {
        consistent = name;
      } else {
        candidates.add(name);
      }
    }

    // The price history is the leftover table carrying a date column; its name
    // is the window tables' prefix without a suffix ("us_stocks_growth"), but
    // it is identified by its columns rather than by that convention.
    String? series;
    for (final name in candidates) {
      final columns = await database.rawQuery('PRAGMA table_info("$name")');
      final hasDate = columns.any(
        (c) => (c['name'] as String?) == 'stock_price_date',
      );
      final hasClose = columns.any((c) => (c['name'] as String?) == 'close');
      if (hasDate && hasClose) {
        series = name;
        break;
      }
    }

    if (tables.isEmpty) {
      await database.close();
      throw StateError(
        '${market.objectKey} has no growth tables; found ${rows.length} table(s).',
      );
    }

    return MarketDatabase._(
      market: market,
      path: path,
      database: database,
      tables: tables,
      consistentTable: consistent,
      seriesTable: series,
    );
  }

  String? _tableFor(GrowthWindow window) => _tables[window];

  /// Builds the shared WHERE clause for a query.
  (String, List<Object?>) _where(StockQuery query) {
    final clauses = <String>[];
    final args = <Object?>[];

    final search = query.search?.trim();
    if (search != null && search.isNotEmpty) {
      clauses.add('(ticker LIKE ? OR name LIKE ?)');
      args
        ..add('%$search%')
        ..add('%$search%');
    }
    if (query.exchange != null) {
      clauses.add('exchange = ?');
      args.add(query.exchange);
    }
    if (query.minPctChange != null) {
      clauses.add('pct_change >= ?');
      args.add(query.minPctChange);
    }
    final tickers = query.tickers;
    if (tickers != null) {
      if (tickers.isEmpty) return ('WHERE 1 = 0', const []);
      clauses.add('ticker IN (${List.filled(tickers.length, '?').join(', ')})');
      args.addAll(tickers);
    }

    if (clauses.isEmpty) return ('', args);
    return ('WHERE ${clauses.join(' AND ')}', args);
  }

  Future<List<StockRow>> stocks(
    GrowthWindow window, [
    StockQuery query = const StockQuery(),
  ]) async {
    final table = _tableFor(window);
    if (table == null) return const [];

    final (where, args) = _where(query);
    final direction = query.descending ? 'DESC' : 'ASC';
    final buffer = StringBuffer('SELECT * FROM "$table" $where ')
      ..write('ORDER BY ${query.sort.column} $direction, ticker ASC');
    if (query.limit != null) {
      buffer.write(' LIMIT ${query.limit}');
      if (query.offset != null) buffer.write(' OFFSET ${query.offset}');
    }

    final rows = await _db.rawQuery(buffer.toString(), args);
    return [
      for (final row in rows)
        StockRow.fromMap(row, market: market, window: window),
    ];
  }

  Future<int> count(
    GrowthWindow window, [
    StockQuery query = const StockQuery(),
  ]) async {
    final table = _tableFor(window);
    if (table == null) return 0;
    final (where, args) = _where(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM "$table" $where',
      args,
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Every window's row for one ticker, shortest window first.
  Future<List<StockRow>> ticker(String symbol) async {
    final results = <StockRow>[];
    for (final window in availableWindows) {
      final table = _tables[window]!;
      final rows = await _db.rawQuery(
        'SELECT * FROM "$table" WHERE ticker = ? LIMIT 1',
        [symbol],
      );
      if (rows.isEmpty) continue;
      results.add(StockRow.fromMap(rows.first, market: market, window: window));
    }
    return results;
  }

  Future<List<String>> exchanges(GrowthWindow window) async {
    final table = _tableFor(window);
    if (table == null) return const [];
    final rows = await _db.rawQuery(
      'SELECT DISTINCT exchange FROM "$table" WHERE exchange IS NOT NULL ORDER BY exchange',
    );
    return [
      for (final row in rows)
        if (row['exchange'] != null) row['exchange'].toString(),
    ];
  }

  Future<RunInfo?> runInfo(GrowthWindow window) async {
    final table = _tableFor(window);
    if (table == null) return null;
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, MAX(data_as_of) AS data_as_of, MAX(run_id) AS run_id FROM "$table"',
    );
    final row = rows.first;
    final count = (row['n'] as num?)?.toInt() ?? 0;
    if (count == 0) {
      return RunInfo(market: market, window: window, rowCount: 0);
    }
    return RunInfo(
      market: market,
      window: window,
      rowCount: count,
      dataAsOf: row['data_as_of'] as String?,
      runId: row['run_id'] as String?,
    );
  }

  Future<List<RunInfo>> allRuns() async {
    final results = <RunInfo>[];
    for (final window in availableWindows) {
      final info = await runInfo(window);
      if (info != null) results.add(info);
    }
    return results;
  }

  Future<MarketSummary> summary() async {
    final stats = <WindowStat>[];
    String? dataAsOf;

    for (final window in availableWindows) {
      final table = _tables[window]!;
      final aggregate = await _db.rawQuery(
        'SELECT COUNT(*) AS n, MAX(pct_change) AS hi, MIN(pct_change) AS lo, '
        'MAX(data_as_of) AS data_as_of FROM "$table"',
      );
      final row = aggregate.first;
      final count = (row['n'] as num?)?.toInt() ?? 0;
      dataAsOf ??= row['data_as_of'] as String?;
      if (count == 0) {
        stats.add(
          WindowStat(
            window: window,
            count: 0,
            medianPctChange: 0,
            maxPctChange: 0,
            minPctChange: 0,
          ),
        );
        continue;
      }
      stats.add(
        WindowStat(
          window: window,
          count: count,
          medianPctChange: await _median(table, 'pct_change'),
          maxPctChange: (row['hi'] as num?)?.toDouble() ?? 0,
          minPctChange: (row['lo'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    final shortest = availableWindows.isEmpty ? null : availableWindows.first;
    StockRow? top;
    if (shortest != null) {
      final best = await stocks(shortest, const StockQuery(limit: 1));
      if (best.isNotEmpty) top = best.first;
    }

    return MarketSummary(
      market: market,
      stats: stats,
      consistentCount: await consistentCount(),
      topGainer: top,
      dataAsOf: dataAsOf,
    );
  }

  /// Median without a SQLite extension: take the middle row (or the middle two
  /// for an even count) from the ordered column and average them.
  Future<double> _median(String table, String column) async {
    final rows = await _db.rawQuery(
      'SELECT AVG($column) AS m FROM ('
      '  SELECT $column FROM "$table" WHERE $column IS NOT NULL ORDER BY $column'
      '  LIMIT 2 - ((SELECT COUNT(*) FROM "$table" WHERE $column IS NOT NULL) % 2)'
      '  OFFSET (SELECT (COUNT(*) - 1) / 2 FROM "$table" WHERE $column IS NOT NULL)'
      ')',
    );
    return (rows.first['m'] as num?)?.toDouble() ?? 0;
  }

  Future<int> consistentCount() async {
    final table = _consistentTable;
    if (table == null) return 0;
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM "$table"');
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<List<ConsistentStock>> consistent({String? search, int? limit}) async {
    final table = _consistentTable;
    if (table == null) return const [];

    final args = <Object?>[];
    var where = '';
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      where = 'WHERE ticker LIKE ? OR name LIKE ?';
      args
        ..add('%$term%')
        ..add('%$term%');
    }
    final sql = StringBuffer(
      'SELECT * FROM "$table" $where ORDER BY pct_change_shortest_window DESC',
    );
    if (limit != null) sql.write(' LIMIT $limit');

    final rows = await _db.rawQuery(sql.toString(), args);
    return [
      for (final row in rows) ConsistentStock.fromMap(row, market: market),
    ];
  }

  /// Mean percentage change for a window, or null when the window is empty.
  ///
  /// The dashboard reports this alongside the median: the screener's long tail
  /// pulls the two a long way apart, and showing both makes that visible.
  Future<double?> averagePctChange(GrowthWindow window) async {
    final table = _tableFor(window);
    if (table == null) return null;
    final rows = await _db.rawQuery(
      'SELECT AVG(pct_change) AS a, COUNT(pct_change) AS n FROM "$table" '
      'WHERE pct_change IS NOT NULL',
    );
    final count = (rows.first['n'] as num?)?.toInt() ?? 0;
    if (count == 0) return null;
    return (rows.first['a'] as num?)?.toDouble();
  }

  /// Weekly bars for one ticker, oldest first.
  ///
  /// [from] and [to] bound the range inclusively; the dates are ISO strings in
  /// the file, so a lexicographic comparison is also a chronological one.
  Future<List<PriceBar>> priceHistory(
    String ticker, {
    DateTime? from,
    DateTime? to,
  }) async {
    final table = _seriesTable;
    if (table == null) return const [];

    final clauses = <String>['ticker = ?'];
    final args = <Object?>[ticker];
    if (from != null) {
      clauses.add('stock_price_date >= ?');
      args.add(_isoDate(from));
    }
    if (to != null) {
      clauses.add('stock_price_date <= ?');
      args.add(_isoDate(to));
    }

    final rows = await _db.rawQuery(
      'SELECT * FROM "$table" WHERE ${clauses.join(' AND ')} '
      'ORDER BY stock_price_date',
      args,
    );
    return [
      for (final row in rows)
        if (PriceBar.fromMap(row) case final bar?) bar,
    ];
  }

  /// A market-wide growth curve: a chain-linked index of median weekly return.
  ///
  /// Normalising every ticker against its own first bar looks simpler, but the
  /// constituents are not fixed — tickers enter the history at different dates
  /// — so that median lurches whenever the set changes, which shows up as
  /// spikes of tens of percent in a single week. Chaining the median
  /// *week-over-week* return instead only ever compares a ticker with itself,
  /// which is how an index handles changing membership.
  Future<List<GrowthPoint>> medianGrowthSeries({DateTime? from}) async {
    final table = _seriesTable;
    if (table == null) return const [];
    if (from == null && _growthCache != null) return _growthCache!;

    final args = <Object?>[];
    var where = '';
    if (from != null) {
      where = 'WHERE stock_price_date >= ?';
      args.add(_isoDate(from));
    }

    final rows = await _db.rawQuery(
      'SELECT ticker, stock_price_date AS d, CAST(close AS REAL) AS c '
      'FROM "$table" $where ORDER BY ticker, stock_price_date',
      args,
    );

    final byTicker = <String, Map<String, double>>{};
    final dates = <String>{};
    for (final row in rows) {
      final ticker = row['ticker'] as String?;
      final date = row['d'] as String?;
      final close = (row['c'] as num?)?.toDouble();
      if (ticker == null || date == null || close == null || close <= 0) {
        continue;
      }
      (byTicker[ticker] ??= <String, double>{})[date] = close;
      dates.add(date);
    }
    if (dates.isEmpty) return const [];

    final ordered = dates.toList()..sort();
    final points = <GrowthPoint>[
      GrowthPoint(date: DateTime.parse(ordered.first), pctChange: 0),
    ];

    var level = 1.0;
    for (var i = 1; i < ordered.length; i++) {
      final previous = ordered[i - 1];
      final current = ordered[i];

      // Only tickers with a price in both weeks contribute a return.
      final returns = <double>[];
      for (final series in byTicker.values) {
        final before = series[previous];
        final after = series[current];
        if (before == null || after == null || before <= 0) continue;
        returns.add(after / before - 1);
      }

      if (returns.isNotEmpty) {
        returns.sort();
        final middle = returns.length ~/ 2;
        final median = returns.length.isOdd
            ? returns[middle]
            : (returns[middle - 1] + returns[middle]) / 2;
        level *= 1 + median;
      }
      points.add(
        GrowthPoint(
          date: DateTime.parse(current),
          pctChange: (level - 1) * 100,
        ),
      );
    }

    if (from == null) _growthCache = points;
    return points;
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Raw percentage changes for a window, used to draw the distribution.
  Future<List<double>> pctChanges(GrowthWindow window) async {
    final table = _tableFor(window);
    if (table == null) return const [];
    final rows = await _db.rawQuery(
      'SELECT pct_change FROM "$table" WHERE pct_change IS NOT NULL ORDER BY pct_change',
    );
    return [
      for (final row in rows) (row['pct_change'] as num?)?.toDouble() ?? 0,
    ];
  }

  /// Where [value] sits within a window's distribution for [sort], as 0..1.
  ///
  /// Used to describe a single stock relative to its peers ("top 12% by
  /// volume") instead of against an arbitrary absolute threshold, which would
  /// be meaningless across markets as different as US stocks and ASX ETFs.
  Future<double?> percentileOf(
    GrowthWindow window,
    StockSort sort,
    double value,
  ) async {
    final table = _tableFor(window);
    if (table == null) return null;
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, '
      'SUM(CASE WHEN ${sort.column} <= ? THEN 1 ELSE 0 END) AS below '
      'FROM "$table" WHERE ${sort.column} IS NOT NULL',
      [value],
    );
    final total = (rows.first['n'] as num?)?.toInt() ?? 0;
    if (total == 0) return null;
    final below = (rows.first['below'] as num?)?.toDouble() ?? 0;
    return below / total;
  }

  /// Instrument counts per exchange for a window.
  Future<List<({String exchange, int count})>> exchangeBreakdown(
    GrowthWindow window,
  ) async {
    final table = _tableFor(window);
    if (table == null) return const [];
    final rows = await _db.rawQuery(
      'SELECT exchange, COUNT(*) AS n FROM "$table" GROUP BY exchange ORDER BY n DESC',
    );
    return [
      for (final row in rows)
        (
          exchange: row['exchange']?.toString() ?? 'Unknown',
          count: (row['n'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<void> close() => _db.close();
}
