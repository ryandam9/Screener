import 'package:sqflite/sqflite.dart';

import '../models/growth_window.dart';
import '../models/market.dart';
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
  }) : _db = database,
       _tables = tables,
       _consistentTable = consistentTable;

  final Market market;
  final String path;
  final Database _db;
  final Map<GrowthWindow, String> _tables;
  final String? _consistentTable;

  /// Windows this file actually contains, shortest first.
  List<GrowthWindow> get availableWindows {
    final windows = _tables.keys.toList()
      ..sort((a, b) => a.approximateDays.compareTo(b.approximateDays));
    return windows;
  }

  bool get hasConsistentTable => _consistentTable != null;

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
    for (final row in rows) {
      final name = row['name'] as String?;
      if (name == null) continue;
      final window = GrowthWindow.fromTableName(name);
      if (window != null) {
        tables[window] = name;
      } else if (name.toLowerCase().contains('consistent')) {
        consistent = name;
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
