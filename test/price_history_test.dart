import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/price_bar.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixture_database.dart';

/// The weekly price history published alongside the per-window tables.
void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_history_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Four Fridays for two tickers, priced so the medians are easy to state.
  const bars = [
    FixtureBar(date: '2026-08-07', ticker: 'AAA', close: 100),
    FixtureBar(date: '2026-08-14', ticker: 'AAA', close: 110),
    FixtureBar(date: '2026-08-21', ticker: 'AAA', close: 120),
    FixtureBar(date: '2026-08-07', ticker: 'BBB', close: 50),
    FixtureBar(date: '2026-08-14', ticker: 'BBB', close: 55),
    FixtureBar(date: '2026-08-21', ticker: 'BBB', close: 40),
  ];

  Future<MarketDatabase> open({List<FixtureBar> series = bars}) async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'us.db',
      tablePrefix: 'us_stocks_growth',
      includeConsistentTable: false,
      weeklyBars: series,
      rowsBySuffix: const {
        '_7_days': [
          FixtureRow(
            ticker: 'AAA',
            name: 'Alpha',
            exchange: 'NASDAQ',
            firstDate: '2026-08-14',
            firstPrice: 110,
            lastDate: '2026-08-21',
            latestPrice: 120,
            pctChange: 9.09,
          ),
        ],
      },
    );
    return MarketDatabase.open(Market.us, path);
  }

  test('discovers the history table by its columns', () async {
    final db = await open();
    addTearDown(db.close);
    expect(db.hasPriceHistory, isTrue);
  });

  test('a file without history still opens and reports none', () async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'old.db',
      tablePrefix: 'us_stocks_growth',
      includeConsistentTable: false,
      rowsBySuffix: const {
        '_7_days': [
          FixtureRow(
            ticker: 'AAA',
            name: 'Alpha',
            exchange: 'NASDAQ',
            firstDate: '2026-08-14',
            firstPrice: 110,
            lastDate: '2026-08-21',
            latestPrice: 120,
            pctChange: 9.09,
          ),
        ],
      },
    );
    final db = await MarketDatabase.open(Market.us, path);
    addTearDown(db.close);

    expect(db.hasPriceHistory, isFalse);
    expect(await db.priceHistory('AAA'), isEmpty);
    expect(await db.medianGrowthSeries(), isEmpty);
  });

  test(
    'returns a ticker\'s bars oldest first, parsing the TEXT numerics',
    () async {
      final db = await open();
      addTearDown(db.close);

      final history = await db.priceHistory('AAA');
      expect(history, hasLength(3));
      expect(
        [for (final b in history) b.date],
        [
          DateTime.parse('2026-08-07'),
          DateTime.parse('2026-08-14'),
          DateTime.parse('2026-08-21'),
        ],
      );
      expect(history.first.close, 100.0);
      expect(history.first.volume, 1000000.0);
      expect(history.first.growthPeriods, contains('1Y'));
    },
  );

  test('bounds the range inclusively', () async {
    final db = await open();
    addTearDown(db.close);

    final history = await db.priceHistory(
      'AAA',
      from: DateTime(2026, 8, 14),
      to: DateTime(2026, 8, 21),
    );
    expect([for (final b in history) b.close], [110.0, 120.0]);
  });

  test('an unknown ticker yields nothing', () async {
    final db = await open();
    addTearDown(db.close);
    expect(await db.priceHistory('NOPE'), isEmpty);
  });

  test('plotPrice prefers the adjusted close', () {
    final adjusted = PriceBar.fromMap(const {
      'stock_price_date': '2026-08-21',
      'ticker': 'AAA',
      'close': '120',
      'adj_close': '118.5',
    })!;
    expect(adjusted.plotPrice, 118.5);

    final unadjusted = PriceBar.fromMap(const {
      'stock_price_date': '2026-08-21',
      'ticker': 'AAA',
      'close': '120',
      'adj_close': '',
    })!;
    expect(unadjusted.plotPrice, 120.0);
  });

  test('a row with no usable date or price is dropped', () {
    expect(
      PriceBar.fromMap(const {'stock_price_date': 'nope', 'close': '10'}),
      isNull,
    );
    expect(
      PriceBar.fromMap(const {
        'stock_price_date': '2026-08-21',
        'close': '0',
        'adj_close': '0',
      }),
      isNull,
      reason: 'a zero price would draw as a spike to the axis',
    );
  });

  test('the growth curve chains median weekly returns', () async {
    final db = await open();
    addTearDown(db.close);

    final series = await db.medianGrowthSeries();
    expect(series, hasLength(3));

    // The index starts at zero.
    expect(series[0].pctChange, closeTo(0, 0.001));
    // Both tickers returned +10% that week, so the index is +10%.
    expect(series[1].pctChange, closeTo(10, 0.001));
    // Then AAA +9.09% and BBB -27.27%; the median of two is their mean,
    // -9.09%, and 1.10 x 0.9091 lands back at par.
    expect(series[2].pctChange, closeTo(0, 0.001));
  });

  test('the growth curve weighs tickers equally, not by price', () async {
    // BBB is priced far below AAA but doubles; a raw-price average would be
    // dominated by AAA, a normalised median is not.
    final db = await open(
      series: const [
        FixtureBar(date: '2026-08-07', ticker: 'AAA', close: 1000),
        FixtureBar(date: '2026-08-14', ticker: 'AAA', close: 1000),
        FixtureBar(date: '2026-08-07', ticker: 'BBB', close: 1),
        FixtureBar(date: '2026-08-14', ticker: 'BBB', close: 2),
      ],
    );
    addTearDown(db.close);

    final series = await db.medianGrowthSeries();
    // AAA 0%, BBB +100% -> median of two returns is 50%.
    expect(series.last.pctChange, closeTo(50, 0.001));
  });

  test('a ticker joining late does not jolt the curve', () async {
    // CCC appears in week two. Under a baseline-normalised median its arrival
    // at 0% would drag the whole curve; chaining ignores it until it has two
    // prices of its own.
    final db = await open(
      series: const [
        FixtureBar(date: '2026-08-07', ticker: 'AAA', close: 100),
        FixtureBar(date: '2026-08-14', ticker: 'AAA', close: 110),
        FixtureBar(date: '2026-08-21', ticker: 'AAA', close: 121),
        FixtureBar(date: '2026-08-14', ticker: 'CCC', close: 500),
        FixtureBar(date: '2026-08-21', ticker: 'CCC', close: 550),
      ],
    );
    addTearDown(db.close);

    final series = await db.medianGrowthSeries();
    expect(series[1].pctChange, closeTo(10, 0.001));
    // Both return +10% in the final week, so the index compounds to +21%.
    expect(series[2].pctChange, closeTo(21, 0.001));
  });

  test('the growth curve can start from a date', () async {
    final db = await open();
    addTearDown(db.close);

    final series = await db.medianGrowthSeries(from: DateTime(2026, 8, 14));
    expect(series, hasLength(2));
    // The index restarts at zero for the range asked for.
    expect(series.first.pctChange, closeTo(0, 0.001));
    // AAA +9.09%, BBB -27.27% -> median -9.09%.
    expect(series.last.pctChange, closeTo(-9.0909, 0.001));
  });
}
