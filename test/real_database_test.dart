@Tags(['real-data'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/daily_digest.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/price_series.dart';
import 'package:screener/models/stock_row.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the data layer against the databases actually published to S3.
///
/// Fixtures prove the code handles the schema as documented; this proves the
/// documentation matches production. Point `SCREENER_DB_DIR` at a directory
/// holding `us.db` and `asx.db`:
///
/// ```
/// mkdir -p .cache && cd .cache
/// curl -O https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/us.db
/// curl -O https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/asx.db
/// cd .. && SCREENER_DB_DIR=.cache flutter test test/real_database_test.dart
/// ```
///
/// The whole group is skipped when the directory is missing, so CI without
/// network access still passes.
void main() {
  final directory = Platform.environment['SCREENER_DB_DIR'];
  final available =
      directory != null &&
      File('$directory/us.db').existsSync() &&
      File('$directory/asx.db').existsSync();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group(
    'published databases',
    () {
      test('us.db exposes all five windows and reads rows', () async {
        final db = await MarketDatabase.open(Market.us, '$directory/us.db');
        addTearDown(db.close);

        expect(db.availableWindows, GrowthWindow.values);
        expect(db.hasConsistentTable, isTrue);

        final rows = await db.stocks(
          GrowthWindow.sevenDays,
          const StockQuery(limit: 5),
        );
        expect(rows, isNotEmpty);
        expect(rows.first.pctChange, greaterThan(0));
        expect(rows.first.exchange, isNotEmpty);
        expect(rows.first.dataAsOf, isNotNull);
        for (var i = 1; i < rows.length; i++) {
          expect(
            rows[i].pctChange,
            lessThanOrEqualTo(rows[i - 1].pctChange),
            reason: 'default sort must be strongest first',
          );
        }
      });

      test('asx.db uses a different table prefix and still resolves', () async {
        final db = await MarketDatabase.open(Market.asx, '$directory/asx.db');
        addTearDown(db.close);

        expect(db.availableWindows, isNotEmpty);
        final rows = await db.stocks(GrowthWindow.sevenDays);
        expect(rows, isNotEmpty);
        expect(rows.first.assetType, 'etf');
        expect(rows.first.exchange, 'ASX');
      });

      test('summaries compute for every window in both files', () async {
        for (final market in Market.values) {
          final db = await MarketDatabase.open(
            market,
            '$directory/${market.objectKey}',
          );
          addTearDown(db.close);

          final summary = await db.summary();
          expect(summary.stats, hasLength(db.availableWindows.length));
          for (final stat in summary.stats) {
            expect(stat.count, greaterThanOrEqualTo(0));
            if (stat.count > 0) {
              expect(
                stat.maxPctChange,
                greaterThanOrEqualTo(stat.minPctChange),
              );
              expect(
                stat.medianPctChange,
                greaterThanOrEqualTo(stat.minPctChange),
              );
              expect(
                stat.medianPctChange,
                lessThanOrEqualTo(stat.maxPctChange),
              );
            }
          }
        }
      });

      test('a real ticker builds a multi-point price series', () async {
        final db = await MarketDatabase.open(Market.us, '$directory/us.db');
        addTearDown(db.close);

        final top = await db.stocks(
          GrowthWindow.sevenDays,
          const StockQuery(limit: 1),
        );
        final rows = await db.ticker(top.single.ticker);
        expect(rows, isNotEmpty);

        final series = PriceSeries.build(rows, rows.last.window);
        expect(series.points.length, greaterThanOrEqualTo(2));
        expect(series.minPrice, greaterThan(0));
        for (var i = 1; i < series.points.length; i++) {
          expect(
            series.points[i].date.isAfter(series.points[i - 1].date),
            isTrue,
          );
        }
      });

      test('both files publish a year of weekly bars', () async {
        for (final market in Market.values) {
          final db = await MarketDatabase.open(
            market,
            '$directory/${market.objectKey}',
          );
          addTearDown(db.close);

          expect(db.hasPriceHistory, isTrue, reason: market.objectKey);

          final top = await db.stocks(
            GrowthWindow.sevenDays,
            const StockQuery(limit: 1),
          );
          final bars = await db.priceHistory(top.single.ticker);
          expect(bars, isNotEmpty);
          expect(bars.length, lessThanOrEqualTo(53));

          for (var i = 1; i < bars.length; i++) {
            expect(bars[i].date.isAfter(bars[i - 1].date), isTrue);
            final gap = bars[i].date.difference(bars[i - 1].date).inDays;
            expect(gap, lessThanOrEqualTo(10), reason: 'weekly cadence');
          }
          for (final bar in bars) {
            expect(bar.plotPrice, greaterThan(0));
          }
        }
      });

      test('the market growth curve spans the published year', () async {
        final db = await MarketDatabase.open(Market.us, '$directory/us.db');
        addTearDown(db.close);

        final series = await db.medianGrowthSeries();
        expect(series.length, greaterThan(40));
        expect(series.first.pctChange, closeTo(0, 0.001));
        for (var i = 1; i < series.length; i++) {
          expect(series[i].date.isAfter(series[i - 1].date), isTrue);
        }
      });

      test('the morning digest reads as a sentence about real rows', () async {
        final rows = <StockRow>[];
        for (final market in Market.values) {
          final db = await MarketDatabase.open(
            market,
            '$directory/${market.objectKey}',
          );
          addTearDown(db.close);
          rows.addAll(await db.stocks(GrowthWindow.sevenDays));
        }

        final digest = DailyDigest.build(
          rows: rows,
          previousKeys: const {},
          date: DateTime.now(),
        );

        // Printed as well as asserted: the wording is the product here, and
        // this is the one test that sees the real names.
        // ignore: avoid_print
        print('${digest.title}\n${digest.body}');

        expect(digest.isEmpty, isFalse);
        expect(digest.title, contains('7-day screen'));
        // The strongest row, not the first one read: the digest sorts.
        expect(digest.body, contains(digest.rows.first.ticker));
        expect(digest.body, matches(RegExp(r'\+\d+\.\d%')));
      });

      test('run metadata parses into a real timestamp', () async {
        final db = await MarketDatabase.open(Market.us, '$directory/us.db');
        addTearDown(db.close);

        final info = await db.runInfo(GrowthWindow.sevenDays);
        expect(info!.rowCount, greaterThan(0));
        expect(
          info.runStartedAt,
          isNotNull,
          reason: 'run_id should match the pipeline stamp format',
        );
      });
    },
    skip: available
        ? null
        : 'Set SCREENER_DB_DIR to a directory holding us.db and asx.db.',
  );
}
