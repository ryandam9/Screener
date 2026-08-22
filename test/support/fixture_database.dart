import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Column list of the published growth tables, in schema order.
const _growthColumns =
    '"ticker" TEXT, "name" TEXT, "exchange" TEXT, "asset_type" TEXT, '
    '"first_date" TEXT, "first_price" FLOAT, "last_date" TEXT, '
    '"latest_price" FLOAT, "pct_change" FLOAT, "observations" INTEGER, '
    '"days_covered" INTEGER, "coverage" FLOAT, "observation_ratio" FLOAT, '
    '"median_volume" FLOAT, "price_basis" TEXT, "data_as_of" TEXT, '
    '"run_id" TEXT, "google_finance" TEXT';

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
    this.assetType = 'common_stock',
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
  final String firstDate;
  final double firstPrice;
  final String lastDate;
  final double latestPrice;
  final double pctChange;
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
  List<(String ticker, String name, String exchange, double pct)> consistent =
      const [],
}) async {
  final path = '${directory.path}/$fileName';
  final file = File(path);
  if (await file.exists()) await file.delete();

  final db = await databaseFactoryFfi.openDatabase(path);
  for (final entry in rowsBySuffix.entries) {
    final table = '$tablePrefix${entry.key}';
    await db.execute('CREATE TABLE "$table" ($_growthColumns)');
    for (final row in entry.value) {
      await db.insert(table, {
        'ticker': row.ticker,
        'name': row.name,
        'exchange': row.exchange,
        'asset_type': row.assetType,
        'first_date': row.firstDate,
        'first_price': row.firstPrice,
        'last_date': row.lastDate,
        'latest_price': row.latestPrice,
        'pct_change': row.pctChange,
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

  if (includeConsistentTable) {
    await db.execute(
      'CREATE TABLE consistent_growth_stocks('
      '  ticker TEXT, name TEXT, exchange TEXT,'
      '  pct_change_shortest_window REAL, data_as_of TEXT, run_id TEXT)',
    );
    for (final entry in consistent) {
      await db.insert('consistent_growth_stocks', {
        'ticker': entry.$1,
        'name': entry.$2,
        'exchange': entry.$3,
        'pct_change_shortest_window': entry.$4,
        'data_as_of': '2026-08-21',
        'run_id': '20260822T224430Z-a4761276',
      });
    }
  }

  await db.close();
  return path;
}
