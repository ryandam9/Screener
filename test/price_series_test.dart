import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/price_series.dart';
import 'package:screener/models/stock_row.dart';

StockRow row({
  required GrowthWindow window,
  required String firstDate,
  required double firstPrice,
  required double latestPrice,
  String lastDate = '2026-08-21',
  double pctChange = 0,
  int daysCovered = 7,
}) {
  return StockRow(
    market: Market.us,
    window: window,
    ticker: 'MRNA',
    name: 'Moderna, Inc. - Common Stock',
    exchange: 'NASDAQ',
    assetType: 'common_stock',
    firstDate: firstDate,
    firstPrice: firstPrice,
    lastDate: lastDate,
    latestPrice: latestPrice,
    pctChange: pctChange,
    observations: 6,
    daysCovered: daysCovered,
    coverage: 1,
    observationRatio: 1,
    medianVolume: 1000,
    priceBasis: 'adjusted',
    dataAsOf: '2026-08-21',
    runId: 'run',
    googleFinanceUrl: null,
  );
}

void main() {
  // The real MRNA rows: each window contributes its opening price, and every
  // window closes on the same date.
  final rows = [
    row(
      window: GrowthWindow.sevenDays,
      firstDate: '2026-08-14',
      firstPrice: 63.89,
      latestPrice: 139.225,
    ),
    row(
      window: GrowthWindow.oneMonth,
      firstDate: '2026-07-21',
      firstPrice: 58.07,
      latestPrice: 145.13,
    ),
    row(
      window: GrowthWindow.threeMonths,
      firstDate: '2026-05-21',
      firstPrice: 47.03,
      latestPrice: 145.13,
    ),
    row(
      window: GrowthWindow.oneYear,
      firstDate: '2025-08-22',
      firstPrice: 25.35,
      latestPrice: 145.13,
    ),
  ];

  test('includes only windows that fit inside the selected one', () {
    final series = PriceSeries.build(rows, GrowthWindow.oneMonth);

    expect(
      [for (final p in series.points) p.date],
      [
        DateTime.parse('2026-07-21'),
        DateTime.parse('2026-08-14'),
        DateTime.parse('2026-08-21'),
      ],
      reason: '3M and 1Y start before the 1M window opens',
    );
  });

  test('the closing price comes from the selected window', () {
    // The 7-day row closes at 139.225 while the longer windows say 145.13.
    final sevenDay = PriceSeries.build(rows, GrowthWindow.sevenDays);
    expect(sevenDay.points.last.price, 139.225);
    expect(sevenDay.points.last.isEndpoint, isTrue);

    final oneYear = PriceSeries.build(rows, GrowthWindow.oneYear);
    expect(oneYear.points.last.price, 145.13);
  });

  test('points are ordered oldest to newest', () {
    final series = PriceSeries.build(rows, GrowthWindow.oneYear);
    expect(series.points, hasLength(5));
    for (var i = 1; i < series.points.length; i++) {
      expect(
        series.points[i].date.isAfter(series.points[i - 1].date),
        isTrue,
        reason: 'point $i is out of order',
      );
    }
    expect(series.minPrice, 25.35);
    expect(series.maxPrice, 145.13);
  });

  test('a window with no row yields an empty series', () {
    expect(PriceSeries.build(rows, GrowthWindow.sixMonths).isEmpty, isTrue);
    expect(PriceSeries.build(const [], GrowthWindow.sevenDays).isEmpty, isTrue);
  });

  test('a shorter window wins when two windows share a start date', () {
    final collided = [
      row(
        window: GrowthWindow.sevenDays,
        firstDate: '2026-08-14',
        firstPrice: 63.89,
        latestPrice: 139.225,
      ),
      row(
        window: GrowthWindow.oneMonth,
        firstDate: '2026-08-14',
        firstPrice: 60.00,
        latestPrice: 145.13,
      ),
    ];
    final series = PriceSeries.build(collided, GrowthWindow.oneMonth);
    expect(series.points.first.price, 63.89);
    expect(series.points.first.sourceWindow, GrowthWindow.sevenDays);
  });

  test('a single point has no shape to draw', () {
    final single = [
      row(
        window: GrowthWindow.sevenDays,
        firstDate: '2026-08-21',
        firstPrice: 63.89,
        latestPrice: 139.225,
        lastDate: '2026-08-21',
      ),
    ];
    // Opening and closing land on the same date, collapsing to one point.
    final series = PriceSeries.build(single, GrowthWindow.sevenDays);
    expect(series.points, hasLength(1));
    expect(series.hasShape, isFalse);
  });

  test('an unparseable date is skipped rather than throwing', () {
    final broken = [
      row(
        window: GrowthWindow.sevenDays,
        firstDate: 'not-a-date',
        firstPrice: 63.89,
        latestPrice: 139.225,
      ),
    ];
    final series = PriceSeries.build(broken, GrowthWindow.sevenDays);
    expect(series.points, hasLength(1));
    expect(series.points.single.isEndpoint, isTrue);
  });
}
