import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/stock_row.dart';
import 'package:screener/utils/formatters.dart';
import 'package:screener/utils/trend.dart';

import 'price_series_test.dart' show row;

void main() {
  group('GrowthWindow.fromTableName', () {
    test('maps both published prefixes', () {
      expect(
        GrowthWindow.fromTableName('us_stocks_growth_7_days'),
        GrowthWindow.sevenDays,
      );
      expect(
        GrowthWindow.fromTableName('asx_etf_growth_1_year'),
        GrowthWindow.oneYear,
      );
      expect(
        GrowthWindow.fromTableName('asx_etf_growth_3_months'),
        GrowthWindow.threeMonths,
      );
      expect(
        GrowthWindow.fromTableName('us_stocks_growth_6_months'),
        GrowthWindow.sixMonths,
      );
      expect(
        GrowthWindow.fromTableName('us_stocks_growth_1_month'),
        GrowthWindow.oneMonth,
      );
    });

    test('returns null for tables that are not growth tables', () {
      expect(GrowthWindow.fromTableName('consistent_growth_stocks'), isNull);
      expect(GrowthWindow.fromTableName('sqlite_sequence'), isNull);
    });
  });

  group('StockRow.fromMap', () {
    test('decodes a published row', () {
      final decoded = StockRow.fromMap(
        const {
          'ticker': 'MRNA',
          'name': 'Moderna, Inc. - Common Stock',
          'exchange': 'NASDAQ',
          'asset_type': 'common_stock',
          'first_date': '2026-08-14',
          'first_price': 63.89,
          'last_date': '2026-08-21',
          'latest_price': 139.225,
          'pct_change': 117.91,
          'observations': 6,
          'days_covered': 7,
          'coverage': 1.0,
          'observation_ratio': 1.0,
          'median_volume': 45924100.0,
          'price_basis': 'adjusted',
          'data_as_of': '2026-08-21',
          'run_id': '20260822T224430Z-a4761276',
          'google_finance': 'https://example.test',
        },
        market: Market.us,
        window: GrowthWindow.sevenDays,
      );

      expect(decoded.ticker, 'MRNA');
      expect(decoded.priceChange, closeTo(75.335, 0.0001));
      expect(decoded.isPositive, isTrue);
      expect(decoded.key, 'us:MRNA');
      expect(decoded.shortName, 'Moderna, Inc.');
    });

    test('survives integers, strings and nulls in numeric columns', () {
      final decoded = StockRow.fromMap(
        const {
          'ticker': 'TEST',
          'first_price': 10, // int, not double
          'latest_price': '12.5', // text
          'pct_change': null,
          'observations': 6.0, // double in an INTEGER column
          'median_volume': null,
        },
        market: Market.asx,
        window: GrowthWindow.oneMonth,
      );

      expect(decoded.firstPrice, 10.0);
      expect(decoded.latestPrice, 12.5);
      expect(decoded.pctChange, 0);
      expect(decoded.observations, 6);
      expect(decoded.medianVolume, 0);
      expect(decoded.name, 'TEST', reason: 'falls back to the ticker');
      expect(decoded.firstDate, isNull);
    });

    test('keeps names that have no exchange suffix intact', () {
      final decoded = StockRow.fromMap(
        const {'ticker': 'QETH', 'name': 'Betashares Ethereum ETF'},
        market: Market.asx,
        window: GrowthWindow.sevenDays,
      );
      expect(decoded.shortName, 'Betashares Ethereum ETF');
    });
  });

  group('assessTrend', () {
    test('flags a short window running hotter than the long one', () {
      // 117.91% over 7 days is far faster per day than 472.5% over 364.
      final trend = assessTrend([
        row(
          window: GrowthWindow.sevenDays,
          firstDate: '2026-08-14',
          firstPrice: 63.89,
          latestPrice: 139.225,
          pctChange: 117.91,
          daysCovered: 7,
        ),
        row(
          window: GrowthWindow.oneYear,
          firstDate: '2025-08-22',
          firstPrice: 25.35,
          latestPrice: 145.13,
          pctChange: 472.5,
          daysCovered: 364,
        ),
      ]);
      expect(trend.label, TrendLabel.accelerating);
      expect(trend.shortRatePerDay, greaterThan(trend.longRatePerDay));
    });

    test('calls an even pace steady', () {
      final trend = assessTrend([
        row(
          window: GrowthWindow.sevenDays,
          firstDate: '2026-08-14',
          firstPrice: 100,
          latestPrice: 107,
          pctChange: 7,
          daysCovered: 7,
        ),
        row(
          window: GrowthWindow.oneMonth,
          firstDate: '2026-07-21',
          firstPrice: 100,
          latestPrice: 131,
          pctChange: 31,
          daysCovered: 31,
        ),
      ]);
      expect(trend.label, TrendLabel.steady);
    });

    test('flags a short window lagging the long one', () {
      final trend = assessTrend([
        row(
          window: GrowthWindow.sevenDays,
          firstDate: '2026-08-14',
          firstPrice: 100,
          latestPrice: 101,
          pctChange: 1,
          daysCovered: 7,
        ),
        row(
          window: GrowthWindow.oneMonth,
          firstDate: '2026-07-21',
          firstPrice: 100,
          latestPrice: 131,
          pctChange: 31,
          daysCovered: 31,
        ),
      ]);
      expect(trend.label, TrendLabel.cooling);
    });

    test('needs two windows to say anything', () {
      final trend = assessTrend([
        row(
          window: GrowthWindow.sevenDays,
          firstDate: '2026-08-14',
          firstPrice: 100,
          latestPrice: 107,
          pctChange: 7,
        ),
      ]);
      expect(trend.label, TrendLabel.undetermined);
    });
  });

  group('Fmt', () {
    test('formats prices, percentages and volumes', () {
      // 139.225 is stored as a double slightly below the midpoint, so 139.22
      // is the honest rendering of the value the database holds.
      expect(Fmt.price(139.225), '139.22');
      expect(Fmt.price(0.125), '0.13', reason: 'exact halves round up');
      expect(Fmt.price(1234.5), '1,234.50');
      expect(Fmt.price(1234567.891), '1,234,567.89');
      expect(Fmt.price(-42.5), '-42.50');
      expect(
        Fmt.price(0.0451),
        '0.0451',
        reason: 'sub-cent prices keep digits',
      );
      expect(Fmt.signedPrice(75.335), '+75.33');
      expect(Fmt.signedPrice(-4.5), '-4.50');
      expect(Fmt.signedPercent(117.91), '+117.91%');
      expect(Fmt.signedPercent(-3.256, decimals: 1), '-3.3%');
      expect(Fmt.compact(45924100), '45.9M');
      expect(Fmt.compact(7518), '7.5K');
      expect(Fmt.compact(842), '842');
    });

    test('formats dates and falls back to the raw value', () {
      expect(Fmt.date('2026-08-21'), 'Aug 21, 2026');
      expect(Fmt.date(null), '—');
      expect(Fmt.date('sometime'), 'sometime');
    });

    test('relative stamps read as today, yesterday, then a date', () {
      final now = DateTime(2026, 8, 22, 18);
      expect(
        Fmt.relativeStamp(DateTime(2026, 8, 22, 9, 30), now: now),
        'Today, 9:30 AM',
      );
      expect(
        Fmt.relativeStamp(DateTime(2026, 8, 21, 9, 30), now: now),
        startsWith('Yesterday'),
      );
      expect(
        Fmt.relativeStamp(DateTime(2026, 7, 1, 9, 30), now: now),
        'Jul 1, 2026',
      );
    });
  });
}
