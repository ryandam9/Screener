import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Column list of the published growth tables, in schema order.
///
/// `issuer` and `category` sit between `asset_type` and `first_date` in the
/// ASX file and are absent from the US one; [createFixtureDatabase] takes a
/// flag for which shape to write, because coping with both is exactly what
/// the discovery code has to do.
const _facetColumns = '"issuer" TEXT, "category" TEXT, ';

const _growthColumns =
    '"ticker" TEXT, "name" TEXT, "exchange" TEXT, "asset_type" TEXT, '
    '"first_date" TEXT, "first_price" FLOAT, "last_date" TEXT, '
    '"latest_price" FLOAT, "pct_change" FLOAT, "threshold" FLOAT, '
    '"observations" INTEGER, '
    '"days_covered" INTEGER, "coverage" FLOAT, "observation_ratio" FLOAT, '
    '"median_volume" FLOAT, "price_basis" TEXT, "data_as_of" TEXT, '
    '"run_id" TEXT, "google_finance" TEXT';

/// One bar of the whole-market history table.
class FixtureHistoryBar {
  const FixtureHistoryBar({
    required this.ticker,
    required this.date,
    required this.close,
    this.volume = 1000,
  });

  final String ticker;
  final String date;
  final double close;
  final double volume;
}

/// One row of test data, mirroring what the pipeline writes.
class FixtureRow {
  const FixtureRow({
    required this.ticker,
    required this.name,
    required this.exchange,
    required this.firstDate,
    required this.firstPrice,
    required this.lastDate,
    required this.latestPrice,
    required this.pctChange,
    this.threshold = 10.0,
    this.assetType = 'common_stock',
    this.issuer,
    this.category,
    this.observations = 6,
    this.daysCovered = 7,
    this.coverage = 1.0,
    this.observationRatio = 1.0,
    this.medianVolume = 1000000,
    this.priceBasis = 'adjusted',
    this.dataAsOf = '2026-08-21',
    this.runId = '20260822T224430Z-a4761276',
  });

  final String ticker;
  final String name;
  final String exchange;
  final String assetType;

  /// Published by the ASX file only. See [_facetColumns].
  final String? issuer;
  final String? category;

  final String firstDate;
  final double firstPrice;
  final String lastDate;
  final double latestPrice;
  final double pctChange;

  /// The cut-off the window's screen applied; every row of a table shares it.
  final double? threshold;

  final int observations;
  final int daysCovered;
  final double coverage;
  final double observationRatio;
  final double medianVolume;
  final String priceBasis;
  final String dataAsOf;
  final String runId;

  List<Object?> get values => [
    ticker,
    name,
    exchange,
    assetType,
    firstDate,
    firstPrice,
    lastDate,
    latestPrice,
    pctChange,
    threshold,
    observations,
    daysCovered,
    coverage,
    observationRatio,
    medianVolume,
    priceBasis,
    dataAsOf,
    runId,
    'https://www.google.com/finance/quote/$ticker:$exchange?window=5D',
  ];
}

/// One weekly bar, written as TEXT exactly as the pipeline does.
class FixtureBar {
  const FixtureBar({
    required this.date,
    required this.ticker,
    required this.close,
    this.open,
    this.high,
    this.low,
    double? adjClose,
    this.volume = 1000000,
    this.growthPeriods = '1Y,6M,3M,1M,5D',
  }) : adjClose = adjClose ?? close;

  final String date;
  final String ticker;
  final double close;
  final double? open;
  final double? high;
  final double? low;
  final double adjClose;
  final double volume;
  final String growthPeriods;
}

/// The `run_metadata` row, as the pipeline writes it.
class FixtureRun {
  const FixtureRun({
    this.runId = '20260822T224430Z-a4761276',
    this.codeRevision = '63ad976',
    this.exchange = 'NASDAQ',
    this.instrumentType = 'common_stock',
    this.dataAsOf = '2026-08-21',
    this.startedAt = '2026-08-22T22:44:30.987183+00:00',
    this.finishedAt = '2026-08-22T22:44:32.391127+00:00',
    this.status = 'success',
    this.universeTotal = 403,
    this.universeScreened = 402,
    this.provider = 'yahoo_finance',
    this.sourceRunId = '20260822T033603Z-628bdcfe',
    this.sourceStatus = 'success',
    this.settingsJson =
        '{"min_price": 2.0, "min_coverage": 0.8, '
        '"min_median_volume": 1000.0, "min_observation_ratio": 0.5, '
        '"max_data_age_days": 5, "endpoint_window": 3, '
        '"price_history_sampling": "weekly"}',
  });

