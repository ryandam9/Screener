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
            threshold: 25,
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

  /// The ASX file as it is published now: ETFs labelled with the issuer that
  /// runs them and the category they hold, and one row the pipeline left
  /// uncategorised.
  Future<MarketDatabase> openAsxFixture() async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'asx_facets.db',
      tablePrefix: 'asx_etf_growth',
      includeConsistentTable: false,
      includeFacetColumns: true,
      rowsBySuffix: {
        '_7_days': const [
          FixtureRow(
            ticker: 'QETH',
            name: 'Betashares Ethereum ETF',
            exchange: 'ASX',
            assetType: 'etf',
            issuer: 'Betashares',
            category: 'crypto',
            firstDate: '2026-08-14',
            firstPrice: 18.53,
            lastDate: '2026-08-21',
            latestPrice: 22.42,
            pctChange: 20.99,
          ),
          FixtureRow(
            ticker: 'GDX',
            name: 'VanEck Gold Miners ETF',
            exchange: 'ASX',
            assetType: 'etf',
            issuer: 'VanEck',
            category: 'precious metals',
            firstDate: '2026-08-14',
            firstPrice: 80.10,
            lastDate: '2026-08-21',
            latestPrice: 94.52,
            pctChange: 18.00,
          ),
          FixtureRow(
            ticker: 'ATOM',
            name: 'Global X Copper Miners ETF',
            exchange: 'ASX',
            assetType: 'etf',
            issuer: 'Global X',
            category: 'industrial metals',
            firstDate: '2026-08-14',
            firstPrice: 10.00,
            lastDate: '2026-08-21',
            latestPrice: 11.50,
            pctChange: 15.00,
          ),
          FixtureRow(
            ticker: 'VAS',
            name: 'Vanguard Australian Shares Index ETF',
            exchange: 'ASX',
            assetType: 'etf',
            issuer: 'Vanguard',
            firstDate: '2026-08-14',
            firstPrice: 100.00,
            lastDate: '2026-08-21',
            latestPrice: 111.00,
            pctChange: 11.00,
          ),
        ],
      },
    );
    return MarketDatabase.open(Market.asx, path);
  }

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

  test('lists the categories and issuers a file publishes', () async {
    final asx = await openAsxFixture();
    addTearDown(asx.close);

    expect(asx.hasCategories, isTrue);
    expect(asx.hasIssuers, isTrue);
    // Alphabetical, and the uncategorised row contributes nothing.
    expect(await asx.categories(GrowthWindow.sevenDays), [
      'crypto',
      'industrial metals',
      'precious metals',
    ]);
    expect(await asx.issuers(GrowthWindow.sevenDays), [
      'Betashares',
      'Global X',
      'VanEck',
      'Vanguard',
    ]);
  });

  test('filters by one category and by a union of them', () async {
    final asx = await openAsxFixture();
    addTearDown(asx.close);

    final crypto = await asx.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(categories: {'crypto'}),
    );
    expect([for (final r in crypto) r.ticker], ['QETH']);

    // "metals or crypto": the reason the filter takes a set at all.
    final metalsOrCrypto = await asx.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(
        categories: {'crypto', 'precious metals', 'industrial metals'},
      ),
    );
    expect([for (final r in metalsOrCrypto) r.ticker], ['QETH', 'GDX', 'ATOM']);
    expect(
      await asx.count(
        GrowthWindow.sevenDays,
        const StockQuery(
          categories: {'crypto', 'precious metals', 'industrial metals'},
        ),
      ),
      3,
    );
  });

  test('combines an issuer filter with a category one', () async {
    final asx = await openAsxFixture();
    addTearDown(asx.close);

    final both = await asx.stocks(
      GrowthWindow.sevenDays,
      const StockQuery(
        categories: {'precious metals', 'industrial metals'},
        issuers: {'VanEck'},
      ),
    );
    expect([for (final r in both) r.ticker], ['GDX']);
    expect(both.single.issuer, 'VanEck');
    expect(both.single.category, 'precious metals');
  });

  test(
    'a file without the columns offers no facets and ignores them',
    () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      expect(us.hasCategories, isFalse);
      expect(us.hasIssuers, isFalse);
      expect(await us.categories(GrowthWindow.sevenDays), isEmpty);
      expect(await us.issuers(GrowthWindow.sevenDays), isEmpty);

      // A filter carried over from the ASX list must not take the US query down
      // with a "no such column" error.
      final rows = await us.stocks(
        GrowthWindow.sevenDays,
        const StockQuery(categories: {'crypto'}, issuers: {'Betashares'}),
      );
      expect([for (final r in rows) r.ticker], ['MRNA', 'AMLX', 'SCTX']);
      expect(rows.first.category, isNull);
      expect(rows.first.issuer, isNull);
    },
  );

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

  group('the screen cut-off', () {
    test('is read per window and cached', () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      // The published files raise the cut-off for the longer windows, which is
      // why a single app-wide constant would be wrong.
      expect(await us.threshold(GrowthWindow.sevenDays), 10);
      expect(await us.threshold(GrowthWindow.oneYear), 25);

      // Cached: the second read answers from memory, so a closed database
      // still returns the value.
      final again = us.threshold(GrowthWindow.sevenDays);
      expect(await again, 10);
    });

    test('rides along on every row', () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      final rows = await us.stocks(GrowthWindow.sevenDays);
      expect(rows.first.threshold, 10);
      expect(rows.first.marginOverThreshold, closeTo(107.91, 0.001));

      final year = await us.stocks(GrowthWindow.oneYear);
      expect(year.first.threshold, 25);
    });

    test('is null for a window the file lacks', () async {
      final us = await openUsFixture();
      addTearDown(us.close);

      expect(await us.threshold(GrowthWindow.threeMonths), isNull);
    });

    test('is null when the file predates the column', () async {
      // Written by hand rather than through the fixture builder, which always
      // includes the column now.
      final path = '${tempDir.path}/legacy.db';
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute(
        'CREATE TABLE "us_stocks_growth_7_days" ('
        '  ticker TEXT, name TEXT, exchange TEXT, pct_change FLOAT)',
      );
      await db.insert('us_stocks_growth_7_days', {
        'ticker': 'MRNA',
        'name': 'Moderna, Inc.',
        'exchange': 'NASDAQ',
        'pct_change': 117.91,
      });
      await db.close();

      final legacy = await MarketDatabase.open(Market.us, path);
      addTearDown(legacy.close);

      expect(await legacy.threshold(GrowthWindow.sevenDays), isNull);
      final rows = await legacy.stocks(GrowthWindow.sevenDays);
      expect(rows.single.threshold, isNull);
      expect(rows.single.marginOverThreshold, isNull);
    });

    test('a table with more than one cut-off reports none', () async {
      final path = await createFixtureDatabase(
        directory: tempDir,
        fileName: 'mixed.db',
        tablePrefix: 'us_stocks_growth',
        includeConsistentTable: false,
        rowsBySuffix: const {
          '_7_days': [
            FixtureRow(
              ticker: 'AAA',
              name: 'Alpha',
              exchange: 'NASDAQ',
              firstDate: '2026-08-14',
              firstPrice: 10,
              lastDate: '2026-08-21',
              latestPrice: 12,
              pctChange: 20,
              threshold: 10,
            ),
            FixtureRow(
              ticker: 'BBB',
              name: 'Beta',
              exchange: 'NASDAQ',
              firstDate: '2026-08-14',
              firstPrice: 10,
              lastDate: '2026-08-21',
              latestPrice: 13,
              pctChange: 30,
              threshold: 25,
            ),
          ],
        },
      );
      final mixed = await MarketDatabase.open(Market.us, path);
      addTearDown(mixed.close);

      // One number would misdescribe half the rows, so the list caption says
      // nothing instead. The rows still carry their own — strongest first,
      // which is the default sort.
      expect(await mixed.threshold(GrowthWindow.sevenDays), isNull);
      final rows = await mixed.stocks(GrowthWindow.sevenDays);
      expect([for (final row in rows) row.threshold], [25, 10]);
    });
  });

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
