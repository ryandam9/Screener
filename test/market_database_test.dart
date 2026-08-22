import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixture_database.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_db_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<MarketDatabase> openUsFixture() async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'us.db',
      tablePrefix: 'us_stocks_growth',
      consistent: const [
        ('MRNA', 'Moderna, Inc. - Common Stock', 'NASDAQ', 117.91),
        ('ABCL', 'AbCellera Biologics Inc.', 'NASDAQ', 101.92),
      ],
      rowsBySuffix: {
        '_7_days': const [
          FixtureRow(
            ticker: 'MRNA',
            name: 'Moderna, Inc. - Common Stock',
            exchange: 'NASDAQ',
            firstDate: '2026-08-14',
            firstPrice: 63.89,
            lastDate: '2026-08-21',
            latestPrice: 139.225,
            pctChange: 117.91,
            medianVolume: 45924100,
          ),
          FixtureRow(
            ticker: 'AMLX',
            name: 'Amylyx Pharmaceuticals, Inc. - Common Stock',
            exchange: 'NASDAQ',
            firstDate: '2026-08-14',
            firstPrice: 21.53,
            lastDate: '2026-08-21',
            latestPrice: 39.16,
            pctChange: 81.89,
            medianVolume: 6451750,
          ),
          FixtureRow(
            ticker: 'SCTX',
            name: 'Scribe Therapeutics Inc. - Common Stock',
            exchange: 'NYSE',
            firstDate: '2026-08-14',
            firstPrice: 20.96,
            lastDate: '2026-08-21',
            latestPrice: 33.48,
            pctChange: 59.73,
            medianVolume: 295950,
          ),
        ],
        '_1_year': const [
          FixtureRow(
            ticker: 'MRNA',
            name: 'Moderna, Inc. - Common Stock',
            exchange: 'NASDAQ',
            firstDate: '2025-08-22',
            firstPrice: 25.35,
            lastDate: '2026-08-21',
            latestPrice: 145.13,
            pctChange: 472.5,
            observations: 251,
            daysCovered: 364,
            coverage: 0.997,
            observationRatio: 0.958,
            medianVolume: 8359900,
          ),
        ],
      },
    );
    return MarketDatabase.open(Market.us, path);
  }

  test('discovers per-window tables regardless of prefix', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    expect(us.availableWindows, [
      GrowthWindow.sevenDays,
      GrowthWindow.oneYear,
    ], reason: 'windows should be ordered shortest first');
    expect(us.hasConsistentTable, isTrue);

    final asxPath = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'asx.db',
      tablePrefix: 'asx_etf_growth',
      includeConsistentTable: false,
      rowsBySuffix: {
        '_7_days': const [
          FixtureRow(
            ticker: 'QETH',
            name: 'Betashares Ethereum ETF',
            exchange: 'ASX',
            assetType: 'etf',
            firstDate: '2026-08-14',
            firstPrice: 18.53,
            lastDate: '2026-08-21',
            latestPrice: 22.42,
            pctChange: 20.99,
            medianVolume: 7518,
          ),
        ],
      },
    );
    final asx = await MarketDatabase.open(Market.asx, asxPath);
    addTearDown(asx.close);

    expect(asx.availableWindows, [GrowthWindow.sevenDays]);
    expect(asx.hasConsistentTable, isFalse);
  });

  test('rejects a database with no growth tables', () async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'empty.db',
      tablePrefix: 'unrelated',
      includeConsistentTable: false,
      rowsBySuffix: const {'_table': []},
    );
    await expectLater(
      MarketDatabase.open(Market.us, path),
      throwsA(isA<StateError>()),
    );
  });

  test('sorts and filters rows', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final byChange = await us.stocks(GrowthWindow.sevenDays);
    expect([for (final r in byChange) r.ticker], ['MRNA', 'AMLX', 'SCTX']);

    final ascending = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(sort: StockSort.ticker, descending: false),
    );
    expect([for (final r in ascending) r.ticker], ['AMLX', 'MRNA', 'SCTX']);

    final nasdaqOnly = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(exchange: 'NASDAQ'),
    );
    expect([for (final r in nasdaqOnly) r.ticker], ['MRNA', 'AMLX']);

    final strong = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(minPctChange: 80),
    );
    expect([for (final r in strong) r.ticker], ['MRNA', 'AMLX']);
  });

  test('search matches ticker and company name', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final byTicker = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(search: 'mrna'),
    );
    expect([for (final r in byTicker) r.ticker], ['MRNA']);

    final byName = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(search: 'Therapeutics'),
    );
    expect([for (final r in byName) r.ticker], ['SCTX']);
  });

  test(
    'an empty ticker filter returns nothing rather than everything',
    () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      final rows = await us.stocks(
        GrowthWindow.sevenDays,
        const StockQuery(tickers: []),
      );
      expect(rows, isEmpty);
      expect(
        await us.count(GrowthWindow.sevenDays, const StockQuery(tickers: [])),
        0,
      );
    },
  );

  test('watchlist filter selects only the named tickers', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final rows = await us.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(tickers: ['SCTX', 'MRNA']),
    );
    expect([for (final r in rows) r.ticker], ['MRNA', 'SCTX']);
  });

  test('reads every window for one ticker, shortest first', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final rows = await us.ticker('MRNA');
    expect(
      [for (final r in rows) r.window],
      [GrowthWindow.sevenDays, GrowthWindow.oneYear],
    );
    expect(rows.first.firstPrice, 63.89);
    expect(rows.last.pctChange, 472.5);
    expect(await us.ticker('NOPE'), isEmpty);
  });

  test('summary reports counts, median and the top gainer', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final summary = await us.summary();
    final sevenDay = summary.statFor(GrowthWindow.sevenDays)!;

    expect(sevenDay.count, 3);
    // Odd row count: the median is the middle value, not the mean.
    expect(sevenDay.medianPctChange, closeTo(81.89, 0.001));
    expect(sevenDay.maxPctChange, closeTo(117.91, 0.001));
    expect(sevenDay.minPctChange, closeTo(59.73, 0.001));
    expect(summary.topGainer?.ticker, 'MRNA');
    expect(summary.consistentCount, 2);
    expect(summary.dataAsOf, '2026-08-21');
  });

  test('median averages the middle pair when the count is even', () async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'even.db',
      tablePrefix: 'us_stocks_growth',
      includeConsistentTable: false,
      rowsBySuffix: {
        '_7_days': [
          for (final pct in const [10.0, 20.0, 30.0, 40.0])
            FixtureRow(
              ticker: 'T$pct',
              name: 'Test $pct',
              exchange: 'NASDAQ',
              firstDate: '2026-08-14',
              firstPrice: 10,
              lastDate: '2026-08-21',
              latestPrice: 10 + pct,
              pctChange: pct,
            ),
        ],
      },
    );
    final db = await MarketDatabase.open(Market.us, path);
    addTearDown(db.close);

    final stat = (await db.summary()).statFor(GrowthWindow.sevenDays)!;
    expect(stat.medianPctChange, closeTo(25.0, 0.001));
  });

  test('percentile ranks a value within its window', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    // MRNA has the largest median volume of the three rows.
    final top = await us.percentileOf(
      GrowthWindow.sevenDays,
      StockSort.medianVolume,
      45924100,
    );
    expect(top, closeTo(1.0, 0.001));

    final bottom = await us.percentileOf(
      GrowthWindow.sevenDays,
      StockSort.medianVolume,
      295950,
    );
    expect(bottom, closeTo(1 / 3, 0.001));
  });

  test('exchange breakdown and distinct exchanges', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    expect(await us.exchanges(GrowthWindow.sevenDays), ['NASDAQ', 'NYSE']);

    final breakdown = await us.exchangeBreakdown(GrowthWindow.sevenDays);
    expect(breakdown.first.exchange, 'NASDAQ');
    expect(breakdown.first.count, 2);
  });

  test('run info exposes provenance and parses the run timestamp', () async {
    final us = await openUsFixture();
    addTearDown(us.close);

    final info = await us.runInfo(GrowthWindow.sevenDays);
    expect(info!.rowCount, 3);
    expect(info.dataAsOf, '2026-08-21');
    expect(info.runStartedAt?.toUtc(), DateTime.utc(2026, 8, 22, 22, 44, 30));
  });

  test(
    'consistent growers are sorted by their shortest-window change',
    () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      final rows = await us.consistent();
      expect([for (final r in rows) r.ticker], ['MRNA', 'ABCL']);
      expect(await us.consistent(search: 'abc'), hasLength(1));
    },
  );

  test(
    'queries on a window the file lacks return empty, not an error',
    () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      expect(await us.stocks(GrowthWindow.threeMonths), isEmpty);
      expect(await us.count(GrowthWindow.threeMonths), 0);
      expect(await us.pctChanges(GrowthWindow.threeMonths), isEmpty);
      expect(await us.runInfo(GrowthWindow.threeMonths), isNull);
    },
  );
}