  final String? runId;
  final String? codeRevision;
  final String? exchange;
  final String? instrumentType;
  final String? dataAsOf;
  final String? startedAt;
  final String? finishedAt;
  final String? status;
  final int? universeTotal;
  final int? universeScreened;
  final String? provider;
  final String? sourceRunId;
  final String? sourceStatus;
  final String? settingsJson;
}

/// One `screen_funnel` row. [window] is the table suffix without its leading
/// underscore, exactly as the pipeline writes it.
class FixtureStage {
  const FixtureStage({
    required this.window,
    required this.position,
    required this.stage,
    required this.count,
  });

  final String window;
  final int position;
  final String stage;
  final int count;
}

/// Writes a SQLite file shaped like the published databases.
///
/// [tablePrefix] varies in production (`us_stocks_growth`, `asx_etf_growth`),
/// which is exactly what the table-discovery code has to cope with.
Future<String> createFixtureDatabase({
  required Directory directory,
  required String fileName,
  required String tablePrefix,
  required Map<String, List<FixtureRow>> rowsBySuffix,
  bool includeConsistentTable = true,

  /// Writes the `issuer` and `category` columns the ASX file carries.
  bool includeFacetColumns = false,

  List<FixtureBar> weeklyBars = const [],
  FixtureRun? run,
  List<FixtureStage> funnel = const [],
  List<(String ticker, String name, String exchange, double pct)> consistent =
      const [],

  /// The whole-market history table the ASX file publishes.
  List<FixtureHistoryBar> history = const [],
  String historyTable = 'ASX_1_YEAR_HISTORY',

  /// The ticker directory, for files that publish one.
  Map<String, String> tickerNames = const {},
  String universeTable = 'asx_universe',
}) async {
  final path = '${directory.path}/$fileName';
  final file = File(path);
  if (await file.exists()) await file.delete();

  final db = await databaseFactoryFfi.openDatabase(path);
  for (final entry in rowsBySuffix.entries) {
    final table = '$tablePrefix${entry.key}';
    await db.execute(
      'CREATE TABLE "$table" '
      '(${includeFacetColumns ? _facetColumns : ''}$_growthColumns)',
    );
    for (final row in entry.value) {
      await db.insert(table, {
        'ticker': row.ticker,
        'name': row.name,
        'exchange': row.exchange,
        'asset_type': row.assetType,
        if (includeFacetColumns) 'issuer': row.issuer,
        if (includeFacetColumns) 'category': row.category,
        'first_date': row.firstDate,
        'first_price': row.firstPrice,
        'last_date': row.lastDate,
        'latest_price': row.latestPrice,
        'pct_change': row.pctChange,
        'threshold': row.threshold,
        'observations': row.observations,
        'days_covered': row.daysCovered,
        'coverage': row.coverage,
        'observation_ratio': row.observationRatio,
        'median_volume': row.medianVolume,
        'price_basis': row.priceBasis,
        'data_as_of': row.dataAsOf,
        'run_id': row.runId,
        'google_finance': row.values.last,
      });
    }
  }

  if (weeklyBars.isNotEmpty) {
    // Every column is TEXT in the published files, prices included.
    await db.execute(
      'CREATE TABLE "$tablePrefix" ('
      '  "stock_price_date" TEXT, "ticker" TEXT, "open" TEXT, "high" TEXT,'
      '  "low" TEXT, "close" TEXT, "adj_close" TEXT, "volume" TEXT,'
      '  "growth_count" TEXT, "growth_periods" TEXT)',
    );
    for (final bar in weeklyBars) {
      await db.insert(tablePrefix, {
        'stock_price_date': bar.date,
        'ticker': bar.ticker,
        'open': '${bar.open ?? bar.close}',
        'high': '${bar.high ?? bar.close}',
        'low': '${bar.low ?? bar.close}',
        'close': '${bar.close}',
        'adj_close': '${bar.adjClose}',
        'volume': '${bar.volume}',
        'growth_count': '${bar.growthPeriods.split(',').length}',
        'growth_periods': bar.growthPeriods,
      });
    }
  }

  if (run != null) {
    await db.execute(
      'CREATE TABLE run_metadata ('
      '  run_id TEXT, code_revision TEXT, exchange TEXT, instrument_type TEXT,'
      '  data_as_of TEXT, started_at TEXT, finished_at TEXT, status TEXT,'
      '  universe_total INTEGER, universe_screened INTEGER, provider TEXT,'
      '  source_run_id TEXT, source_status TEXT, settings_json TEXT)',
    );
    await db.insert('run_metadata', {
      'run_id': run.runId,
      'code_revision': run.codeRevision,
      'exchange': run.exchange,
      'instrument_type': run.instrumentType,
      'data_as_of': run.dataAsOf,
      'started_at': run.startedAt,
      'finished_at': run.finishedAt,
      'status': run.status,
      'universe_total': run.universeTotal,
      'universe_screened': run.universeScreened,
      'provider': run.provider,
      'source_run_id': run.sourceRunId,
      'source_status': run.sourceStatus,
      'settings_json': run.settingsJson,
    });
  }

  if (funnel.isNotEmpty) {
    await db.execute(
      'CREATE TABLE screen_funnel ('
      '  "window" TEXT, position INTEGER, stage TEXT, count INTEGER)',
    );
    for (final stage in funnel) {
      await db.insert('screen_funnel', {
        'window': stage.window,
        'position': stage.position,
        'stage': stage.stage,
        'count': stage.count,
      });
    }
  }

  if (history.isNotEmpty) {
    // Named as the published table is, and with the same TEXT columns: the
    // pipeline writes every number as text.
    await db.execute(
      'CREATE TABLE "$historyTable" ('
      '  ticker TEXT, stock_price_date TEXT, open TEXT, high TEXT,'
      '  low TEXT, close TEXT, adj_close TEXT, volume TEXT)',
    );
    for (final bar in history) {
      await db.insert(historyTable, {
        'ticker': bar.ticker,
        'stock_price_date': bar.date,
        'open': '${bar.close}',
        'high': '${bar.close}',
        'low': '${bar.close}',
        'close': '${bar.close}',
        'adj_close': '${bar.close}',
        'volume': '${bar.volume}',
      });
    }
  }

  if (tickerNames.isNotEmpty) {
    // Named and shaped as the published one: ticker, name, and nothing
    // priced. See the query the pipeline documents:
    //   SELECT u.name, h.close FROM ASX_1_YEAR_HISTORY h
    //   JOIN asx_universe u USING (ticker)
    await db.execute(
      'CREATE TABLE "$universeTable" ('
      '  ticker TEXT, name TEXT, exchange TEXT, asset_type TEXT'
      '${includeFacetColumns ? ', issuer TEXT, category TEXT' : ''})',
    );
    for (final entry in tickerNames.entries) {
      await db.insert(universeTable, {
        'ticker': entry.key,
        'name': entry.value,
        'exchange': 'ASX',
        'asset_type': 'etf',
      });
    }
  }

  if (includeConsistentTable) {
    await db.execute(
      'CREATE TABLE consistent_growth_stocks('
      '  ticker TEXT, name TEXT, exchange TEXT,'
      '${includeFacetColumns ? '  issuer TEXT, category TEXT,' : ''}'
      '  pct_change_shortest_window REAL, threshold_shortest_window REAL,'
      '  data_as_of TEXT, run_id TEXT)',
    );
    for (final entry in consistent) {
      await db.insert('consistent_growth_stocks', {
        'ticker': entry.$1,
        'name': entry.$2,
        'exchange': entry.$3,
        'pct_change_shortest_window': entry.$4,
        'threshold_shortest_window': 10.0,
        'data_as_of': '2026-08-21',
        'run_id': '20260822T224430Z-a4761276',
      });
    }
  }

  await db.close();
  return path;
}
